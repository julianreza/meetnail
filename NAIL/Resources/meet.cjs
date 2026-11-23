const electron = process.versions.electron ? require('electron') : {};
const { app, BrowserWindow } = electron;
const { mkdirSync, appendFileSync, writeFileSync } = require('node:fs');
const { appendFile, mkdtemp, readFile, rm, writeFile, stat } = require('node:fs/promises');
const { join } = require('node:path');
const { homedir, tmpdir } = require('node:os');
const { execFile, spawn } = require('node:child_process');
const { promisify } = require('node:util');
const { randomUUID } = require('node:crypto');
const { createInterface } = require('node:readline');
const { setTimeout: delay } = require('node:timers/promises');
const { CodexLiveSession } = require('./codex-voice.cjs');
const { createMeetAvatarController, listenForAvatarFrames, avatarSpeechTransition } = require('./meet-avatar.cjs');

function presentationRequestKind(text) {
  const question = String(text || '').toLowerCase();
  if (!/\b(layar|screen|slide|presentasi|presentation|screenshare|screen share)\b/u.test(question)) return null;
  if (/\b(grafik|graph|chart|diagram|gambar|visual|tata letak|layout)\b/u.test(question)) return 'visual';
  return /\b(baca|bacakan|tulis|tulisan|teks|text|error|kesalahan|tertulis)\b/u.test(question) ? 'text' : 'visual';
}

function shouldReadPresentation(platform, enabled, text) {
  return platform === 'meet' && enabled && presentationRequestKind(text) !== null;
}

function findMeetPresentation() {
  const matches = [];
  for (const video of document.querySelectorAll('video')) {
    if (video.readyState < 2) continue;
    const tile = video.closest('[data-tile-media-id]');
    const tileId = tile?.getAttribute('data-tile-media-id');
    if (!tileId || ![...tile.querySelectorAll('[aria-label],[title]')].some(element =>
      /\b(?:presentation|presentasi)\b/i.test(`${element.getAttribute('aria-label') || ''} ${element.getAttribute('title') || ''}`))) continue;
    const bounds = video.getBoundingClientRect();
    const tileBounds = tile.getBoundingClientRect();
    const x = Math.max(bounds.x, tileBounds.x, 0);
    const y = Math.max(bounds.y, tileBounds.y, 0);
    const right = Math.min(bounds.right, tileBounds.right);
    const bottom = Math.min(bounds.bottom, tileBounds.bottom);
    if (right - x < 50 || bottom - y < 50) continue;
    matches.push({
      tileId,
      rect: {x: Math.ceil(x), y: Math.ceil(y), width: Math.floor(right) - Math.ceil(x), height: Math.floor(bottom) - Math.ceil(y)},
    });
  }
  return matches.length === 1 ? matches[0] : null;
}

async function captureMeetPresentation(wc, signal) {
  if (signal?.aborted || wc.isDestroyed?.()) return null;
  const inspect = () => wc.executeJavaScript(`(${findMeetPresentation})()`);
  const before = await inspect();
  if (!before || signal?.aborted) return null;
  const image = await wc.capturePage(before.rect, {stayHidden: true});
  if (signal?.aborted || image.isEmpty()) return null;
  const after = await inspect();
  if (signal?.aborted || !after || before.tileId !== after.tileId ||
      JSON.stringify(before.rect) !== JSON.stringify(after.rect)) return null;
  return image.toPNG();
}

function createPresentationOCRBridge(emit) {
  const pending = new Map();
  return {
    recognize(image, signal) {
      if (signal?.aborted) return Promise.reject(new DOMException('Interrupted', 'AbortError'));
      return new Promise((resolve, reject) => {
        const id = randomUUID();
        const finish = (error, text) => {
          if (!pending.has(id)) return;
          pending.delete(id);
          clearTimeout(timer);
          signal?.removeEventListener('abort', onAbort);
          if (error) reject(error); else resolve(text);
        };
        const onAbort = () => finish(new DOMException('Interrupted', 'AbortError'));
        const timer = setTimeout(() => finish(new Error('presentation-ocr-timeout')), 15000);
        pending.set(id, finish);
        signal?.addEventListener('abort', onAbort, {once: true});
        emit(`presentation-ocr ${JSON.stringify({id, image: image.toString('base64')})}`);
      });
    },
    receive(response) {
      const finish = pending.get(typeof response?.id === 'string' ? response.id.toLowerCase() : '');
      if (!finish) return false;
      finish(response.error ? new Error('presentation-ocr-failed') : null, response.text || '');
      return true;
    },
  };
}

function attributeNotes(entries, startedAtMs, captions) {
  const normalize = text => (text.normalize('NFKC').toLowerCase().match(/[\p{L}\p{N}\p{M}]+/gu) ?? []).join(' ');
  const evidence = captions.map(({speaker, text, seenAtMs}) => ({
    speaker: speaker.trim(), text: ` ${normalize(text)} `, seenAtMs,
  }));
  return entries.map(({text, start, end, speaker}) => {
    const timestampMs = startedAtMs + start * 1000;
    const needle = normalize(text);
    const names = new Set();
    if (needle.split(' ').length >= 4) {
      const latest = startedAtMs + end * 1000 + 5000;
      for (const caption of evidence) {
        if (caption.speaker && caption.seenAtMs >= timestampMs - 1000 &&
            caption.seenAtMs <= latest && caption.text.includes(` ${needle} `)) names.add(caption.speaker);
      }
    }
    const label = Number.isSafeInteger(speaker) && speaker > 0 ? `Pembicara ${speaker}` : 'Pembicara tidak diketahui';
    return {text, timestampMs, speaker: names.size === 1 ? names.values().next().value : label};
  });
}

function createMeetingNotesMemory({maxEntries = 600} = {}) {
  const entries = [];
  let nextId = 1;
  const isSystemNotice = text => /^\[.*\]$/.test(text);
  const formatClock = timestampMs => {
    if (!Number.isFinite(timestampMs)) return '';
    const date = new Date(timestampMs);
    if (Number.isNaN(date.getTime())) return '';
    const hh = String(date.getHours()).padStart(2, '0');
    const mm = String(date.getMinutes()).padStart(2, '0');
    return `${hh}:${mm}`;
  };
  const formatEntry = entry => {
    const clock = formatClock(entry.timestampMs);
    const prefix = clock ? `[${clock}] ` : '';
    const hasSpeaker = Boolean(entry.speaker) && entry.speaker !== 'Pembicara tidak diketahui';
    const speaker = hasSpeaker ? `${entry.speaker}: ` : '';
    return `${prefix}${speaker}${entry.text}`;
  };
  const compactLines = (lines, maxChars) => {
    if (!lines.length || maxChars <= 0) return '';
    const joined = lines.join('\n');
    if (joined.length <= maxChars) return joined;
    const marker = '\n[... sebagian catatan tengah rapat dipadatkan ...]\n';
    if (maxChars <= marker.length + 20) return joined.slice(0, maxChars);

    const budget = maxChars - marker.length;
    const headBudget = Math.floor(budget * 0.35);
    const tailBudget = budget - headBudget;

    const head = [];
    let headLen = 0;
    let headEnd = 0;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const nextLen = headLen + (head.length ? 1 : 0) + line.length;
      if (nextLen <= headBudget) {
        head.push(line);
        headLen = nextLen;
        headEnd = i + 1;
      } else {
        break;
      }
    }
    if (head.length === 0 && headBudget > 0) {
      head.push(lines[0].slice(0, headBudget));
      headEnd = 1;
    }

    const tail = [];
    let tailLen = 0;
    for (let i = lines.length - 1; i >= headEnd; i--) {
      const line = lines[i];
      const nextLen = tailLen + (tail.length ? 1 : 0) + line.length;
      if (nextLen <= tailBudget) {
        tail.push(line);
        tailLen = nextLen;
      } else {
        break;
      }
    }
    if (tail.length === 0 && headEnd < lines.length && tailBudget > 0) {
      tail.push(lines[lines.length - 1].slice(-tailBudget));
    }
    tail.reverse();

    if (head.length && tail.length) return `${head.join('\n')}${marker}${tail.join('\n')}`;
    if (head.length) return head.join('\n').slice(0, maxChars);
    return tail.join('\n').slice(-maxChars);
  };

  function addEntry({text, speaker = null, timestampMs = Date.now(), kind = 'meeting'} = {}) {
    const cleaned = String(text ?? '').replace(/\s+/g, ' ').trim();
    if (!cleaned || isSystemNotice(cleaned)) return null;
    const cleanSpeaker = speaker ? String(speaker).replace(/\s+/g, ' ').trim() : null;
    const ts = Number.isFinite(timestampMs) ? timestampMs : Date.now();
    const last = entries[entries.length - 1];
    if (last && last.text === cleaned && last.kind === kind && last.speaker === cleanSpeaker && Math.abs(ts - last.timestampMs) <= 5000) {
      return null;
    }
    const entry = {id: nextId++, timestampMs: ts, speaker: cleanSpeaker, text: cleaned, kind};
    entries.push(entry);
    if (entries.length > maxEntries) {
      // Preserve earliest opening entries when evicting overflow from long meetings.
      const keepHead = Math.floor(maxEntries * 0.3);
      entries.splice(keepHead, entries.length - maxEntries);
    }
    return entry;
  }

  function addExchange({heard, reply, heardAtMs = Date.now(), replyAtMs = Date.now()} = {}) {
    if (typeof heard === 'string' && heard.trim()) {
      addEntry({text: heard, speaker: 'Peserta', timestampMs: heardAtMs, kind: 'command'});
    }
    if (typeof reply === 'string' && reply.trim()) {
      addEntry({text: reply, speaker: 'Nail', timestampMs: replyAtMs, kind: 'reply'});
    }
  }

  function buildSnapshot(maxChars = 10_000, {excludeKinds = []} = {}) {
    const exclude = excludeKinds.length ? new Set(excludeKinds) : null;
    const lines = (exclude ? entries.filter(e => !exclude.has(e.kind)) : entries).map(formatEntry);
    return compactLines(lines, maxChars);
  }

  function drainDelta(sinceCursor = 0, maxChars = 4000, {excludeKinds = []} = {}) {
    const nextCursor = entries.length ? entries[entries.length - 1].id : sinceCursor;
    const exclude = excludeKinds.length ? new Set(excludeKinds) : null;
    const filtered = entries.filter(e => e.id > sinceCursor && (!exclude || !exclude.has(e.kind)));
    return {
      text: compactLines(filtered.map(formatEntry), maxChars),
      nextCursor,
      count: filtered.length,
    };
  }

  return {
    addEntry,
    addExchange,
    buildSnapshot,
    drainDelta,
    latestCursor: () => (entries.length ? entries[entries.length - 1].id : 0),
    count: () => entries.length,
  };
}

function detectPlatform(target) {
  if (typeof target !== 'string') return null;
  if (/^https:\/\/meet\.google\.com\/[a-z]{3}-[a-z]{4}-[a-z]{3}$/.test(target)) return 'meet';
  if (!URL.canParse(target)) return null;
  const url = new URL(target);
  if (url.protocol !== 'https:') return null;
  const host = url.hostname.toLowerCase();
  if ((host === 'teams.microsoft.com' || host === 'teams.live.com' || host === 'teams.cloud.microsoft') &&
      /^\/(l\/meetup-join\/|meet\/|dl\/launcher\/|v2\/)/.test(url.pathname)) {
    return 'teams';
  }
  return null;
}

function isAllowedTeamsHost(hostname) {
  if (typeof hostname !== 'string') return false;
  const host = hostname.toLowerCase().replace(/\.$/, '');
  return host === 'teams.microsoft.com' || host.endsWith('.teams.microsoft.com')
    || host === 'teams.live.com' || host.endsWith('.teams.live.com')
    || host === 'teams.cloud.microsoft' || host === 'm365.cloud.microsoft' || host.endsWith('.cloud.microsoft')
    || host.endsWith('.office.net') || host.endsWith('.office.com')
    || host === 'go.microsoft.com' || host === 'aka.ms';
}

