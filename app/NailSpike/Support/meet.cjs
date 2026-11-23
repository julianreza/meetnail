const { app, BrowserWindow } = require('electron');
const { mkdirSync } = require('node:fs');
const { mkdtemp, readFile, rm, writeFile, stat } = require('node:fs/promises');
const { join } = require('node:path');
const { tmpdir } = require('node:os');
const { execFile, spawn } = require('node:child_process');
const { promisify } = require('node:util');
const { createInterface } = require('node:readline');
const { setTimeout: delay } = require('node:timers/promises');
const { codexVoice } = require('./codex-voice.cjs');

const [target, profile, provider, pipeline] = process.argv.slice(2);
const login = target === '--login';
if (!profile || (!login && !/^https:\/\/meet\.google\.com\/[a-z]{3}-[a-z]{4}-[a-z]{3}$/.test(target ?? ''))) process.exit(2);
if (provider && provider !== 'codex' && ((provider !== 'deepseek' && provider !== 'antigravity') || !pipeline)) process.exit(2);
mkdirSync(profile, {recursive: true, mode: 0o700});
app.setPath('userData', profile);
const emit = event => console.log(event);
let stopping = false;
const consoleLogs = [];
const cancelVoice = new AbortController();
let turnRequested = false;
let agyDaemon = null;
let agyLines = null;
let agyReady = null;
function startAgyDaemon() {
  if (provider !== 'antigravity' || agyDaemon) return;
  const env = {...process.env, PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.HOME}/.local/bin:${process.env.PATH ?? '/usr/bin:/bin'}`};
  agyDaemon = spawn('/opt/homebrew/bin/uv', ['run', '--offline', '--script', pipeline, '--daemon'],
    {env, stdio: ['pipe', 'pipe', 'ignore']});
  const rl = createInterface({input: agyDaemon.stdout, terminal: false});
  const waiters = [];
  rl.on('line', line => { const w = waiters.shift(); if (w) w.resolve(line); });
  agyDaemon.on('exit', () => {
    while (waiters.length) waiters.shift().reject(new Error('agy daemon exited'));
    agyDaemon = null; agyLines = null; agyReady = null;
  });
  agyLines = () => new Promise((resolve, reject) => waiters.push({resolve, reject}));
  agyReady = agyLines().then(line => JSON.parse(line));
}
let activeWc = null;
const commands = createInterface({input: process.stdin, terminal: false});
commands.on('line', line => {
  if (line === 'voice-turn') {
    turnRequested = true;
    activeWc?.executeJavaScript('window.__nailUpgradeRecord?.()').catch(() => {});
  }
});
commands.on('close', () => { stopping = true; cancelVoice.abort(); agyDaemon?.kill(); });

// Inspect the real Meet controls; never fabricate an admission or enable a disabled button.
function inspect() {
  const label = element => (element.getAttribute('aria-labelledby') || '').split(/\s+/)
    .map(id => document.getElementById(id)?.textContent || '').join(' ').trim() ||
    (element.getAttribute('aria-label') || element.innerText || '').trim();
  const controls = [...document.querySelectorAll('button,[role=button],a')];
  const visible = element => element.getClientRects().length > 0 && getComputedStyle(element).visibility === 'visible';
  const action = names => {
    const match = text => names.some(n => text === n || text.startsWith(`${n} (`));
    const element = controls.find(e => match(label(e)) && !e.matches(':disabled,[aria-disabled="true"]') && visible(e) && (() => {
      const r = e.getBoundingClientRect();
      return e.contains(document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2));
    })());
    if (!element) return null;
    const r = element.getBoundingClientRect();
    return {x: r.x + r.width / 2, y: r.y + r.height / 2, name: label(element)};
  };
  const text = document.body?.innerText ?? '';
  return {
    signedIn: controls.some(e => /^(Switch account|Change account|Switch Google Account|Ganti akun)$/i.test(label(e)) && visible(e)),
    signIn: action(['Sign in', 'Sign in with Google', 'Login', 'Masuk', 'Masuk dengan Google']),
    skip: action(['Continue without microphone and camera', 'Lanjutkan tanpa mikrofon dan kamera']),
    dismiss: action(['Got it', 'Mengerti', 'Oke']),
    unmute: action(['Turn on microphone', 'Aktifkan mikrofon', 'Nyalakan mikrofon']),
    mute: action(['Turn off microphone', 'Nonaktifkan mikrofon']),
    enter: action(['Join now', 'Join meeting', 'Ask to join', 'Gabung sekarang', 'Bergabung sekarang', 'Minta bergabung']),
    leave: action(['Leave call', 'Tutup panggilan']),
    rejected: [...document.querySelectorAll('h1,h2,[role=heading]')].some(e => visible(e) &&
      /^(You can[’']t join this video call|Anda tidak (dapat|bisa) bergabung.*)$/i.test(label(e))),
    waiting: /Asking to join|Someone in the meeting should let you in|Waiting for (the )?host|Menunggu.*(penyelenggara|host)|Meminta untuk bergabung/i.test(text),
  };
}

async function voiceTurn(wc, read, click, auto = false) {
  const work = await mkdtemp(join(tmpdir(), 'nail-meet-'));
  const input = join(work, 'meeting.webm');
  const output = join(work, 'reply.wav');
  let restoreMute = false;
  try {
    emit(auto ? 'voice-standby' : 'voice-recording');
    const clip = await wc.executeJavaScript(`__nailMedia.record(8000, ${Boolean(auto)})`, true);
    if (stopping) return;
    const manual = !auto || turnRequested;
    if (turnRequested) turnRequested = false;
    const diag = await wc.executeJavaScript('window.__nailDiagnostics ?? null', true);
    if (!clip) {
      if (!manual) return;
      // Diagnostic snapshot of what Meet shows inside Nail's hidden window.
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
    if (manual) emit('voice-processing');
    let result, audio;
    if (provider === 'codex') {
      result = await codexVoice(clip, cancelVoice.signal, emit);
      audio = result.audio;
    } else if (provider === 'antigravity') {
      await writeFile(input, Buffer.from(clip, 'base64'), {mode: 0o600});
      startAgyDaemon();
      await agyReady;
      agyDaemon.stdin.write(`${JSON.stringify({from_wav: input, reply_wav: output, require_wake: !manual})}\n`);
      let msg = JSON.parse(await agyLines());
      if (msg.event === 'wake') {
        emit(`voice-wake ${JSON.stringify({heard: msg.heard ?? ''})}`);
        msg = JSON.parse(await agyLines());
      }
      result = msg;
      if (result.error) throw new Error(result.error);
      if (result.skipped) return;
      if (!result.reply) { if (manual) emit(`voice-no-audio ${JSON.stringify(diag ?? {})}`); return; }
      if ((await stat(output)).size > 2_000_000) throw new Error('Reply audio too large');
      audio = (await readFile(output)).toString('base64');
    } else {
      await writeFile(input, Buffer.from(clip, 'base64'), {mode: 0o600});
      const extraArgs = manual ? [] : ['--require', 'Nail'];
      const {stdout} = await promisify(execFile)('/usr/bin/python3',
        [pipeline, '--from-wav', input, '--reply-wav', output, '--no-notulen', ...extraArgs],
        {signal: cancelVoice.signal, timeout: 65_000,
          env: {...process.env, PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.HOME}/.local/bin:${process.env.PATH ?? '/usr/bin:/bin'}`}});
      const line = stdout.trim().split(/\r?\n/).pop() ?? '';
      result = JSON.parse(line);
      if (result.skipped) return;
      if (!result.reply) { if (manual) emit(`voice-no-audio ${JSON.stringify(diag ?? {})}`); return; }
      if ((await stat(output)).size > 2_000_000) throw new Error('Reply audio too large');
      audio = (await readFile(output)).toString('base64');
    }
    if (stopping) return;
    emit('voice-sending');
    const {unmute} = await read();
    if (unmute) restoreMute = await click(unmute);
    const deadline = Date.now() + 3000;
    while (!stopping && Date.now() < deadline && !await wc.executeJavaScript('__nailMedia.sending()')) await delay(150);
    if (stopping) return;
    if (!await wc.executeJavaScript('__nailMedia.sending()')) {
      try {
        const dir = join(require('node:os').homedir(), 'Library/Logs/Nail');
        mkdirSync(dir, {recursive: true});
        await writeFile(join(dir, 'meet-nomic.png'), (await wc.capturePage()).toPNG());
        const info = await wc.executeJavaScript('JSON.stringify({mic: __nailMedia.micDiag(), buttons: [...document.querySelectorAll("button,[role=button]")].map(b => b.getAttribute("aria-label") || b.innerText).filter(Boolean).slice(0, 40)}, null, 1)');
        await writeFile(join(dir, 'meet-nomic.txt'), `${JSON.stringify({unmute, restoreMute})}\n\n${info}\n`);
      } catch {}
      emit('voice-no-mic');
      return;
    }
    if (!audio || audio.length > 2_700_000) throw new Error('Invalid reply audio');
    if (stopping) return;
    await wc.executeJavaScript(`__nailMedia.play(${JSON.stringify(audio)})`, true);
    if (!stopping) emit(`voice-result ${JSON.stringify({heard: result.heard, reply: result.reply})}`);
    if (!stopping) await delay(500);
  } catch (error) {
    try {
      const dir = join(require('node:os').homedir(), 'Library/Logs/Nail');
      mkdirSync(dir, {recursive: true});
      await writeFile(join(dir, 'voice-error.log'), `${new Date().toISOString()} ${error?.stack || error?.message || error}\n${error?.stderr ?? ''}\n`);
    } catch {}
    if (!stopping) emit(/^voice-codex-(quota|login|missing|timeout|error|connection|no-transcript)$/.test(error.message) ? error.message : 'voice-failed');
  } finally {
    if (restoreMute && !wc.isDestroyed()) {
      try {
        const {mute} = await read();
        if (mute) await click(mute);
      } catch {}
    }
    await rm(work, {recursive: true, force: true});
  }
}