function buildTeamsLightLaunchURL(target) {
  if (typeof target !== 'string' || !URL.canParse(target)) return null;
  const url = new URL(target);
  if (url.protocol !== 'https:' || url.hostname.toLowerCase() !== 'teams.live.com') return null;
  const match = url.pathname.match(/^\/meet\/([^/?#]+)/);
  if (!match) return null;
  let meetingCode;
  try { meetingCode = decodeURIComponent(match[1]); } catch { meetingCode = match[1]; }
  if (!meetingCode) return null;
  const passcode = url.searchParams.get('p') || '';
  const coords = Buffer.from(JSON.stringify({meetingUrl: target, meetingCode, passcode})).toString('base64');
  const params = new URLSearchParams();
  if (passcode) params.set('p', passcode);
  params.set('anon', 'true');
  params.set('v', '.jlw');
  params.set('launchType', 'web');
  params.set('launchAgent', 'join_launcher_web');
  params.set('lightExperience', 'true');
  params.set('agent', 'web');
  params.set('coords', coords);
  return `https://teams.live.com/light-meetings/launch?${params.toString()}`;
}

function inspectTeams() {
  document.body?.dispatchEvent(new MouseEvent('mousemove', {bubbles: true, clientX: 200, clientY: 200}));
  const norm = s => String(s || '').replace(/\s+/g, ' ').trim();
  const roots = [document];
  const seenRoots = new Set(roots);
  const queue = [document];
  while (queue.length) {
    const root = queue.shift();
    let all = [];
    try { all = [...(root.querySelectorAll?.('*') || [])]; } catch {}
    for (const el of all) {
      if (el?.shadowRoot && !seenRoots.has(el.shadowRoot)) {
        seenRoots.add(el.shadowRoot);
        roots.push(el.shadowRoot);
        queue.push(el.shadowRoot);
      }
    }
  }
  const queryAllDeep = selector => {
    const out = [];
    const seen = new Set();
    for (const root of roots) {
      let list = [];
      try { list = [...(root.querySelectorAll?.(selector) || [])]; } catch {}
      for (const el of list) {
        if (el && !seen.has(el)) { seen.add(el); out.push(el); }
      }
    }
    return out;
  };
  const label = element => {
    const rootNode = element.getRootNode?.();
    const labelled = (element.getAttribute('aria-labelledby') || '').split(/\s+/).filter(Boolean)
      .map(id => rootNode?.getElementById?.(id)?.textContent || document.getElementById?.(id)?.textContent || '')
      .join(' ');
    return norm(labelled) || norm(element.getAttribute('aria-label') || element.getAttribute('title') || element.innerText || element.textContent || '');
  };
  const controls = queryAllDeep('button,[role=button],a,[role=switch],[role=radio],input[type=checkbox],input[type=radio]');
  const visible = element => {
    if (!element || (element.getClientRects?.().length ?? 0) <= 0) return false;
    if (typeof getComputedStyle === 'function') {
      const st = getComputedStyle(element);
      if (st?.visibility === 'hidden' || st?.display === 'none') return false;
    }
    return true;
  };
  const disabled = element => Boolean(element?.matches?.(':disabled,[aria-disabled="true"]'));
  const escapeId = id => (typeof CSS !== 'undefined' && typeof CSS.escape === 'function') ? CSS.escape(id) : id;
  const toTarget = (element, selector) => {
    if (!element) return null;
    const r = element.getBoundingClientRect();
    const tid = element.getAttribute('data-tid');
    return {
      x: r.x + r.width / 2,
      y: r.y + r.height / 2,
      name: label(element),
      selector: selector || (tid ? `[data-tid=${JSON.stringify(tid)}]` : element.id ? `#${escapeId(element.id)}` : null),
    };
  };
  const matchName = (text, names) => {
    const lower = norm(text).toLowerCase();
    return names.some(n => {
      const nl = n.toLowerCase();
      return lower === nl || lower.startsWith(`${nl} (`) || lower.startsWith(`${nl} `) || lower.startsWith(`${nl},`);
    });
  };
  const findBtn = ({selectors = [], names = [], matchRe = null, predicate = () => true} = {}) => {
    for (const sel of selectors) {
      for (const el of queryAllDeep(sel)) {
        if (visible(el) && !disabled(el) && predicate(el, label(el))) {
          return toTarget(el, sel);
        }
      }
    }
    if (matchRe) {
      const el = controls.find(e => !disabled(e) && visible(e) && matchRe.test(label(e)) && predicate(e, label(e)));
      if (el) return toTarget(el, null);
    }
    if (!names.length) return null;
    const el = controls.find(e => !disabled(e) && visible(e) && matchName(label(e), names) && predicate(e, label(e)));
    return toTarget(el, null);
  };

  const inputLabelText = i => {
    if (!i?.id) return '';
    const esc = escapeId(i.id);
    const lbl = queryAllDeep(`label[for="${esc}"]`)[0];
    return lbl ? norm(lbl.innerText || lbl.textContent || '') : '';
  };
  const isTextLikeInput = i => !/^(hidden|button|submit|reset|checkbox|radio|password|email|file|image)$/i.test(String(i.type || 'text').trim());
  const nameCandidates = [
    ...queryAllDeep('input[data-tid="prejoin-display-name-input"]'),
    ...queryAllDeep('input#username'),
    ...queryAllDeep('input[name="username"]'),
    ...queryAllDeep('input[name="name"]'),
    ...queryAllDeep('input').filter(i =>
      isTextLikeInput(i) &&
      /type your name|enter your name|your name|display name|ketik nama|masukkan nama|nama anda|nama tampilan|\bname\b|\bnama\b/i.test(
        norm(`${i.getAttribute('placeholder') || ''} ${i.getAttribute('aria-label') || ''} ${i.getAttribute('data-tid') || ''} ${i.id || ''} ${i.name || ''} ${inputLabelText(i)}`)
      )
    ),
  ];
  const nameEl = nameCandidates.find(el => el && visible(el) && !disabled(el) && isTextLikeInput(el));

  const leave = findBtn({
    selectors: ['[data-tid="hangup-main-btn"]', '[data-tid="call-hangup"]', '[data-tid="calling-hangup-button"]', '#hangup-button'],
    names: ['Leave', 'Hang up', 'Keluar', 'Tutup panggilan', 'Tinggalkan'],
  });

  const isUnmuteLabel = text => /^(unmute|turn on microphone|nyalakan (suara|mikrofon)|aktifkan mikrofon|suarakan)/i.test(text);
  const isMuteLabel = text => /^(mute|turn off microphone|bisukan|matikan mikrofon|nonaktifkan mikrofon)/i.test(text);
  const isCheckedTrue = el => el.checked === true || el.getAttribute('aria-checked') === 'true' || el.getAttribute('aria-pressed') === 'true';
  const isCheckedFalse = el => (el.tagName === 'INPUT' && el.checked === false) || el.getAttribute('aria-checked') === 'false' || el.getAttribute('aria-pressed') === 'false';

  const micSel = ['#mic-button', '[data-tid="toggle-mute"]', '[data-tid="prejoin-mic-button"]', '#microphone-button'];
  const unmute = findBtn({
    selectors: micSel,
    names: ['Unmute', 'Turn on microphone', 'Nyalakan suara', 'Aktifkan mikrofon', 'Suarakan'],
    predicate: (el, text) => isUnmuteLabel(text) || (!isMuteLabel(text) && isCheckedFalse(el)),
  });
  const mute = findBtn({
    selectors: micSel,
    names: ['Mute', 'Turn off microphone', 'Bisukan', 'Matikan mikrofon', 'Nonaktifkan mikrofon'],
    predicate: (el, text) => isMuteLabel(text) || (!isUnmuteLabel(text) && isCheckedTrue(el)),
  });

  const cameraOn = findBtn({
    selectors: ['[data-tid="toggle-video"]', '[data-tid="prejoin-video-button"]', '#video-button'],
    names: ['Turn camera off', 'Matikan kamera'],
    predicate: (el, text) => /^(turn camera off|matikan kamera)/i.test(text) ||
      (!/^(turn camera on|nyalakan kamera)/i.test(text) && isCheckedTrue(el)),
  });

  const continueWeb = findBtn({
    selectors: [
      '[data-tid="joinOnWeb"]',
      '[data-tid="continueOnBrowser"]',
      '[data-tid="continue-on-web"]',
      '[data-tid="openInWeb"]',
      '[data-tid="browser-join-btn"]',
      'button[data-tid*="browser" i]',
      'a[data-tid*="browser" i]',
      'button[data-tid*="joinOnWeb" i]',
    ],
    matchRe: /continue on this browser|join on the web|use the web app|open in (this )?browser|lanjutkan di browser|bergabung di web|gabung di web|gunakan aplikasi web/i,
    names: ['Continue on this browser', 'Join on the web instead', 'Lanjutkan di browser ini', 'Bergabung di web'],
  });
  const enter = findBtn({
    selectors: ['[data-tid="prejoin-join-button"]', 'button[data-tid="join-btn"]', '[data-tid="prejoin-join-btn"]'],
    names: ['Join now', 'Gabung sekarang', 'Bergabung sekarang', 'Join meeting', 'Gabung rapat', 'Ask to join', 'Minta bergabung', 'Join as a guest', 'Gabung sebagai tamu'],
  });
  const computerAudio = findBtn({
    selectors: ['[data-tid="prejoin-audio-computer"]'],
    names: ['Computer audio', 'Audio komputer'],
    predicate: el => el.checked !== true && el.getAttribute('aria-checked') !== 'true' && el.getAttribute('aria-selected') !== 'true',
  });
  const dismiss = findBtn({
    names: ['Got it', 'Accept', 'Dismiss', 'OK', 'Oke', 'Mengerti', 'Terima', 'Not now', 'Lain kali'],
  });

  const rawText = document.body?.innerText ?? document.body?.textContent ?? '';
  const bodyText = norm(rawText);
  return {
    continueWeb,
    dismiss,
    computerAudio,
    cameraOn,
    prejoinMicOn: !leave ? mute : null,
    nameInput: nameEl ? {present: true, value: (nameEl.value || '').trim()} : {present: false, value: ''},
    enter,
    leave,
    unmute,
    mute,
    waiting: /someone in the meeting should let you in|when the meeting starts|let people.*know you['’]?re waiting|waiting in the lobby|seseorang di rapat.*mengizinkan|menunggu di lobi/i.test(bodyText),
    rejected: /denied access|couldn['’]t be admitted|wasn['’]t admitted|you were removed|akses.*ditolak|tidak dapat masuk/i.test(bodyText),
    signInOnly: !continueWeb && !nameEl && !enter && !leave &&
      /sign in to join|masuk untuk bergabung|you need to sign in/i.test(bodyText),
    hasBodyText: bodyText.slice(0, 200),
  };
}

function fillTeamsName(name) {
  const norm = s => String(s || '').replace(/\s+/g, ' ').trim();
  const roots = [document];
  const seenRoots = new Set(roots);
  const queue = [document];
  while (queue.length) {
    const root = queue.shift();
    let all = [];
    try { all = [...(root.querySelectorAll?.('*') || [])]; } catch {}
    for (const el of all) {
      if (el?.shadowRoot && !seenRoots.has(el.shadowRoot)) {
        seenRoots.add(el.shadowRoot);
        roots.push(el.shadowRoot);
        queue.push(el.shadowRoot);
      }
    }
  }
  const queryAllDeep = selector => {
    const out = [];
    const seen = new Set();
    for (const root of roots) {
      let list = [];
      try { list = [...(root.querySelectorAll?.(selector) || [])]; } catch {}
      for (const el of list) {
        if (el && !seen.has(el)) { seen.add(el); out.push(el); }
      }
    }
    return out;
  };
  const visible = element => {
    if (!element || (element.getClientRects?.().length ?? 0) <= 0) return false;
    if (typeof getComputedStyle === 'function') {
      const st = getComputedStyle(element);
      if (st?.visibility === 'hidden' || st?.display === 'none') return false;
    }
    return true;
  };
  const disabled = element => Boolean(element?.matches?.(':disabled,[aria-disabled="true"]'));
  const escapeId = id => (typeof CSS !== 'undefined' && typeof CSS.escape === 'function') ? CSS.escape(id) : id;
  const inputLabelText = i => {
    if (!i?.id) return '';
    const esc = escapeId(i.id);
    const lbl = queryAllDeep(`label[for="${esc}"]`)[0];
    return lbl ? norm(lbl.innerText || lbl.textContent || '') : '';
  };
  const isTextLikeInput = i => !/^(hidden|button|submit|reset|checkbox|radio|password|email|file|image)$/i.test(String(i.type || 'text').trim());
  const el = [
    ...queryAllDeep('input[data-tid="prejoin-display-name-input"]'),
    ...queryAllDeep('input#username'),
    ...queryAllDeep('input[name="username"]'),
    ...queryAllDeep('input[name="name"]'),
    ...queryAllDeep('input').filter(i =>
      isTextLikeInput(i) &&
      /type your name|enter your name|your name|display name|ketik nama|masukkan nama|nama anda|nama tampilan|\bname\b|\bnama\b/i.test(
        norm(`${i.getAttribute('placeholder') || ''} ${i.getAttribute('aria-label') || ''} ${i.getAttribute('data-tid') || ''} ${i.id || ''} ${i.name || ''} ${inputLabelText(i)}`)
      )
    ),
  ].find(candidate => candidate && visible(candidate) && !disabled(candidate) && isTextLikeInput(candidate));
  if (!el) return false;
  el.focus();
  try { el._valueTracker?.setValue?.(''); } catch {}
  const setter = typeof HTMLInputElement !== 'undefined'
    ? Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set
    : null;
  if (setter) {
    try { setter.call(el, name); } catch { el.value = name; }
  } else {
    el.value = name;
  }
  try {
    if (typeof InputEvent === 'function') {
      el.dispatchEvent(new InputEvent('input', {bubbles: true, data: name, inputType: 'insertText'}));
    } else {
      el.dispatchEvent(new Event('input', {bubbles: true}));
    }
  } catch {
    el.dispatchEvent(new Event('input', {bubbles: true}));
  }
  el.dispatchEvent(new Event('change', {bubbles: true}));
  return (el.value || '').trim() === name;
}

function meetAvatarCameraAction(state, enabled, clicked, resetRequested) {
  if (clicked) return null;
  if (!enabled) return state.disableCamera;
  if (state.cameraEnabled) return resetRequested ? null : state.disableCamera;
  return state.enableCamera;
}

function inspectMeet() {
  const label = element => (element.getAttribute('aria-labelledby') || '').split(/\s+/)
    .map(id => document.getElementById(id)?.textContent || '').join(' ').trim() ||
    (element.getAttribute('aria-label') || element.innerText || '').trim();
  const controls = [...document.querySelectorAll('button,[role=button],a')];
  const visible = element => element.getClientRects().length > 0 && getComputedStyle(element).visibility === 'visible';
  const matchesLabel = (element, names) => {
    const text = label(element);
    return names.some(name => text === name || text.startsWith(`${name} (`));
  };
  const action = (names, candidates = controls) => {
    const element = candidates.find(e => matchesLabel(e, names) && !e.matches(':disabled,[aria-disabled="true"]') && visible(e) && (() => {
      const r = e.getBoundingClientRect();
      return e.contains(document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2));
    })());
    if (!element) return null;
    const r = element.getBoundingClientRect();
    return {x: r.x + r.width / 2, y: r.y + r.height / 2, name: label(element)};
  };
  const enableCameraLabels = ['Turn on camera', 'Aktifkan kamera', 'Nyalakan kamera'];
  const disableCameraLabels = ['Turn off camera', 'Nonaktifkan kamera', 'Matikan kamera'];
  const leaveLabels = ['Leave call', 'Tutup panggilan'];
  const headings = [...document.querySelectorAll('h1,h2,[role=heading]')];
  const blockedCameraLabels = ['Kamera mungkin diblokir', 'Camera may be blocked', 'Your camera may be blocked'];
  const cameraNotice = headings.find(element => visible(element) && matchesLabel(element,
    ['Kamera tidak tersedia', 'Camera unavailable', 'Camera is unavailable', ...blockedCameraLabels]));
  let dismissCameraNotice = null;
  if (cameraNotice) {
    const blocked = matchesLabel(cameraNotice, blockedCameraLabels);
    let scope = cameraNotice.closest('dialog,[role=dialog],[role=alertdialog]') ?? cameraNotice.parentElement;
    for (let depth = 0; scope && scope !== document.body && depth < 4; depth++, scope = scope.parentElement) {
      const buttons = [...scope.querySelectorAll('button,[role=button]')];
      if (!blocked && !buttons.some(button => visible(button) && matchesLabel(button, ['Coba lagi', 'Try again']))) continue;
      dismissCameraNotice = action(['Tutup', 'Close'], buttons);
      if (dismissCameraNotice) break;
    }
  }
  const text = document.body?.innerText ?? '';
  return {
    signedIn: controls.some(e => /^(Switch account|Change account|Switch Google Account|Ganti akun)$/i.test(label(e)) && visible(e)),
    signIn: action(['Sign in', 'Sign in with Google', 'Login', 'Masuk', 'Masuk dengan Google']),
    skip: action(['Continue without microphone and camera', 'Lanjutkan tanpa mikrofon dan kamera']),
    dismiss: action(['Got it', 'Mengerti', 'Oke']),
    unmute: action(['Turn on microphone', 'Aktifkan mikrofon', 'Nyalakan mikrofon']),
    mute: action(['Turn off microphone', 'Nonaktifkan mikrofon']),
    cameraEnabled: controls.some(element => visible(element) && matchesLabel(element, disableCameraLabels)),
    enableCamera: action(enableCameraLabels),
    disableCamera: action(disableCameraLabels),
    dismissCameraNotice,
    enter: action(['Join now', 'Join meeting', 'Ask to join', 'Gabung sekarang', 'Bergabung sekarang',
      'Minta bergabung', 'Minta untuk bergabung', 'Join now without camera', 'Ask to join without camera',
      'Gabung sekarang tanpa kamera', 'Bergabung sekarang tanpa kamera', 'Minta bergabung tanpa kamera',
      'Minta untuk bergabung tanpa kamera']),
    leave: action(leaveLabels),
    inCall: controls.some(element => visible(element) && matchesLabel(element, leaveLabels)),
    rejected: headings.some(e => visible(e) &&
      /^(You can[’']t join this video call|Anda tidak (dapat|bisa) bergabung.*)$/i.test(label(e))),
    waiting: /Asking to join|Someone in the meeting should let you in|Waiting for (the )?host|Menunggu.*(penyelenggara|host)|Meminta untuk bergabung/i.test(text),
  };
}

if (process.versions.electron) {
  const [target, profile, provider, pipeline] = process.argv.slice(2);
  const login = target === '--login';
  const platform = detectPlatform(target);
  if (!profile || (!login && !platform)) process.exit(2);
  if (provider && provider !== 'codex' && ((provider !== 'deepseek' && provider !== 'antigravity') || !pipeline)) process.exit(2);

  let runtimeConfig = {};
  try {
    if (process.env.NAIL_VOICE_CONFIG) runtimeConfig = JSON.parse(process.env.NAIL_VOICE_CONFIG);
  } catch {}

  mkdirSync(profile, {recursive: true, mode: 0o700});
  app.setPath('userData', profile);
  app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');
  const avatarSocketPath = platform === 'meet' && provider && !login ? process.env.NAIL_AVATAR_SOCKET_PATH : null;
  let avatarController;
  let avatarServer;
  let avatarTimer;
  let avatarRevision = 0;
  let avatarTurn = 0;
  let avatarSpeaking = false;
  let avatarUnmuted = false;
  let avatarOn = false;
  const emitAvatarAudio = (rms, sending) => {
    if (avatarRevision && avatarOn) console.log(`avatar-audio ${JSON.stringify({revision: avatarRevision, turn: avatarTurn, rms, sending})}`);
  };
  const emit = event => {
    console.log(event);
    if (!avatarSocketPath) return;
    const transition = avatarSpeechTransition(event);
    if (transition === 'start') {
      avatarTurn++;
      avatarSpeaking = true;
    } else if (avatarSpeaking && transition === 'stop') {
      avatarSpeaking = false;
      emitAvatarAudio(0, false);
    }
  };
  const closeAvatar = () => {
    clearInterval(avatarTimer);
    avatarOn = false;
    avatarServer?.close();
    avatarServer = null;
    void avatarController?.close();
    avatarController = null;
  };
  const presentationOCR = createPresentationOCRBridge(emit);

  let stopping = false;
  let finalized = false;
  let shutdownFailsafe = null;
  function killWorkerProcess(worker) {
    if (!worker) return;
    try { worker.stdin?.end(); } catch {}
    if (process.platform !== 'win32' && worker.pid) {
      try { process.kill(-worker.pid, 'SIGTERM'); } catch {}
    }
    try { worker.kill('SIGTERM'); } catch {}
  }
  const consoleLogs = [];
  const logDir = join(homedir(), 'Library/Logs/Nail');
  const teamsLogPath = join(logDir, 'teams-debug.log');
  const appendTeamsLog = line => {
    if (platform !== 'teams') return;
    try {
      mkdirSync(logDir, {recursive: true});
      appendFileSync(teamsLogPath, `${new Date().toISOString()} ${line}\n`);
    } catch {}
  };
  if (platform === 'teams') {
    try {
      mkdirSync(logDir, {recursive: true});
      writeFileSync(
        teamsLogPath,
        `${new Date().toISOString()} START target=${target} provider=${provider ?? 'none'} voice=${runtimeConfig.codexVoice ?? ''} style=${runtimeConfig.speakingStyle ?? ''}\n`
      );
    } catch {}
  }
  const cancelVoice = new AbortController();
  let turnRequested = false;
  let turnInterrupted = false;
  let presentationReadingEnabled = runtimeConfig.presentationReadingEnabled === true;
  let activePresentationAbort = null;
  let followUpUntil = 0;
  let listeningMode = runtimeConfig.listeningMode === 'notulen' ? 'notulen' : 'standby';
  const meetingNotes = createMeetingNotesMemory();
  const codexHandsFree = provider === 'codex' && runtimeConfig.codexHandsFree !== false;
  const codexSession = provider === 'codex'
    ? new CodexLiveSession({voice: runtimeConfig.codexVoice, speakingStyle: runtimeConfig.speakingStyle, notesMemory: meetingNotes})
    : null;

  let codexWakeWorker = null;
  let codexWakeReady = null;
  let codexWakeNextLine = null;
  let codexWakeQueue = Promise.resolve();
  let codexWakeFailed = false;
  let codexWakeUnavailableEmitted = false;
  let activeCodexWakeAbort = null;
  function stopCodexWakeDaemon() {
    const worker = codexWakeWorker;
    codexWakeWorker = null;
    codexWakeReady = null;
    codexWakeNextLine = null;
    killWorkerProcess(worker);
  }
  function startCodexWakeDaemon() {
    if (provider !== 'codex' || (!codexHandsFree && !presentationReadingEnabled) || codexWakeFailed || stopping) {
      return Promise.reject(new Error('codex wake daemon unavailable'));
    }
    if (codexWakeReady) return codexWakeReady;
    const configuredModel = runtimeConfig.whisperModel || 'small';
    const spawnWakeWorker = (modelName, allowFallback) => {
      if (provider !== 'codex' || (!codexHandsFree && !presentationReadingEnabled) || codexWakeFailed || stopping) {
        return Promise.reject(new Error('codex wake daemon unavailable'));
      }
      const env = {...process.env, PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.HOME}/.local/bin:${process.env.PATH ?? '/usr/bin:/bin'}`};
      const worker = spawn('/opt/homebrew/bin/uv', [
        'run', '--offline', '--script', join(__dirname, 'agy-voice.py'),
        '--transcribe-daemon', '--whisper-model', modelName,
        '--cpu-threads', '2',
      ], {env, stdio: ['pipe', 'pipe', 'ignore'], detached: process.platform !== 'win32'});
      codexWakeWorker = worker;
      const lines = createInterface({input: worker.stdout, terminal: false});
      const responses = [];
      const waiters = [];
      let exited = null;
      let booted = false;
      const rejectWaiters = error => {
        exited = error;
        while (waiters.length) waiters.shift().reject(error);
        if (codexWakeWorker === worker) {
          codexWakeWorker = null;
          codexWakeNextLine = null;
          if (booted) codexWakeReady = null;
        }
      };
      worker.on('error', rejectWaiters);
      worker.on('exit', code => rejectWaiters(new Error(`codex wake daemon exited (${code})`)));
      worker.stdin.on('error', rejectWaiters);
      lines.on('line', line => {
        const waiter = waiters.shift();
        if (waiter) waiter.resolve(line);
        else responses.push(line);
      });
      const nextLine = () => responses.length ? Promise.resolve(responses.shift()) :
        exited ? Promise.reject(exited) : new Promise((resolve, reject) => waiters.push({resolve, reject}));
      codexWakeNextLine = nextLine;
      return nextLine().then(line => {
        const res = JSON.parse(line);
        if (!res.ready) throw new Error(res.error || 'codex wake daemon failed to start');
        booted = true;
        return res;
      }).catch(error => {
        if (codexWakeWorker === worker) {
          codexWakeWorker = null;
          codexWakeNextLine = null;
        }
        try { worker.stdin.end(); } catch {}
        try { worker.kill(); } catch {}
        if (allowFallback && modelName !== configuredModel && !stopping && !codexWakeFailed) {
          return spawnWakeWorker(configuredModel, false);
        }
        throw error;
      });
    };
    const readyPromise = spawnWakeWorker('base', configuredModel !== 'base').catch(error => {
      codexWakeFailed = true;
      stopCodexWakeDaemon();
      if (!codexWakeUnavailableEmitted) {
        codexWakeUnavailableEmitted = true;
        emit('voice-codex-wake-unavailable');
      }
      throw error;
    });
    codexWakeReady = readyPromise;
    return readyPromise;
  }
  function checkCodexWake(audioPath, mode = 'wake') {
    const runCheck = async () => {
      await startCodexWakeDaemon();
      if (!codexWakeWorker?.stdin?.writable || !codexWakeNextLine) {
        throw new Error('codex wake daemon not ready');
      }
      const response = codexWakeNextLine();
      codexWakeWorker.stdin.write(`${JSON.stringify({audio: audioPath, mode})}\n`);
      const result = JSON.parse(await response);
      if (result.error) throw new Error(result.error);
      return result;
    };
    const next = codexWakeQueue.then(runCheck, runCheck);
    codexWakeQueue = next.catch(() => {});
    return next;
  }

  let agyDaemon = null;
  let agyLines = null;
  let agyReady = null;
  let agySyncedNoteCursor = 0;
  function startAgyDaemon() {
    if (provider !== 'antigravity' || agyDaemon) return;
    const env = {...process.env, PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.HOME}/.local/bin:${process.env.PATH ?? '/usr/bin:/bin'}`};
    const daemonArgs = ['run', '--offline', '--script', pipeline, '--daemon'];
    if (runtimeConfig.whisperModel) daemonArgs.push('--whisper-model', String(runtimeConfig.whisperModel));
    if (runtimeConfig.agyModel) daemonArgs.push('--agy-model', String(runtimeConfig.agyModel));
    if (runtimeConfig.ttsVoice) daemonArgs.push('--tts-voice', String(runtimeConfig.ttsVoice));
    if (runtimeConfig.ttsRate) daemonArgs.push('--tts-rate', String(runtimeConfig.ttsRate));
    if (runtimeConfig.ttsEngine) daemonArgs.push('--tts-engine', String(runtimeConfig.ttsEngine));
    if (runtimeConfig.elevenLabsVoiceId) daemonArgs.push('--elevenlabs-voice-id', String(runtimeConfig.elevenLabsVoiceId));
    if (runtimeConfig.elevenLabsModel) daemonArgs.push('--elevenlabs-model', String(runtimeConfig.elevenLabsModel));
    if (runtimeConfig.speakingStyle) daemonArgs.push('--speaking-style', String(runtimeConfig.speakingStyle));

    agyDaemon = spawn('/opt/homebrew/bin/uv', daemonArgs, {env, stdio: ['pipe', 'pipe', 'ignore'], detached: process.platform !== 'win32'});
    const rl = createInterface({input: agyDaemon.stdout, terminal: false});
    const waiters = [];
    const responses = [];
    rl.on('line', line => { const w = waiters.shift(); if (w) w.resolve(line); else responses.push(line); });
    agyDaemon.on('exit', () => {
      while (waiters.length) waiters.shift().reject(new Error('agy daemon exited'));
      agyDaemon = null; agyLines = null; agyReady = null; agySyncedNoteCursor = 0;
    });
    agyLines = () => responses.length ? Promise.resolve(responses.shift()) : new Promise((resolve, reject) => waiters.push({resolve, reject}));
    agyReady = agyLines().then(line => JSON.parse(line));
  }

  let meetingJoined = false;
  let notesTask = null;
  let notesWorker = null;
  let notesFailed = false;
  let nextNotesSpeaker = 1;
  function stopNotesWorker() {
    const worker = notesWorker;
    notesWorker = null;
    killWorkerProcess(worker);
  }
  const emitNotes = lines => {
    if (Array.isArray(lines)) {
      for (const item of lines) {
        if (item && typeof item.text === 'string') {
          meetingNotes.addEntry({
            text: item.text,
            speaker: item.speaker ?? null,
            timestampMs: item.timestampMs ?? Date.now(),
            kind: 'meeting',
          });
        }
      }
    }
    emit(`voice-notulen-codex ${JSON.stringify(lines)}`);
  };
  function syncCodexNotes() {
    if (provider !== 'codex' || !meetingJoined || listeningMode !== 'notulen' || stopping || notesTask || notesFailed) return;
    notesTask = recordCodexNotes().catch(async error => {
      if (stopping) return;
      notesFailed = true;
      emitNotes([{text: '[Pencatatan terputus: sebagian percakapan mungkin tidak tercatat.]'}]);
      emit('notes-error');
      await logVoiceError(error);
    }).finally(() => {
      notesTask = null;
      if (!notesFailed && !stopping) syncCodexNotes();
    });
  }

  async function recordCodexNotes() {
    const wc = activeWc;
    const dir = await mkdtemp(join(tmpdir(), 'nail-notulen-'));
    let sequence = 0;
    let pending = Promise.resolve();
    let failure = null;
    let hadTracks = false;
    let trackGap = false;
    const env = {...process.env, PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.HOME}/.local/bin:${process.env.PATH ?? '/usr/bin:/bin'}`};
    const models = join(homedir(), 'Library/Application Support/Nail/Speaker Models v1');
    env.PYTHONPATH = join(models, 'python');
    const worker = spawn('/opt/homebrew/bin/uv', [
      'run', '--offline', '--script', join(__dirname, 'agy-voice.py'),
      '--transcribe-daemon', '--whisper-model', runtimeConfig.whisperModel || 'small',
      '--cpu-threads', '2',
      '--speaker-models', models, '--first-speaker', String(nextNotesSpeaker),
    ], {env, stdio: ['pipe', 'pipe', 'pipe'], detached: process.platform !== 'win32'});
    notesWorker = worker;
    const lines = createInterface({input: worker.stdout, terminal: false});
    const responses = [];
    const waiters = [];
    let exited = null;
    function rejectWaiters(error) {
      exited = error;
      while (waiters.length) waiters.shift().reject(error);
    }
    worker.on('error', rejectWaiters);
    worker.on('exit', code => rejectWaiters(new Error(`transcription worker exited (${code})`)));
    worker.stderr.resume();
    lines.on('line', line => {
      const waiter = waiters.shift();
      if (waiter) waiter.resolve(line);
      else responses.push(line);
    });
    const nextLine = () => responses.length ? Promise.resolve(responses.shift()) :
      exited ? Promise.reject(exited) : new Promise((resolve, reject) => waiters.push({resolve, reject}));
    const ready = nextLine().then(line => {
      const result = JSON.parse(line);
      if (!result.ready) throw new Error(result.error || 'transcription worker failed to start');
      if (result.speakerLabels === false) {
        emitNotes([{text: '[Model pembicara lokal belum siap. Nama hanya tersedia dari caption yang cocok.]'}]);
      }
    });
    ready.catch(error => {
      if (stopping) return;
      failure ||= error;
      notesFailed = true;
      emit('notes-error');
    });
    ready.then(() => { if (!stopping) emit('notes-ready'); }).catch(() => {});
    worker.stdin.on('error', rejectWaiters);
    // Capture continues while Whisper processes earlier segments.
    function enqueue(chunk) {
      if (!chunk || stopping) return;
      const {audio, startedAtMs, captions} = chunk;
      const path = join(dir, `${String(sequence++).padStart(8, '0')}.webm`);
      const saved = writeFile(path, Buffer.from(audio, 'base64'), {mode: 0o600}).then(() => null, error => error);
      pending = pending.then(async () => {
        const saveError = await saved;
        if (stopping) {
          await rm(path, {force: true}).catch(() => {});
          return;
        }
        if (saveError) throw saveError;
        await ready;
        if (stopping) {
          await rm(path, {force: true}).catch(() => {});
          return;
        }
        const response = nextLine();
        worker.stdin.write(`${JSON.stringify({audio: path})}\n`);
        const result = JSON.parse(await response);
        if (result.error) throw new Error(result.error);
        if (Number.isSafeInteger(result.nextSpeaker)) nextNotesSpeaker = Math.max(nextNotesSpeaker, result.nextSpeaker);
        if (result.speakerLabels === false) {
          emitNotes([{text: '[Pemisahan suara terhenti. Transkripsi dan pencocokan caption tetap berjalan.]'}]);
        }
        if (result.entries.length && !stopping) emitNotes(attributeNotes(result.entries, startedAtMs, captions));
        await rm(path, {force: true});
      }).catch(error => {
        if (stopping) return;
        failure ||= error;
        notesFailed = true;
        emit('notes-error');
      });
    }
    try {
      await wc.executeJavaScript('window.__nailMedia.notesStart()', true);
      while (!stopping && meetingJoined && listeningMode === 'notulen' && !notesFailed) {
        await delay(1000);
        if (stopping || !meetingJoined || listeningMode !== 'notulen' || notesFailed) break;
        enqueue(await wc.executeJavaScript('window.__nailMedia.notesTake()', true));
        const count = await wc.executeJavaScript('window.__nailMedia.micDiag().remoteCount', true);
        if (count > 0) {
          hadTracks = true;
          if (trackGap) {
            trackGap = false;
            emit('notes-ready');
          }
        } else if (hadTracks && !trackGap) {
          trackGap = true;
          emitNotes([{text: '[Audio rapat terputus; percakapan selama jeda mungkin tidak tercatat.]'}]);
          emit('notes-gap');
        }
      }
    } catch (error) {
      if (!stopping) failure ||= error;
    } finally {
      if (stopping) {
        try { await Promise.race([wc.executeJavaScript('window.__nailMedia.notesStop()', true), delay(500)]); } catch {}
        stopNotesWorker();
        await Promise.race([pending.catch(() => {}), delay(500)]);
      } else {
        try {
          enqueue(await wc.executeJavaScript('window.__nailMedia.notesStop()', true));
          let chunk;
          while ((chunk = await wc.executeJavaScript('window.__nailMedia.notesTake()', true))) enqueue(chunk);
        } catch (error) {
          failure ||= error;
        }
        await pending;
        worker.stdin.end();
      }
      if (notesWorker === worker) notesWorker = null;
      await rm(dir, {recursive: true, force: true}).catch(() => {});
    }
    if (failure && !stopping) throw failure;
  }

  let activeWin = null;
  let activeWc = null;
  let activeTurnAbort = null;

  async function presentationAnswer(wc, question, signal) {
    let image;
    try { image = await captureMeetPresentation(wc, signal); }
    catch (error) {
      if (signal.aborted || error?.name === 'AbortError') throw error;
      return 'Saya belum bisa membaca presentasi yang sedang dibagikan. Coba lagi sebentar.';
    }
    if (signal.aborted) throw new DOMException('Interrupted', 'AbortError');
    if (!image) return 'Saya belum bisa membaca presentasi yang sedang dibagikan. Coba lagi sebentar.';
    if (presentationRequestKind(question) === 'text') {
      let text;
      try { text = await presentationOCR.recognize(image, signal); }
      catch (error) {
        if (signal.aborted || error?.name === 'AbortError') throw error;
        return 'Saya belum bisa membaca teks presentasi. Coba lagi sebentar.';
      }
      return text ? `Di layar tertulis: ${text}` : 'Saya belum menemukan teks yang bisa dibaca di presentasi.';
    }
    const work = await mkdtemp(join(tmpdir(), 'nail-presentation-'));
    const path = join(work, 'presentation.png');
    const vision = new CodexLiveSession({visionOnly: true});
    const onAbort = () => { vision.dispose().catch(() => {}); };
    signal.addEventListener('abort', onAbort, {once: true});
    try {
      await writeFile(path, image, {mode: 0o600});
      if (signal.aborted) throw new DOMException('Interrupted', 'AbortError');
      return await vision.analyzeImage(path, question, signal);
    } catch (error) {
      if (signal.aborted || error?.name === 'AbortError') throw error;
      let text = '';
      try { text = await presentationOCR.recognize(image, signal); }
      catch (ocrError) {
        if (signal.aborted || ocrError?.name === 'AbortError') throw ocrError;
      }
      return text ? `Saya belum bisa menganalisis gambarnya. Teks yang terbaca: ${text}` :
        'Saya belum bisa menganalisis gambar dan tidak menemukan teks yang bisa dibaca.';
    } finally {
      signal.removeEventListener('abort', onAbort);
      await vision.dispose().catch(() => {});
      await rm(work, {recursive: true, force: true}).catch(() => {});
    }
  }

  const commands = createInterface({input: process.stdin, terminal: false});
  commands.on('line', line => {
    if (line.startsWith('avatar-set ')) {
      if (!avatarSocketPath || !meetingJoined || stopping) return;
      try {
        const request = JSON.parse(line.slice('avatar-set '.length));
        if (avatarController) void avatarController.request(request);
        else if (Number.isInteger(request.revision)) emit(`avatar-state ${JSON.stringify({revision: request.revision, state: 'unavailable'})}`);
      } catch {}
    } else if (line.startsWith('avatar-fail ')) {
      void avatarController?.fail(Number(line.slice('avatar-fail '.length)));
    } else if (line.startsWith('presentation-ocr-result ')) {
      try { presentationOCR.receive(JSON.parse(line.slice('presentation-ocr-result '.length))); } catch {}
    } else if (line === 'voice-turn') {
      turnRequested = true;
      turnInterrupted = false;
      if (provider === 'codex') {
        activeCodexWakeAbort?.abort();
        activeWc?.executeJavaScript('window.__nailAbortRecord?.()').catch(() => {});
      } else {
        activeWc?.executeJavaScript('window.__nailUpgradeRecord?.()').catch(() => {});
      }
    } else if (line === 'interrupt') {
      turnInterrupted = true;
      followUpUntil = 0;
      activeCodexWakeAbort?.abort();
      activeTurnAbort?.abort(new Error('voice-interrupted'));
      activePresentationAbort?.abort();
      codexSession?.interrupt(activeWc);
      activeWc?.executeJavaScript('window.__nailMedia?.stopPlay?.(); window.__nailAbortRecord?.()').catch(() => {});
      emit('voice-interrupted');
    } else if (line === 'presentation-reading on' || line === 'presentation-reading off') {
      presentationReadingEnabled = line.endsWith(' on');
      if (!presentationReadingEnabled) activePresentationAbort?.abort();
    } else if (line === 'mode standby' || line === 'mode notulen') {
      listeningMode = line === 'mode notulen' ? 'notulen' : 'standby';
      if (listeningMode === 'notulen') notesFailed = false;
      syncCodexNotes();
      emit(`mode-changed ${listeningMode}`);
    } else if (line === 'toggle-window') {
      if (activeWin && !activeWin.isDestroyed()) {
        if (activeWin.isVisible()) {
          activeWin.hide();
          emit('browser-window hidden');
        } else {
          activeWin.show();
          activeWin.focus();
          emit('browser-window shown');
        }
      }
    }
  });
  commands.on('close', () => {
    stopping = true;
    closeAvatar();
    activePresentationAbort?.abort();
    followUpUntil = 0;
    activeCodexWakeAbort?.abort();
    cancelVoice.abort(new Error('voice-interrupted'));
    activeTurnAbort?.abort(new Error('voice-interrupted'));
    codexSession?.dispose().catch(() => {});
    activeWc?.executeJavaScript('window.__nailMedia?.stopPlay?.(); window.__nailAbortRecord?.()').catch(() => {});
    stopCodexWakeDaemon();
    stopNotesWorker();
    if (agyDaemon) {
      killWorkerProcess(agyDaemon);
      agyDaemon = null;
    }
    if (login) {
      finalizeAndExit('left', 0);
      return;
    }
    if (!shutdownFailsafe && !finalized) {
      shutdownFailsafe = setTimeout(() => {
        finalizeAndExit('left', 0);
      }, 3500);
    }
  });

  function isFrameAlive(frame) {
    if (!frame || frame.detached) return false;
    try {
      if (typeof frame.isDestroyed === 'function' && frame.isDestroyed()) return false;
    } catch {
      return false;
    }
    return true;
  }

  function resolveTargetFrame(wc, item) {
    if (!wc || wc.isDestroyed?.()) return null;
    if (item && item.frameRoutingId != null && item.frameProcessId != null) {
      const frames = wc.mainFrame?.framesInSubtree;
      if (Array.isArray(frames)) {
        const match = frames.find(f => isFrameAlive(f) && f.routingId === item.frameRoutingId && f.processId === item.frameProcessId);
        if (match) return match;
      }
    }
    return wc;
  }

  async function readTeamsAcrossFrames(wc) {
    const main = wc?.mainFrame;
    const candidateFrames = Array.isArray(main?.framesInSubtree) && main.framesInSubtree.length
      ? main.framesInSubtree
      : (main ? [main] : []);
    const liveFrames = candidateFrames.filter(f => {
      if (!isFrameAlive(f)) return false;
      const u = String(f.url || '');
      return !u || u === 'about:blank' || u.startsWith('https://');
    });
    if (!liveFrames.length) {
      return await wc.executeJavaScript(`(${inspectTeams})()`);
    }
    const tagKeys = ['continueWeb', 'dismiss', 'computerAudio', 'cameraOn', 'prejoinMicOn', 'enter', 'leave', 'unmute', 'mute'];
    const merged = {
      continueWeb: null,
      dismiss: null,
      computerAudio: null,
      cameraOn: null,
      prejoinMicOn: null,
      nameInput: {present: false, value: ''},
      enter: null,
      leave: null,
      unmute: null,
      mute: null,
      waiting: false,
      rejected: false,
      signInOnly: false,
      hasBodyText: '',
      frameCount: liveFrames.length,
    };
    let anySignInOnly = false;
    let evalSucceeded = 0;
    for (const frame of liveFrames) {
      let res = null;
      try {
        res = await frame.executeJavaScript(`(${inspectTeams})()`);
        evalSucceeded++;
      } catch {
        continue;
      }
      if (!res || typeof res !== 'object') continue;
      const tag = obj => obj ? {...obj, frameRoutingId: frame.routingId, frameProcessId: frame.processId} : null;
      for (const k of tagKeys) {
        if (!merged[k] && res[k]) merged[k] = tag(res[k]);
      }
      if (!merged.nameInput.present && res.nameInput?.present) {
        merged.nameInput = {
          ...res.nameInput,
          frameRoutingId: frame.routingId,
          frameProcessId: frame.processId,
        };
      }
      if (res.waiting) merged.waiting = true;
      if (res.rejected) merged.rejected = true;
      if (res.signInOnly) anySignInOnly = true;
      if (!merged.hasBodyText && res.hasBodyText) merged.hasBodyText = res.hasBodyText;
    }
    if (evalSucceeded === 0) throw new Error('All frames failed inspectTeams');
    merged.signInOnly = anySignInOnly && !merged.continueWeb && !merged.nameInput.present && !merged.enter && !merged.leave;
    return merged;
  }

  async function fillTeamsNameInTarget(wc, nameInput, name) {
    const execHost = resolveTargetFrame(wc, nameInput);
    if (!execHost) return false;
    return await execHost.executeJavaScript(`(${fillTeamsName})(${JSON.stringify(name)})`, true);
  }

  // Inspect the real Meet controls; never fabricate an admission or enable a disabled button.

  async function saveDiagnosticSnapshot(wc, label) {
    if (!wc || wc.isDestroyed?.()) return;
    try { mkdirSync(logDir, {recursive: true}); } catch {}
    try {
      const img = await Promise.race([
        wc.capturePage(),
        delay(2000).then(() => null),
      ]);
      if (img) await writeFile(join(logDir, 'meet-view.png'), img.toPNG());
    } catch {}
    try {
      const currentUrl = wc.getURL();
      const rawFrames = Array.isArray(wc.mainFrame?.framesInSubtree) ? wc.mainFrame.framesInSubtree.filter(isFrameAlive) : [];
      const frameUrls = rawFrames.map(f => String(f.url || ''));
      const controls = [];
      const texts = [];
      const evalTargets = rawFrames.length
        ? rawFrames.filter(f => { const u = String(f.url || ''); return !u || u === 'about:blank' || u.startsWith('https://'); })
        : [wc];
      for (const frame of (evalTargets.length ? evalTargets : [wc])) {
        try {
          const snap = await Promise.race([
            frame.executeJavaScript(`(() => {
              const norm = s => String(s || '').replace(/\\s+/g, ' ').trim();
              const roots = [document];
              const seen = new Set(roots);
              const q = [document];
              while (q.length) {
                const r = q.shift();
                try {
                  for (const el of (r.querySelectorAll?.('*') || [])) {
                    if (el?.shadowRoot && !seen.has(el.shadowRoot)) {
                      seen.add(el.shadowRoot);
                      roots.push(el.shadowRoot);
                      q.push(el.shadowRoot);
                    }
                  }
                } catch {}
              }
              const items = [];
              const itemSeen = new Set();
              for (const r of roots) {
                try {
                  for (const e of (r.querySelectorAll?.('button,[role=button],a,input,[role=switch],[role=radio]') || [])) {
                    if (itemSeen.has(e)) continue;
                    itemSeen.add(e);
                    items.push({
                      tag: e.tagName,
                      tid: e.getAttribute('data-tid'),
                      id: e.id || null,
                      type: e.type || null,
                      aria: e.getAttribute('aria-label'),
                      ph: e.getAttribute('placeholder'),
                      text: norm(e.innerText || e.textContent || '').slice(0, 80),
                    });
                    if (items.length >= 40) break;
                  }
                } catch {}
                if (items.length >= 40) break;
              }
              return {items, text: (document.body?.innerText ?? document.body?.textContent ?? '').slice(0, 2000)};
            })()`, true),
            delay(1500).then(() => null),
          ]);
          if (snap) {
            for (const it of snap.items || []) {
              if (controls.length < 60) controls.push(it);
            }
            if (snap.text) texts.push(`[${frame.url || currentUrl}]\n${snap.text}`);
          }
        } catch {}
      }
      await writeFile(
        join(logDir, 'meet-view.txt'),
        `PHASE: ${label}\nURL: ${currentUrl}\nFRAMES:\n${JSON.stringify(frameUrls, null, 1)}\n\nBUTTONS:\n${JSON.stringify(controls, null, 1)}\n\nCONSOLE:\n${consoleLogs.join('\n')}\n\n${texts.join('\n---\n').slice(0, 5000)}`
      );
      appendTeamsLog(`SNAPSHOT(${label}) url=${currentUrl} controls=${controls.length}`);
    } catch {}
  }

  async function saveNoMicDiag(wc, unmute, restoreMute, reason) {
    try {
      const dir = join(require('node:os').homedir(), 'Library/Logs/Nail');
      mkdirSync(dir, {recursive: true});
      await writeFile(join(dir, 'meet-nomic.png'), (await wc.capturePage()).toPNG());
      const info = await wc.executeJavaScript('(async () => JSON.stringify({mic: __nailMedia.micDiag(), out: await __nailMedia.micOutDiag?.(), buttons: [...document.querySelectorAll("button,[role=button]")].map(b => b.getAttribute("aria-label") || b.innerText).filter(Boolean).slice(0, 40)}, null, 1))()');
      await writeFile(join(dir, 'meet-nomic.txt'), `${JSON.stringify({reason, unmute, restoreMute})}\n\n${info}\n`);
      appendTeamsLog(`${reason} unmute=${JSON.stringify(unmute)} diag=${info.slice(0, 500)}`);
    } catch {}
  }

  async function unmuteAndVerifyMic(wc, read, click, state, signal) {
    const before = await read();
    const {unmute} = before;
    let after = before;
    if (unmute) state.restoreMute = await click(unmute);
    if (platform === 'teams' && unmute) {
      const unmuteStartedAt = Date.now();
      let retriedInputClick = false;
      const uiDeadline = unmuteStartedAt + 1500;
      while (!stopping && !turnInterrupted && !signal?.aborted) {
        after = await read();
        if (!after?.unmute) break;
        const now = Date.now();
        if (now >= uiDeadline) break;
        if (!retriedInputClick && now - unmuteStartedAt >= 600 &&
            (after.unmute.frameRoutingId == null || after.unmute.frameRoutingId === wc.mainFrame?.routingId)) {
          retriedInputClick = true;
          const pt = {x: Math.round(after.unmute.x), y: Math.round(after.unmute.y)};
          try {
            wc.sendInputEvent({type: 'mouseMove', ...pt});
            wc.sendInputEvent({type: 'mouseDown', ...pt, button: 'left', clickCount: 1});
            wc.sendInputEvent({type: 'mouseUp', ...pt, button: 'left', clickCount: 1});
            state.restoreMute = true;
          } catch {}
        }
        await delay(120);
      }
      if (stopping || turnInterrupted || signal?.aborted) return false;
      if (after?.unmute) {
        await saveNoMicDiag(wc, {before: before.unmute, after: after.unmute}, state.restoreMute, 'UNMUTE_UI_STUCK');
        return false;
      }
    }
    const deadline = Date.now() + (platform === 'teams' ? 4500 : 2500);
    while (!stopping && !turnInterrupted && !signal?.aborted &&
        Date.now() < deadline && !await wc.executeJavaScript('__nailMedia.sending()')) {
      await delay(100);
    }
    if (stopping || turnInterrupted || signal?.aborted) return false;
    if (await wc.executeJavaScript('__nailMedia.sending()')) {
      if (platform === 'teams') {
        if (state.restoreMute) {
          await delay(250);
          if (stopping || turnInterrupted || signal?.aborted) return false;
        }
        const outDiag = await wc.executeJavaScript('window.__nailMedia?.micOutDiag?.()', true).catch(() => null);
        appendTeamsLog(
          `UNMUTE_OK before=${JSON.stringify({u: before.unmute?.name ?? null, m: before.mute?.name ?? null})} after=${JSON.stringify({u: after?.unmute?.name ?? null, m: after?.mute?.name ?? null})} restore=${state.restoreMute} diag=${JSON.stringify(outDiag)}`
        );
      }
      return true;
    }
    await saveNoMicDiag(wc, unmute, state.restoreMute, 'NO_MIC');
    return false;
  }

  async function restoreMeetMute(wc, read, click, shouldRestore) {
    if (!shouldRestore || wc.isDestroyed()) return;
    try {
      const {mute} = await read();
      const clicked = mute ? await click(mute) : false;
      if (platform === 'teams') {
        appendTeamsLog(`RESTORE_MUTE mute=${JSON.stringify(mute?.name ?? null)} clicked=${clicked}`);
      }
    } catch {}
  }

  async function logVoiceError(error) {
    try {
      const dir = join(require('node:os').homedir(), 'Library/Logs/Nail');
      mkdirSync(dir, {recursive: true});
      await appendFile(join(dir, 'voice-error.log'), `${new Date().toISOString()} ${error?.stack || error?.message || error}\n${error?.stderr ?? ''}\n`);
    } catch {}
  }

  async function runCodexTurn(wc, read, click, executeTurn) {
    const micState = {restoreMute: false};
    turnInterrupted = false;
    const turnAbort = new AbortController();
    const onStop = () => turnAbort.abort(cancelVoice.signal.reason ?? new Error('voice-interrupted'));
    if (cancelVoice.signal.aborted) onStop();
    else cancelVoice.signal.addEventListener('abort', onStop, {once: true});
    activeTurnAbort = turnAbort;
    try {
      const result = await executeTurn({
        unmuteMeet: () => unmuteAndVerifyMic(wc, read, click, micState, turnAbort.signal),
        signal: turnAbort.signal,
        progress: emit,
      });
      if (stopping || turnInterrupted || result?.aborted) return;
      if (result?.noAudio) {
        const diag = await wc.executeJavaScript('window.__nailDiagnostics ?? null', true).catch(() => null);
        emit(`voice-no-audio ${JSON.stringify(diag ?? {})}`);
        return;
      }
      if (platform === 'teams') {
        const outDiag = await wc.executeJavaScript('window.__nailMedia?.micOutDiag?.()', true).catch(() => null);
        appendTeamsLog(
          `TURN_END provider=${provider} latencyMs=${result.latencyMs} replyLen=${(result.reply || '').length} codex=${JSON.stringify(result.diag ?? null)} out=${JSON.stringify(outDiag)}`
        );
      }
      meetingNotes.addExchange({
        heard: result.heard,
        reply: result.reply,
        heardAtMs: result.heardAtMs,
        replyAtMs: result.replyAtMs,
      });
      emit(`voice-result ${JSON.stringify({
        heard: result.heard,
        reply: result.reply,
        heardAtMs: result.heardAtMs,
        replyAtMs: result.replyAtMs,
        latencyMs: result.latencyMs,
      })}`);
      emit('voice-standby');
      await delay(450);
    } catch (error) {
      if (error?.message === 'voice-interrupted' || error?.name === 'AbortError' || stopping || turnInterrupted) return;
      await logVoiceError(error);
      emit(error.message === 'voice-no-mic' || /^voice-codex-(quota|login|missing|timeout|error|connection|no-transcript)$/.test(error.message)
        ? error.message : 'voice-failed');
    } finally {
      cancelVoice.signal.removeEventListener('abort', onStop);
      if (activeTurnAbort === turnAbort) activeTurnAbort = null;
      await restoreMeetMute(wc, read, click, micState.restoreMute);
    }
  }

  async function runCodexLiveTurn(wc, read, click) {
    return runCodexTurn(wc, read, click, opts => codexSession.runLiveTurn(wc, opts));
  }

  async function runCodexTextTurn(wc, read, click, text) {
    return runCodexTurn(wc, read, click, opts => codexSession.runTextTurn(wc, {text, ...opts}));
  }

  async function runCodexPresentationTurn(wc, read, click, question) {
    return runCodexTurn(wc, read, click, async opts => {
      const controller = new AbortController();
      const onAbort = () => controller.abort();
      activePresentationAbort = controller;
      opts.signal.addEventListener('abort', onAbort, {once: true});
      try {
        if (opts.signal.aborted || !presentationReadingEnabled) controller.abort();
        emit('voice-processing');
        const answer = await presentationAnswer(wc, question, controller.signal);
        if (controller.signal.aborted) throw new DOMException('Interrupted', 'AbortError');
        return await codexSession.runTextTurn(wc, {
          ...opts,
          signal: controller.signal,
          displayText: question,
          text: `Bacakan jawaban berikut persis seperti tertulis, tanpa menambah penjelasan: ${answer}`,
        });
      } finally {
        opts.signal.removeEventListener('abort', onAbort);
        if (activePresentationAbort === controller) activePresentationAbort = null;
      }
    });
  }

  async function runCodexHandsFreeTurn(wc, read, click) {
    if (!turnRequested && !stopping) emit('voice-standby');
    const clip = await wc.executeJavaScript('__nailMedia.record(8000, true, 12000)', true);
    if (!clip || stopping || turnInterrupted || turnRequested) return;
    if (typeof clip !== 'string' || clip.length > 512_000) return;

    const work = await mkdtemp(join(tmpdir(), 'nail-wake-'));
    const input = join(work, 'wake.webm');
    const wakeAbort = new AbortController();
    activeCodexWakeAbort = wakeAbort;
    let wake = null;
    try {
      await writeFile(input, Buffer.from(clip, 'base64'), {mode: 0o600});
      if (stopping || turnInterrupted || turnRequested || wakeAbort.signal.aborted) {
        await rm(work, {recursive: true, force: true}).catch(() => {});
        return;
      }
      const wakePromise = checkCodexWake(input);
      wakePromise
        .catch(error => { if (wakeAbort.signal.aborted) return logVoiceError(error); })
        .finally(() => { rm(work, {recursive: true, force: true}).catch(() => {}); });
      wake = await new Promise((resolve, reject) => {
        if (wakeAbort.signal.aborted || stopping || turnInterrupted || turnRequested) {
          resolve(null);
          return;
        }
        const onAbort = () => resolve(null);
        wakeAbort.signal.addEventListener('abort', onAbort, {once: true});
        wakePromise.then(
          res => { wakeAbort.signal.removeEventListener('abort', onAbort); resolve(res); },
          err => { wakeAbort.signal.removeEventListener('abort', onAbort); reject(err); },
        );
      });
    } catch (error) {
      await logVoiceError(error);
      await rm(work, {recursive: true, force: true}).catch(() => {});
      return;
    } finally {
      if (activeCodexWakeAbort === wakeAbort) activeCodexWakeAbort = null;
    }

    if (!wake?.triggered || stopping || turnInterrupted || turnRequested) return;
    emit(`voice-wake ${JSON.stringify({heard: wake.prompt || wake.raw || 'Nail'})}`);
    if (wake.has_query && wake.prompt) {
      if (shouldReadPresentation(platform, presentationReadingEnabled, wake.prompt)) {
        await runCodexPresentationTurn(wc, read, click, wake.prompt);
      } else {
        await runCodexTextTurn(wc, read, click, wake.prompt);
      }
    } else {
      await runCodexLiveTurn(wc, read, click);
    }
  }

  async function runCodexManualPresentationTurn(wc, read, click) {
    emit('voice-recording');
    const clip = await wc.executeJavaScript('__nailMedia.record(8000, false, 12000)', true);
    if (!clip || stopping || turnInterrupted) return;
    if (typeof clip !== 'string' || clip.length > 512_000) throw new Error('Invalid audio');
    const work = await mkdtemp(join(tmpdir(), 'nail-manual-'));
    const input = join(work, 'question.webm');
    try {
      await writeFile(input, Buffer.from(clip, 'base64'), {mode: 0o600});
      emit('voice-processing');
      const transcript = await checkCodexWake(input, 'transcript');
      if (stopping || turnInterrupted) return;
      const question = (transcript.entries || []).map(entry => entry.text).filter(Boolean).join(' ').trim();
      if (!question) { emit('voice-no-audio'); return; }
      if (shouldReadPresentation(platform, presentationReadingEnabled, question)) {
        await runCodexPresentationTurn(wc, read, click, question);
      } else {
        await runCodexTextTurn(wc, read, click, question);
      }
    } finally {
      await rm(work, {recursive: true, force: true});
    }
  }

  async function voiceTurn(wc, read, click, auto = false, isFollowUp = false) {
    if (provider === 'codex' && codexSession) {
      if (!auto) {
        if (platform === 'meet' && presentationReadingEnabled) return await runCodexManualPresentationTurn(wc, read, click);
        return await runCodexLiveTurn(wc, read, click);
      }
      if (codexHandsFree && !codexWakeFailed) return await runCodexHandsFreeTurn(wc, read, click);
      return;
    }
    const work = await mkdtemp(join(tmpdir(), 'nail-meet-'));
    const input = join(work, 'meeting.webm');
    const output = join(work, 'reply.wav');
    const micState = {restoreMute: false};
    turnInterrupted = false;
    try {
      emit(isFollowUp ? 'voice-followup' : auto ? 'voice-standby' : 'voice-recording');
      const idleMs = isFollowUp ? 3000 : 12000;
      const clip = await wc.executeJavaScript(`__nailMedia.record(8000, ${Boolean(auto)}, ${idleMs})`, true);
      if (stopping || turnInterrupted) return;
      const manual = !auto || turnRequested;
      if (turnRequested) turnRequested = false;
      const diag = await wc.executeJavaScript('window.__nailDiagnostics ?? null', true);
      if (!clip) {
        if (isFollowUp) followUpUntil = 0;
        if (!manual) return;
        try {
          const dir = join(require('node:os').homedir(), 'Library/Logs/Nail');
          mkdirSync(dir, {recursive: true});
          await writeFile(join(dir, 'meet-view.png'), (await wc.capturePage()).toPNG());
          const text = await wc.executeJavaScript('document.body?.innerText?.slice(0, 4000) ?? ""');
          const inbound = await wc.executeJavaScript('JSON.stringify(window.__nailInbound ?? null, null, 1)');
          await writeFile(join(dir, 'meet-view.txt'), `${JSON.stringify(diag)}\n\n${inbound}\n\nCONSOLE:\n${consoleLogs.join('\n')}\n\n${text}`);
        } catch {}
        emit(`voice-no-audio ${JSON.stringify(diag ?? {})}`);
        return;
      }
      if (typeof clip !== 'string' || clip.length > 512_000) throw new Error('Invalid audio');
      const heardAtMs = Date.now();
      if (manual || isFollowUp) emit('voice-processing');
      let result, audio;
      const requireWake = !manual && !isFollowUp;
      const wantNotulen = listeningMode === 'notulen';
      if (provider === 'antigravity') {
        await writeFile(input, Buffer.from(clip, 'base64'), {mode: 0o600});
        startAgyDaemon();
        await agyReady;
        const notesPayload = agySyncedNoteCursor === 0
          ? {text: meetingNotes.buildSnapshot(8000), nextCursor: meetingNotes.latestCursor()}
          : meetingNotes.drainDelta(agySyncedNoteCursor, 4000, {excludeKinds: ['command', 'reply']});
        agyDaemon.stdin.write(`${JSON.stringify({
          from_wav: input,
          reply_wav: output,
          require_wake: requireWake,
          notulen: wantNotulen,
          notes_context: notesPayload.text,
          defer_reply: platform === 'meet' && presentationReadingEnabled,
        })}\n`);
        let msg = JSON.parse(await agyLines());
        if (msg.event === 'wake') {
          if (!turnInterrupted && !stopping) emit(`voice-wake ${JSON.stringify({heard: msg.heard ?? ''})}`);
          msg = JSON.parse(await agyLines());
        }
        if (msg.event === 'transcribed') {
          const question = String(msg.heard || '');
          let decision = {action: stopping || turnInterrupted ? 'cancel' : 'continue'};
          if (!stopping && !turnInterrupted && shouldReadPresentation(platform, presentationReadingEnabled, question)) {
            const controller = new AbortController();
            activePresentationAbort = controller;
            const onStop = () => controller.abort();
            cancelVoice.signal.addEventListener('abort', onStop, {once: true});
            try {
              const answer = await presentationAnswer(wc, question, controller.signal);
              decision = {action: 'answer', text: answer};
            } catch {
              decision = {action: 'cancel'};
            } finally {
              cancelVoice.signal.removeEventListener('abort', onStop);
              if (activePresentationAbort === controller) activePresentationAbort = null;
            }
          }
          const response = agyLines();
          agyDaemon.stdin.write(`${JSON.stringify(decision)}\n`);
          msg = JSON.parse(await response);
        }
        result = msg;
        if (result.error) throw new Error(result.error);
        if (result.skipped) {
          if (result.notulen_line && listeningMode === 'notulen') {
            meetingNotes.addEntry({text: result.notulen_line, timestampMs: heardAtMs, kind: 'meeting'});
            emit(`voice-notulen ${JSON.stringify({text: result.notulen_line})}`);
          }
          return;
        }
        if (result.heard) agySyncedNoteCursor = notesPayload.nextCursor;
        if (!result.reply) { if (manual) emit(`voice-no-audio ${JSON.stringify(diag ?? {})}`); return; }
        if ((await stat(output)).size > 2_000_000) throw new Error('Reply audio too large');
        audio = (await readFile(output)).toString('base64');
      } else {
        await writeFile(input, Buffer.from(clip, 'base64'), {mode: 0o600});
        const extraArgs = requireWake ? ['--require', 'Nail'] : [];
        const notesSnapshot = meetingNotes.buildSnapshot(8000);
        if (notesSnapshot) {
          const contextFile = join(work, 'notes-context.txt');
          await writeFile(contextFile, notesSnapshot, {mode: 0o600});
          extraArgs.push('--context-file', contextFile);
        }
        const options = {signal: cancelVoice.signal, timeout: 65_000,
          env: {...process.env, PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.HOME}/.local/bin:${process.env.PATH ?? '/usr/bin:/bin'}`}};
        let presentationQuestion = '';
        if (platform === 'meet' && presentationReadingEnabled) {
          const transcription = await promisify(execFile)('/usr/bin/python3',
            [pipeline, '--from-wav', input, '--no-speak', '--no-notulen', '--transcribe-only', ...extraArgs], options);
          if (stopping || turnInterrupted) return;
          const heard = JSON.parse(transcription.stdout.trim().split(/\r?\n/).pop() ?? '{}');
          if (heard.skipped || !heard.heard) {
            if (heard.heard && listeningMode === 'notulen') {
              meetingNotes.addEntry({text: heard.heard, timestampMs: heardAtMs, kind: 'meeting'});
              emit(`voice-notulen ${JSON.stringify({text: heard.heard})}`);
            }
            return;
          }
          if (shouldReadPresentation(platform, presentationReadingEnabled, heard.heard)) {
            presentationQuestion = heard.heard;
          } else {
            const transcriptFile = join(work, 'transcript.txt');
            await writeFile(transcriptFile, heard.heard, {mode: 0o600});
            extraArgs.push('--transcript-file', transcriptFile);
          }
        }
        if (presentationQuestion) {
          const controller = new AbortController();
          activePresentationAbort = controller;
          const onStop = () => controller.abort();
          cancelVoice.signal.addEventListener('abort', onStop, {once: true});
          try {
            const reply = await presentationAnswer(wc, presentationQuestion, controller.signal);
            const textFile = join(work, 'speech.txt');
            await writeFile(textFile, reply, {mode: 0o600});
            await promisify(execFile)('/usr/bin/python3',
              [pipeline, '--speak-text-file', textFile, '--reply-wav', output], {...options, signal: controller.signal});
            result = {heard: presentationQuestion, reply};
          } finally {
            cancelVoice.signal.removeEventListener('abort', onStop);
            if (activePresentationAbort === controller) activePresentationAbort = null;
          }
        } else {
          const {stdout} = await promisify(execFile)('/usr/bin/python3',
            [pipeline, '--from-wav', input, '--reply-wav', output, '--no-notulen', ...extraArgs], options);
          result = JSON.parse(stdout.trim().split(/\r?\n/).pop() ?? '');
        }
        if (result.skipped) {
          if (result.heard && listeningMode === 'notulen') {
            meetingNotes.addEntry({text: result.heard, timestampMs: heardAtMs, kind: 'meeting'});
            emit(`voice-notulen ${JSON.stringify({text: result.heard})}`);
          }
          return;
        }
        if (!result.reply) { if (manual) emit(`voice-no-audio ${JSON.stringify(diag ?? {})}`); return; }
        if ((await stat(output)).size > 2_000_000) throw new Error('Reply audio too large');
        audio = (await readFile(output)).toString('base64');
      }
      if (stopping || turnInterrupted) return;
      emit('voice-sending');
      if (!await unmuteAndVerifyMic(wc, read, click, micState, cancelVoice.signal)) {
        if (!stopping && !turnInterrupted) emit('voice-no-mic');
        return;
      }
      if (!audio || audio.length > 2_700_000) throw new Error('Invalid reply audio');
      if (stopping || turnInterrupted) return;
      const replyAtMs = Date.now();
      await wc.executeJavaScript(`__nailMedia.play(${JSON.stringify(audio)})`, true);
      if (!stopping && !turnInterrupted) {
        const latencyMs = Math.max(0, replyAtMs - heardAtMs);
        if (platform === 'teams') {
          const outDiag = await wc.executeJavaScript('window.__nailMedia?.micOutDiag?.()', true).catch(() => null);
          appendTeamsLog(
            `TURN_END provider=${provider} latencyMs=${latencyMs} replyLen=${(result.reply || '').length} out=${JSON.stringify(outDiag)}`
          );
        }
        meetingNotes.addExchange({
          heard: result.notulen_line || result.heard,
          reply: result.reply,
          heardAtMs,
          replyAtMs,
        });
        emit(`voice-result ${JSON.stringify({
          heard: result.heard,
          reply: result.reply,
          heardAtMs,
          replyAtMs,
          latencyMs,
        })}`);
        followUpUntil = Date.now() + 3000;
        emit('voice-followup');
        await delay(350);
      }
    } catch (error) {
      await logVoiceError(error);
      if (!stopping && !turnInterrupted) emit('voice-failed');
    } finally {
      await restoreMeetMute(wc, read, click, micState.restoreMute);
      await rm(work, {recursive: true, force: true});
    }
  }

  async function run() {
    app.dock.hide();
    const partition = platform === 'teams' ? 'persist:nail-teams-guest' : 'persist:nail-signin';
    const title = login ? 'Login Google untuk Nail' : platform === 'teams' ? 'Microsoft Teams — Nail' : 'Google Meet — Nail';
    const win = new BrowserWindow({show: false, title, width: 1280, height: 860,
      webPreferences: {partition, sandbox: true, contextIsolation: true,
        nodeIntegration: false, backgroundThrottling: false, devTools: false,
        ...(avatarSocketPath ? {additionalArguments: ['--nail-meet-avatar']} : {}),
        ...(provider ? {preload: join(__dirname, 'meet-media.cjs')} : {})}});
    activeWin = win;
    const wc = win.webContents;
    activeWc = wc;
    if (platform === 'teams') {
      await wc.session.clearStorageData().catch(() => {});
      const major = wc.getUserAgent().match(/Chrome\/(\d+)/)?.[1] || '156';
      const cleanUA = `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${major}.0.0.0 Safari/537.36`;
      wc.session.setUserAgent(cleanUA);
      wc.setUserAgent(cleanUA);
      wc.session.webRequest.onBeforeSendHeaders((details, callback) => {
        const headers = {...details.requestHeaders};
        for (const k of Object.keys(headers)) {
          if (/^(user-agent|sec-ch-ua|sec-ch-ua-mobile|sec-ch-ua-platform)$/i.test(k)) {
            delete headers[k];
          }
        }
        headers['User-Agent'] = cleanUA;
        headers['Sec-CH-UA'] = `"Not-A.Brand";v="99", "Google Chrome";v="${major}", "Chromium";v="${major}"`;
        headers['Sec-CH-UA-Mobile'] = '?0';
        headers['Sec-CH-UA-Platform'] = '"macOS"';
        callback({requestHeaders: headers});
      });
    }
    const teamsStoragePerms = new Set(['storage-access', 'top-level-storage-access', 'persistent-storage']);
    wc.session.setPermissionCheckHandler((_wc, permission) =>
      platform === 'teams' ? teamsStoragePerms.has(permission) : false);
    wc.session.setPermissionRequestHandler((_contents, permission, callback) =>
      callback(platform === 'teams' ? teamsStoragePerms.has(permission) : false));
    wc.session.setDisplayMediaRequestHandler((_request, callback) => callback({}));
    wc.setWindowOpenHandler(() => ({action: 'deny'}));
    wc.setAudioMuted(true);
    consoleLogs.length = 0;
    let teamsConsoleCount = 0;
    wc.on('console-message', (ev, levelArg, msgArg) => {
      const level = typeof ev?.level === 'number' ? ev.level : levelArg;
      const message = typeof ev?.message === 'string' ? ev.message : msgArg;
      const text = String(message).slice(0, 300);
      if (level >= 2 && consoleLogs.length < 60) consoleLogs.push(`[${level}] ${text}`);
      if (platform === 'teams' && level >= 1 && teamsConsoleCount < 80 &&
          /ExpLoader|Auth|callingAgents|MediaStream|error|fail|404/i.test(text)) {
        teamsConsoleCount++;
        appendTeamsLog(`CONSOLE[${level}] ${text}`);
      }
    });

    const loginOrigins = new Set(['https://accounts.google.com', 'https://myaccount.google.com', 'https://www.google.com']);
    const msLoginOrigins = new Set(['https://login.microsoftonline.com', 'https://login.live.com']);
    let teamsLoginRedirect = false;

    const validNavigation = value => {
      if (!URL.canParse(value)) return false;
      const url = new URL(value);
      if (login) return loginOrigins.has(url.origin);
      if (platform === 'teams') return url.protocol === 'https:' && isAllowedTeamsHost(url.hostname);
      return `${url.origin}${url.pathname}` === target;
    };
    const guardNavigation = (event, source, legacyUrl) => {
      const navUrl = event?.url || legacyUrl;
      const isMain = event?.isMainFrame !== false;
      if (platform === 'teams' && URL.canParse(navUrl) && msLoginOrigins.has(new URL(navUrl).origin)) {
        if (isMain) {
          teamsLoginRedirect = true;
          appendTeamsLog(`BLOCKED_MS_LOGIN(${source}): ${navUrl}`);
        } else {
          appendTeamsLog(`BLOCKED_SUBFRAME_LOGIN(${source}): ${navUrl}`);
        }
        event.preventDefault();
        return;
      }
      if (!isMain && platform === 'teams' && (navUrl === 'about:blank' || String(navUrl).startsWith('blob:'))) {
        return;
      }
      if (!validNavigation(navUrl)) {
        appendTeamsLog(`BLOCKED_NAV(${source} main=${isMain}): ${navUrl}`);
        event.preventDefault();
      } else if (platform === 'teams' && source === 'will-redirect') {
        appendTeamsLog(`REDIRECT: ${navUrl}`);
      }
    };
    wc.on('will-navigate', (event, url) => guardNavigation(event, 'will-navigate', url));
    wc.on('will-redirect', event => { if (event.isMainFrame !== false) guardNavigation(event, 'will-redirect'); });
    let lightLaunchFallbackUsed = false;
    if (platform === 'teams') {
      wc.on('did-navigate', (_e, url, code, statusText) => {
        appendTeamsLog(`did-navigate code=${code} ${statusText} url=${url}`);
        if (code === 404 && !lightLaunchFallbackUsed &&
            /\/statics\/evergreen-assets\/tabs\/dl\/launcher\//i.test(String(url))) {
          const fallbackURL = buildTeamsLightLaunchURL(target);
          if (fallbackURL) {
            lightLaunchFallbackUsed = true;
            appendTeamsLog(`FALLBACK_LIGHT_LAUNCH: ${fallbackURL}`);
            wc.loadURL(fallbackURL).catch(() => {});
          }
        }
      });
      wc.on('did-navigate-in-page', (_e, url, isMain) => { if (isMain) appendTeamsLog(`did-navigate-in-page url=${url}`); });
      wc.on('did-finish-load', () => appendTeamsLog(`did-finish-load url=${wc.getURL()}`));
      wc.on('did-fail-load', (_e, code, desc, url, isMain) => appendTeamsLog(`did-fail-load main=${isMain} code=${code} ${desc} url=${url}`));
      wc.on('render-process-gone', (_e, details) => appendTeamsLog(`render-process-gone reason=${details?.reason} exit=${details?.exitCode}`));
    }
    win.on('close', event => {
      if (!login && !stopping) {
        event.preventDefault();
        win.hide();
        emit('browser-window hidden');
      }
    });
    win.on('closed', () => app.quit());

    if (login) {
      process.stdin.once('end', () => app.quit());
      await wc.loadURL('https://accounts.google.com/');
      win.show();
      emit('login-panel');
      return;
    }

    const read = () => platform === 'teams'
      ? readTeamsAcrossFrames(wc)
      : wc.executeJavaScript(`(${inspectMeet})()`);
    startAgyDaemon();
    codexSession?.warmup().catch(() => {});
    const click = async item => {
      if (!item) return false;
      const execHost = resolveTargetFrame(wc, item);
      if (!execHost) return false;
      const {x, y, name, selector} = item;
      return await execHost.executeJavaScript(`(() => {
        const isDisabled = el => !el || Boolean(el.matches?.(':disabled,[aria-disabled="true"]'));
        const isVisible = el => Boolean(el) && (el.getClientRects?.().length ?? 0) > 0;
        const findDeepSelector = sel => {
          const seen = new Set();
          const q = [document];
          while (q.length) {
            const root = q.shift();
            if (!root || seen.has(root)) continue;
            seen.add(root);
            try {
              for (const candidate of (root.querySelectorAll?.(sel) || [])) {
                if (isVisible(candidate) && !isDisabled(candidate)) return candidate;
              }
            } catch {}
            try {
              for (const node of (root.querySelectorAll?.('*') || [])) {
                if (node?.shadowRoot) q.push(node.shadowRoot);
              }
            } catch {}
          }
          return null;
        };
        if (${JSON.stringify(Boolean(selector))}) {
          const direct = findDeepSelector(${JSON.stringify(selector ?? '')});
          if (direct) {
            direct.click();
            return true;
          }
        }
        let hit = document.elementFromPoint(${x}, ${y});
        while (hit?.shadowRoot) {
          const inner = hit.shadowRoot.elementFromPoint?.(${x}, ${y});
          if (!inner || inner === hit) break;
          hit = inner;
        }
        const element = hit?.closest?.('button,[role=button],a,[role=switch],[role=radio],input[type=checkbox],input[type=radio]') || hit;
        if (!element || isDisabled(element)) return false;
        const label = ((element.getAttribute?.('aria-labelledby') || '').split(/\\s+/).filter(Boolean)
          .map(id => document.getElementById(id)?.textContent || '').join(' ').trim() ||
          (element.getAttribute?.('aria-label') || element.getAttribute?.('title') || element.innerText || element.textContent || '')).replace(/\\s+/g, ' ').trim();
        if (${JSON.stringify(platform === 'meet')} && label !== ${JSON.stringify(name)}) return false;
        element.click?.();
        return true;
      })()`, true);
    };

    if (avatarSocketPath) {
      const media = async (method, ...args) => {
        if (!meetingJoined || wc.isDestroyed() || !wc.getURL().startsWith('https://meet.google.com/')) return false;
        return Promise.race([
          wc.executeJavaScript(`location.origin === 'https://meet.google.com' && window.__nailMedia?.${method}(...${JSON.stringify(args)})`),
          delay(1500).then(() => false),
        ]);
      };
      const setCamera = async (enabled, revision) => {
        const until = Date.now() + 3000;
        let clicked = false;
        let dismissedNotice = false;
        let resetRequested = false;
        while (!stopping && meetingJoined && Date.now() < until) {
          if (enabled && !avatarController?.accepts(revision)) return false;
          const state = await Promise.race([read(), delay(500).then(() => null)]);
          if (!state) return false;
          if (state.dismissCameraNotice && !dismissedNotice) {
            dismissedNotice = await Promise.race([click(state.dismissCameraNotice), delay(500).then(() => false)]);
            if (dismissedNotice) clicked = false;
            await delay(100);
            continue;
          }
          if (enabled && state.cameraEnabled && await media('avatarCameraHasTrack', revision)) return true;
          if (!enabled && !state.cameraEnabled) return true;
          const action = meetAvatarCameraAction(state, enabled, clicked, resetRequested);
          if (action) {
            const sent = await Promise.race([click(action), delay(500).then(() => false)]);
            if (enabled && state.cameraEnabled) resetRequested = sent;
            else clicked = sent;
          }
          await delay(100);
        }
        return false;
      };
      avatarController = createMeetAvatarController({
        prepare: revision => media('prepareAvatarCamera', revision),
        stop: revision => media('stopAvatarCamera', revision),
        setCamera,
        emitState(revision, state) {
          avatarRevision = revision;
          avatarOn = state === 'on';
          emit(`avatar-state ${JSON.stringify({revision, state})}`);
        },
      });
      avatarServer = await listenForAvatarFrames(avatarSocketPath, async (revision, jpeg) => {
        if (!avatarController?.accepts(revision)) return false;
        const drawn = await media('drawAvatarFrame', revision, jpeg.toString('base64')).catch(() => false);
        if (drawn && avatarController?.accepts(revision)) void avatarController.frameReady(revision);
        if (!drawn) void avatarController?.fail(revision);
        return drawn;
      }).catch(() => null);
      if (!avatarServer) closeAvatar();
      else {
        let sampling = false;
        avatarTimer = setInterval(async () => {
          if (sampling || !avatarOn || !avatarSpeaking || !avatarUnmuted) return;
          const revision = avatarRevision;
          const turn = avatarTurn;
          sampling = true;
          try {
            const sample = await media('avatarAudioSample').catch(() => false);
            if (avatarOn && avatarSpeaking && avatarUnmuted && revision === avatarRevision && turn === avatarTurn) {
              emitAvatarAudio(Number.isFinite(sample?.rms) ? sample.rms : 0, sample?.sending === true);
            }
          } finally {
            sampling = false;
          }
        }, 50);
      }
    }

    try {
      await wc.loadURL(target);
    } catch (error) {
      if (platform === 'teams') {
        appendTeamsLog(`loadURL error code=${error?.code} msg=${error?.message} url=${wc.getURL()} loginRedirect=${teamsLoginRedirect}`);
        if (teamsLoginRedirect) {
          await saveDiagnosticSnapshot(wc, 'teams-login-redirect-load');
          return 'teams-login-required';
        }
        if (error?.code !== 'ERR_ABORTED' || wc.isDestroyed()) throw error;
      } else if (error?.code !== 'ERR_ABORTED' || !validNavigation(wc.getURL())) {
        throw error;
      }
    }
    if (platform === 'teams' && teamsLoginRedirect) {
      await saveDiagnosticSnapshot(wc, 'teams-login-redirect-post-load');
      return 'teams-login-required';
    }

    if (platform === 'meet') {
      if (provider && !await wc.executeJavaScript('Boolean(window.__nailMedia)')) return 'voice-unavailable';
      let submitted = false;
      let joined = false;
      let voice;
      let skipped = false;
      let dismissed = false;
      let waiting = false;
      let prejoinCameraDisabled = false;
      let deadline = Date.now() + 30_000;
      while (!stopping && (joined || Date.now() < deadline)) {
        if (!validNavigation(wc.getURL())) return 'failed';
        const state = await read();
        if (avatarUnmuted && !state.mute) emitAvatarAudio(0, false);
        avatarUnmuted = Boolean(state.mute);
        if (joined && !state.inCall) return 'left';
        if (state.rejected) return 'rejected';
        if (!submitted && state.skip && !skipped) skipped = await click(state.skip);
        else if (!submitted && state.dismiss && !dismissed) dismissed = await click(state.dismiss);
        else if (!submitted && state.signIn && !state.signedIn) return 'login-required';
        else if (!submitted && avatarSocketPath && !prejoinCameraDisabled && state.disableCamera && await click(state.disableCamera)) {
          prejoinCameraDisabled = true;
        }
        else if (!submitted && state.signedIn && state.enter && !state.skip && await click(state.enter)) {
          submitted = true;
          deadline = Date.now() + 90_000;
          emit('submitted');
        } else if (submitted && state.inCall && !joined) {
          joined = true;
          meetingJoined = true;
          syncCodexNotes();
          emit('joined');
          if (provider === 'codex' && codexSession) {
            codexSession.ensureConnected(wc, emit)
              .then(() => { if (!stopping && !voice) emit('voice-standby'); })
              .catch(() => {});
          }
        } else if (joined && provider && !voice && (turnRequested || provider !== 'codex' || (codexHandsFree && !codexWakeFailed))) {
          const manual = turnRequested;
          turnRequested = false;
          const inFollowUp = !manual && Date.now() < followUpUntil;
          if (!inFollowUp) followUpUntil = 0;
          voice = voiceTurn(wc, read, click, !manual, inFollowUp)
            .catch(() => { if (!stopping) emit('voice-failed'); })
            .finally(() => { voice = null; });
        } else if (submitted && state.waiting && !waiting) {
          waiting = true;
          emit('waiting');
        }
        await delay(joined ? 250 : 300);
      }
      if (stopping) {
        return await gracefulLeaveCall(wc, read, click, voice);
      }
      await codexSession?.dispose().catch(() => {});
      return submitted ? 'admission-timeout' : 'lobby-timeout';
    }

    // Microsoft Teams guest join loop
    let submitted = false;
    let joined = false;
    let voice;
    let waiting = false;
    let launcherNotified = false;
    let prejoinNotified = false;
    let earlySnapshotSaved = false;
    let dismissClicks = 0;
    let audioClicks = 0;
    let camClicks = 0;
    let prejoinSeenAt = 0;
    let joinedAt = 0;
    let postJoinMuted = false;
    const loopStartedAt = Date.now();
    let lastPollLogAt = 0;
    let deadline = Date.now() + 60_000;
    while (!stopping && (joined || Date.now() < deadline)) {
      if (teamsLoginRedirect) {
        await saveDiagnosticSnapshot(wc, 'teams-login-redirect');
        return 'teams-login-required';
      }
      const currentURL = wc.getURL();
      if (currentURL && currentURL !== 'about:blank' && !validNavigation(currentURL)) {
        await saveDiagnosticSnapshot(wc, `teams-invalid-url:${currentURL}`);
        return 'failed';
      }
      let state;
      try {
        state = await read();
      } catch (err) {
        if (consoleLogs.length < 60) consoleLogs.push(`[readErr] ${err?.message ?? err}`);
        await delay(300);
        continue;
      }
      const now = Date.now();
      if (!submitted && (state.nameInput?.present || state.enter) && !prejoinSeenAt) {
        prejoinSeenAt = now;
      }
      if (now - lastPollLogAt >= 5000) {
        lastPollLogAt = now;
        appendTeamsLog(`POLL frames=${state.frameCount ?? 1} cw=${Boolean(state.continueWeb)} name=${state.nameInput?.present}:${JSON.stringify(state.nameInput?.value ?? '')} enter=${Boolean(state.enter)} wait=${state.waiting} leave=${Boolean(state.leave)} joined=${joined} sub=${submitted} text=${JSON.stringify((state.hasBodyText || '').slice(0, 80))}`);
      }
      if (!earlySnapshotSaved && !submitted && now - loopStartedAt >= 8000) {
        earlySnapshotSaved = true;
        await saveDiagnosticSnapshot(wc, 'teams-early-8s');
      }
      if (joined && !state.leave) return 'left';
      if (state.rejected) {
        await saveDiagnosticSnapshot(wc, 'teams-rejected');
        return 'rejected';
      }
      if (!submitted && state.signInOnly) {
        await saveDiagnosticSnapshot(wc, 'teams-login-only');
        return 'teams-login-required';
      }
      if (!submitted && state.continueWeb) {
        if (!launcherNotified) { launcherNotified = true; emit('teams-launcher'); }
        appendTeamsLog(`CLICK continueWeb: ${state.continueWeb.name}`);
        await click(state.continueWeb);
        await delay(900);
      } else if (!submitted && state.dismiss && dismissClicks < 2) {
        dismissClicks++;
        appendTeamsLog(`CLICK dismiss(${dismissClicks}): ${state.dismiss.name}`);
        await click(state.dismiss);
      } else if (!submitted && state.computerAudio && audioClicks < 2) {
        audioClicks++;
        appendTeamsLog(`CLICK computerAudio(${audioClicks})`);
        await click(state.computerAudio);
      } else if (!submitted && state.cameraOn && camClicks < 2) {
        camClicks++;
        appendTeamsLog(`CLICK cameraOn(${camClicks})`);
        await click(state.cameraOn);
      } else if (!submitted && state.nameInput?.present && state.nameInput.value !== 'Nail') {
        if (!prejoinNotified) { prejoinNotified = true; emit('teams-prejoin'); }
        appendTeamsLog('FILL nameInput=Nail');
        await fillTeamsNameInTarget(wc, state.nameInput, 'Nail');
      } else if (!submitted && state.enter && (!state.nameInput?.present || state.nameInput.value === 'Nail')) {
        if (!prejoinNotified) { prejoinNotified = true; emit('teams-prejoin'); }
        const micCalls = provider
          ? await wc.executeJavaScript('window.__nailMedia?.micDiag?.().micCalls ?? 0').catch(() => 0)
          : 0;
        if (!provider || micCalls > 0 || now - prejoinSeenAt >= 2000) {
          if (provider && micCalls > 0) await delay(300);
          appendTeamsLog(`CLICK enter: ${state.enter.name} micCalls=${micCalls}`);
          if (await click(state.enter)) {
            submitted = true;
            deadline = Date.now() + 90_000;
            emit('submitted');
          }
        }
      } else if (submitted && state.waiting && !joined) {
        if (!waiting) {
          waiting = true;
          emit('waiting');
          appendTeamsLog('STATE waiting');
        }
      } else if (submitted && state.leave && !state.waiting && !joined) {
        if (provider && !await wc.executeJavaScript('Boolean(window.__nailMedia)')) {
          await saveDiagnosticSnapshot(wc, 'teams-voice-unavailable');
          return 'voice-unavailable';
        }
        joined = true;
        meetingJoined = true;
        syncCodexNotes();
        joinedAt = Date.now();
        appendTeamsLog('STATE joined');
        emit('joined');
        if (provider === 'codex' && codexSession) {
          codexSession.ensureConnected(wc, emit)
            .then(() => { if (!stopping && !voice) emit('voice-standby'); })
            .catch(() => {});
        }
      } else if (joined && !postJoinMuted && !voice && !turnRequested && Date.now() - joinedAt >= 1500) {
        postJoinMuted = true;
        if (state.mute) {
          const clicked = await click(state.mute);
          appendTeamsLog(`POST_JOIN_MUTE mute=${JSON.stringify(state.mute.name)} clicked=${clicked}`);
        } else {
          appendTeamsLog('POST_JOIN_MUTE alreadyMuted=true');
        }
      } else if (joined && provider && !voice && (turnRequested || provider !== 'codex' || (codexHandsFree && !codexWakeFailed))) {
        const manual = turnRequested;
        turnRequested = false;
        const inFollowUp = !manual && Date.now() < followUpUntil;
        if (!inFollowUp) followUpUntil = 0;
        voice = voiceTurn(wc, read, click, !manual, inFollowUp)
          .catch(() => { if (!stopping) emit('voice-failed'); })
          .finally(() => { voice = null; });
      }
      await delay(joined ? 250 : 350);
    }
    if (stopping) {
      if (!joined) await Promise.race([saveDiagnosticSnapshot(wc, submitted ? 'teams-stopped-waiting' : 'teams-stopped-lobby'), delay(1200)]);
      return await gracefulLeaveCall(wc, read, click, voice);
    }
    await saveDiagnosticSnapshot(wc, submitted ? 'teams-admission-timeout' : 'teams-lobby-timeout');
    await codexSession?.dispose().catch(() => {});
    return submitted ? 'admission-timeout' : 'lobby-timeout';
  }

  async function gracefulLeaveCall(wc, read, click, voicePromise) {
    try {
      const state = await Promise.race([read(), delay(1500).then(() => null)]);
      if (state?.leave) {
        const clicked = await Promise.race([click(state.leave), delay(1000).then(() => false)]);
        if (clicked) await delay(500);
      }
    } catch {}
    if (voicePromise) await Promise.race([voicePromise, delay(1000)]).catch(() => {});
    await Promise.race([codexSession?.dispose(), delay(1000)]).catch(() => {});
    return 'left';
  }

  function finalizeAndExit(eventName, exitCode = 0) {
    if (finalized) return;
    finalized = true;
    closeAvatar();
    clearTimeout(startup);
    if (shutdownFailsafe) {
      clearTimeout(shutdownFailsafe);
      shutdownFailsafe = null;
    }
    meetingJoined = false;
    stopCodexWakeDaemon();
    stopNotesWorker();
    if (agyDaemon) {
      killWorkerProcess(agyDaemon);
      agyDaemon = null;
    }
    try { codexSession?.child?.kill('SIGTERM'); } catch {}
    try {
      if (activeWin && !activeWin.isDestroyed()) activeWin.destroy();
    } catch {}
    if (eventName) emit(eventName);
    app.exit(exitCode);
  }

  for (const sig of ['SIGTERM', 'SIGINT']) {
    process.on(sig, () => {
      stopping = true;
      finalizeAndExit(null, 0);
    });
  }

  // Keep loading bounded even if Chromium does not resolve the initial navigation.
  const startupTimeoutMs = platform === 'teams' ? 45_000 : 35_000;
  const startup = setTimeout(async () => {
    if (platform === 'teams') appendTeamsLog(`STARTUP_TIMEOUT url=${activeWc && !activeWc.isDestroyed?.() ? activeWc.getURL() : 'none'}`);
    if (activeWc && !activeWc.isDestroyed?.()) {
      await Promise.race([saveDiagnosticSnapshot(activeWc, 'startup-timeout'), delay(2000)]);
    }
    finalizeAndExit('failed', 1);
  }, startupTimeoutMs);
  app.whenReady().then(() => {
    const stopDeadline = () => clearTimeout(startup);
    app.on('web-contents-created', (_event, wc) => wc.once('did-finish-load', stopDeadline));
    return run();
  }).then(async result => {
    clearTimeout(startup);
    meetingJoined = false;
    await Promise.race([notesTask, delay(1500)]).catch(() => {});
    await Promise.race([codexSession?.dispose(), delay(800)]).catch(() => {});
    if (result) {
      finalizeAndExit(result, result === 'left' ? 0 : 1);
    } else if (stopping) {
      finalizeAndExit('left', 0);
    }
  }).catch(async err => {
    clearTimeout(startup);
    meetingJoined = false;
    await Promise.race([notesTask, delay(1000)]).catch(() => {});
    if (platform === 'teams') appendTeamsLog(`UNHANDLED_ERR ${err?.stack || err?.message || err}`);
    if (activeWc && !activeWc.isDestroyed?.()) {
      await Promise.race([saveDiagnosticSnapshot(activeWc, `unhandled:${err?.code || err?.message || 'err'}`), delay(2000)]);
    }
    await Promise.race([codexSession?.dispose(), delay(800)]).catch(() => {});
    finalizeAndExit(stopping ? 'left' : 'failed', stopping ? 0 : 1);
  });
}

module.exports = { attributeNotes, createMeetingNotesMemory, detectPlatform, isAllowedTeamsHost, buildTeamsLightLaunchURL, inspectMeet, inspectTeams, fillTeamsName, findMeetPresentation, captureMeetPresentation, createPresentationOCRBridge, presentationRequestKind, shouldReadPresentation, meetAvatarCameraAction };