async function run() {
  app.dock.hide();
  const win = new BrowserWindow({show: false, title: 'Login Google untuk Nail', width: 1280, height: 860,
    webPreferences: {partition: 'persist:nail-signin', sandbox: true, contextIsolation: true,
      nodeIntegration: false, backgroundThrottling: false, devTools: false,
      ...(provider ? {preload: join(__dirname, 'meet-media.cjs')} : {})}});
  const wc = win.webContents;
  activeWc = wc;
  wc.session.setPermissionCheckHandler(() => false);
  wc.session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
  wc.session.setDisplayMediaRequestHandler((_request, callback) => callback({}));
  wc.setWindowOpenHandler(() => ({action: 'deny'}));
  wc.setAudioMuted(true);
  consoleLogs.length = 0;
  wc.on('console-message', (ev, levelArg, msgArg) => {
    const level = typeof ev?.level === 'number' ? ev.level : levelArg;
    const message = typeof ev?.message === 'string' ? ev.message : msgArg;
    if (level >= 2 && consoleLogs.length < 60) consoleLogs.push(`[${level}] ${String(message).slice(0, 300)}`);
  });
  const loginOrigins = new Set(['https://accounts.google.com', 'https://myaccount.google.com', 'https://www.google.com']);
  const validNavigation = value => {
    if (!URL.canParse(value)) return false;
    const url = new URL(value);
    return login ? loginOrigins.has(url.origin) : `${url.origin}${url.pathname}` === target;
  };
  const guardNavigation = event => {
    if (!validNavigation(event.url)) event.preventDefault();
  };
  wc.on('will-navigate', guardNavigation);
  wc.on('will-redirect', event => { if (event.isMainFrame) guardNavigation(event); });
  win.on('closed', () => app.quit());

  if (login) {
    process.stdin.once('end', () => app.quit());
    await wc.loadURL('https://accounts.google.com/');
    win.show();
    emit('login-panel');
    return;
  }

  const read = () => wc.executeJavaScript(`(${inspect})()`);
  startAgyDaemon();
  const click = ({x, y, name}) => wc.executeJavaScript(`(() => {
    const element = document.elementFromPoint(${x}, ${y})?.closest('button,[role=button]');
    if (!element || element.matches(':disabled,[aria-disabled="true"]')) return false;
    const label = (element.getAttribute('aria-labelledby') || '').split(/\\s+/)
      .map(id => document.getElementById(id)?.textContent || '').join(' ').trim() ||
      (element.getAttribute('aria-label') || element.innerText || '').trim();
    if (label !== ${JSON.stringify(name)}) return false;
    element.click();
    return true;
  })()`);

  await wc.loadURL(target);
  if (provider && !await wc.executeJavaScript('Boolean(window.__nailMedia)')) return 'voice-unavailable';
  let submitted = false;
  let joined = false;
  let voice;
  let skipped = false;
  let dismissed = false;
  let waiting = false;
  let deadline = Date.now() + 30_000;
  while (!stopping && (joined || Date.now() < deadline)) {
    if (!validNavigation(wc.getURL())) return 'failed';
    const state = await read();
    if (joined && !state.leave) return 'left';
    if (state.rejected) return 'rejected';
    if (!submitted && state.skip && !skipped) skipped = await click(state.skip);
    else if (!submitted && state.dismiss && !dismissed) dismissed = await click(state.dismiss);
    else if (!submitted && state.signIn && !state.signedIn) return 'login-required';
    else if (!submitted && state.signedIn && state.enter && !state.skip && await click(state.enter)) {
      submitted = true;
      deadline = Date.now() + 90_000;
      emit('submitted');
    } else if (submitted && state.leave && !joined) {
      joined = true;
      emit('joined');
    } else if (joined && provider && !voice && (turnRequested || provider !== 'codex')) {
      const manual = turnRequested;
      turnRequested = false;
      voice = voiceTurn(wc, read, click, !manual)
        .catch(() => { if (!stopping) emit('voice-failed'); })
        .finally(() => { voice = null; });
    } else if (submitted && state.waiting && !waiting) {
      waiting = true;
      emit('waiting');
    }
    await delay(joined ? 1000 : 300);
  }
  if (stopping) {
    const state = await read();
    if (state.leave && await click(state.leave)) await delay(600);
    if (voice) await voice;
    return 'left';
  }
  return submitted ? 'admission-timeout' : 'lobby-timeout';
}

// Keep loading bounded even if Chromium does not resolve the initial navigation.
const startup = setTimeout(() => { emit('failed'); app.exit(1); }, 35_000);
app.whenReady().then(() => {
  const stopDeadline = () => clearTimeout(startup);
  // The navigation/loop has its own timeout after the first load.
  app.on('web-contents-created', (_event, wc) => wc.once('did-finish-load', stopDeadline));
  return run();
}).then(result => {
  clearTimeout(startup);
  if (result) {
    emit(result);
    app.exit(result === 'left' ? 0 : 1);
  }
}).catch(() => { emit('failed'); app.exit(1); });
