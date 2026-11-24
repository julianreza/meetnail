function installMedia(enableAvatar = false) {
  // Both destinations are in-memory Web Audio streams, never hardware devices.
  const isTeams = location.hostname !== 'meet.google.com';
  const avatarAllowed = enableAvatar && location.origin === 'https://meet.google.com';
  const avatarDeviceId = 'nail-avatar';
  let avatar;
  let avatarPrepared = false;
  const stopAvatarCamera = revision => {
    if (!avatar || revision < avatar.revision) return;
    for (const track of avatar.tracks) track.stop();
    avatar = null;
  };
  const prepareAvatarCamera = revision => {
    if (!avatarAllowed || !Number.isInteger(revision) || revision <= (avatar?.revision ?? 0)) return false;
    stopAvatarCamera(revision);
    const canvas = document.createElement('canvas');
    canvas.width = 1280;
    canvas.height = 720;
    const ctx = canvas.getContext('2d', {alpha: false});
    if (!ctx) return false;
    const track = canvas.captureStream(20).getVideoTracks()[0];
    if (!track) return false;
    track.contentHint = 'detail';
    avatar = {revision, canvas, ctx, track, tracks: new Set([track]), ready: false};
    avatarPrepared = true;
    return true;
  };
  const drawAvatarFrame = async (revision, encoded) => {
    const source = avatar;
    if (!source || source.revision !== revision || typeof encoded !== 'string' || encoded.length > 1_398_104) return false;
    let frame;
    try {
      const bytes = Uint8Array.from(atob(encoded), char => char.charCodeAt(0));
      frame = await createImageBitmap(new Blob([bytes], {type: 'image/jpeg'}));
      if (avatar !== source || frame.width !== source.canvas.width || frame.height !== source.canvas.height) return false;
      source.ctx.drawImage(frame, 0, 0);
      source.ready = true;
      return true;
    } catch {
      return false;
    } finally {
      frame?.close();
    }
  };
  const decorateAvatarTrack = track => {
    for (const prior of avatar.tracks) if (prior.readyState === 'ended') avatar.tracks.delete(prior);
    avatar.tracks.add(track);
    track.contentHint = 'detail';
    const getSettings = track.getSettings.bind(track);
    Object.defineProperties(track, {
      label: {value: 'Nail'},
      getSettings: {value: () => ({...getSettings(), deviceId: avatarDeviceId, groupId: 'nail'})},
    });
    return track;
  };
  const Peer = window.RTCPeerConnection;
  const OrigAudioContext = window.AudioContext;
  const OrigWebkitAudioContext = window.webkitAudioContext;
  const pageContexts = new Set();
  const issuedTracks = [];
  let pageVirtualSources = 0;
  const resumePageContexts = () => {
    for (const c of pageContexts) {
      if (c.state === 'suspended') c.resume().catch(() => {});
    }
  };
  const remote = new Map();
  const peers = new Set();
  const virtualTracks = new WeakSet();
  const replacedSenders = new Map();
  let lastInjectedStats = null;
  const snapshotSendersStats = async sendersToRead => {
    const set = new Set(sendersToRead);
    if (!set.size) return null;
    const rows = [];
    for (const peer of peers) {
      if (!peer.getSenders().some(s => set.has(s))) continue;
      const outbound = [];
      const mediaSource = [];
      try {
        for (const r of (await peer.getStats()).values()) {
          if (r.type === 'outbound-rtp' && r.kind === 'audio') {
            outbound.push({packetsSent: r.packetsSent ?? 0, bytesSent: r.bytesSent ?? 0, active: r.active ?? null});
          } else if (r.type === 'media-source' && r.kind === 'audio') {
            mediaSource.push({audioLevel: r.audioLevel ?? null, totalAudioEnergy: r.totalAudioEnergy ?? 0, totalSamplesDuration: r.totalSamplesDuration ?? 0});
          }
        }
      } catch {}
      rows.push({outbound, mediaSource});
    }
    return rows.length ? rows : null;
  };
  const attachTeamsVirtualSenders = async () => {
    if (!isTeams) return 0;
    await start();
    const baseTrack = mic?.stream?.getAudioTracks?.()[0];
    if (!baseTrack || baseTrack.readyState !== 'live') return 0;
    let count = 0;
    for (const peer of peers) {
      if (peer.connectionState !== 'connected' && peer.iceConnectionState !== 'connected' && peer.iceConnectionState !== 'completed') {
        continue;
      }
      for (const sender of peer.getSenders()) {
        const cur = sender.track;
        if (!cur || cur.kind !== 'audio' || cur.readyState !== 'live') continue;
        if (virtualTracks.has(cur) || replacedSenders.has(sender)) continue;
        const injectedTrack = decorateVirtualTrack(baseTrack.clone());
        try {
          await sender.replaceTrack(injectedTrack);
          replacedSenders.set(sender, {origTrack: cur, injectedTrack});
          count++;
        } catch {
          try { injectedTrack.stop(); } catch {}
        }
      }
    }
    return count;
  };
  const restoreTeamsSenders = async () => {
    if (!replacedSenders.size) return;
    const entries = [...replacedSenders.entries()];
    replacedSenders.clear();
    const snap = await snapshotSendersStats(entries.map(([sender]) => sender)).catch(() => null);
    if (snap) lastInjectedStats = snap;
    for (const [sender, {origTrack, injectedTrack}] of entries) {
      try {
        if (sender.track === injectedTrack && origTrack?.readyState === 'live') {
          await sender.replaceTrack(origTrack);
        }
      } catch {}
      try { injectedTrack.stop(); } catch {}
    }
  };
  const wrapAudioContext = BaseCtx => {
    if (typeof BaseCtx !== 'function') return BaseCtx;
    return new Proxy(BaseCtx, {
      construct(Target, args, NewTarget) {
        const ctx = Reflect.construct(Target, args, NewTarget);
        pageContexts.add(ctx);
        ctx.addEventListener?.('statechange', () => {
          if (ctx.state === 'closed') pageContexts.delete(ctx);
        });
        if (ctx.state === 'suspended') ctx.resume().catch(() => {});
        const origCreateMSS = typeof ctx.createMediaStreamSource === 'function'
          ? ctx.createMediaStreamSource.bind(ctx)
          : null;
        if (origCreateMSS) {
          ctx.createMediaStreamSource = stream => {
            try {
              if (stream?.getAudioTracks?.().some(t => virtualTracks.has(t))) {
                pageVirtualSources++;
              }
            } catch {}
            return origCreateMSS(stream);
          };
        }
        return ctx;
      },
    });
  };
  if (typeof OrigAudioContext === 'function') {
    window.AudioContext = wrapAudioContext(OrigAudioContext);
  }
  if (typeof OrigWebkitAudioContext === 'function' && OrigWebkitAudioContext !== OrigAudioContext) {
    window.webkitAudioContext = wrapAudioContext(OrigWebkitAudioContext);
  } else if (OrigWebkitAudioContext && OrigWebkitAudioContext === OrigAudioContext) {
    window.webkitAudioContext = window.AudioContext;
  }
  const gumLog = [];
  const pushGum = (c, outcome) => {
    gumLog.push({audio: Boolean(c?.audio), video: Boolean(c?.video), outcome});
    if (gumLog.length > 25) gumLog.shift();
  };
  let context, mic, micBus, micMeter, micMeterBuf, mix;
  const decorateVirtualTrack = track => {
    if (!track) return track;
    virtualTracks.add(track);
    try {
      const desc = Object.getOwnPropertyDescriptor(track, 'label');
      if (!desc || desc.configurable) {
        Object.defineProperty(track, 'label', {get: () => 'Nail', configurable: true});
      }
    } catch {}
    if (!track.__nailSettingsWrapped) {
      const origGetSettings = typeof track.getSettings === 'function' ? track.getSettings.bind(track) : () => ({});
      const wrappedGetSettings = () => ({
        ...origGetSettings(),
        deviceId: 'nail-virtual-mic',
        groupId: 'nail',
        channelCount: 1,
        sampleRate: context?.sampleRate || 48000,
        autoGainControl: false,
        echoCancellation: false,
        noiseSuppression: false,
      });
      try {
        Object.defineProperty(track, 'getSettings', {value: wrappedGetSettings, configurable: true});
        Object.defineProperty(track, '__nailSettingsWrapped', {value: true, configurable: true});
      } catch {}
    }
    return track;
  };
  const origClone = MediaStreamTrack.prototype.clone;
  MediaStreamTrack.prototype.clone = function () {
    const cloned = origClone.apply(this, arguments);
    if (virtualTracks.has(this)) decorateVirtualTrack(cloned);
    if (avatar?.tracks.has(this)) decorateAvatarTrack(cloned);
    return cloned;
  };
  let micCalls = 0;
  const makePerm = (name, state) => ({
    state,
    name,
    onchange: null,
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() { return true; },
  });
  const perms = navigator.permissions;
  if (perms?.query) {
    const origQuery = perms.query.bind(perms);
    perms.query = desc => {
      if (desc?.name === 'microphone') {
        return Promise.resolve(makePerm('microphone', 'granted'));
      }
      if (isTeams && desc?.name === 'camera') {
        return Promise.resolve(makePerm('camera', 'prompt'));
      }
      if (avatarAllowed && desc?.name === 'camera') {
        return Promise.resolve(makePerm('camera', 'granted'));
      }
      return origQuery(desc);
    };
  }
  const diagLog = [];
  const encStats = [];
  const OrigWorker = window.Worker;
  if (OrigWorker) {
    window.Worker = new Proxy(OrigWorker, {
      construct(Target, args, NewTarget) {
        const w = Reflect.construct(Target, args, NewTarget);
        w.addEventListener('error', e => diagLog.push(`workerErr:${e.message}@${e.lineno}`));
        w.addEventListener('messageerror', () => diagLog.push('workerMsgErr'));
        return w;
      },
    });
  }
  const encProto = window.RTCRtpReceiver?.prototype;
  if (encProto?.createEncodedStreams) {
    const origEnc = encProto.createEncodedStreams;
    encProto.createEncodedStreams = function () {
      const kind = this.track?.kind;
      const id = this.track?.id?.slice(0, 8);
      diagLog.push(`createEncodedStreams(${kind}:${id})`);
      const streams = origEnc.apply(this, arguments);
      if (kind !== 'audio') return streams;
      const st = {id, inC: 0, outC: 0, inBytes: 0, outBytes: 0, err: null};
      encStats.push(st);
      const writer = streams.writable.getWriter();
      let meetActive = false;
      const inTap = new TransformStream({async transform(f, c) {
        st.inC++; st.inBytes += f.data?.byteLength ?? 0;
        if (meetActive) { c.enqueue(f); return; }
        let copy = null;
        try { copy = new RTCEncodedAudioFrame(f); } catch {}
        try { await writer.write(f); } catch (e) { st.err = e?.message ?? String(e); }
        if (copy) c.enqueue(copy);
      }});
      const outWritable = new WritableStream({async write(f) {
        meetActive = true;
        st.outC++; st.outBytes += f.data?.byteLength ?? 0;
        await writer.write(f);
      }});
      streams.readable.pipeTo(inTap.writable).catch(e => { st.err = e?.message ?? String(e); });
      return {readable: inTap.readable, writable: outWritable};
    };
  }
  let activePlayer = null;
  let activePlayDone = null;
  let lastPlayEndedAt = 0;
  const activeRecordTrackAttach = new Set();
  const waitForLiveTrack = async (attachedTracks, attachRemoteTrack, idleWaitMs, setNotify) => {
    if (attachedTracks.size > 0) return true;
    const waitMs = Math.max(0, Math.min(idleWaitMs, 1500));
    if (waitMs <= 0) return attachedTracks.size > 0;
    let aborted = false;
    await new Promise(resolve => {
      let settled = false;
      const done = () => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        setNotify(null);
        if (window.__nailAbortRecord === onAbort) window.__nailAbortRecord = null;
        resolve();
      };
      const onAbort = () => {
        aborted = true;
        done();
      };
      setNotify(() => {
        if (attachedTracks.size > 0) done();
      });
      window.__nailAbortRecord = onAbort;
      const timer = setTimeout(done, waitMs);
      for (const track of remote.keys()) attachRemoteTrack(track);
      if (attachedTracks.size > 0) done();
    });
    return !aborted && attachedTracks.size > 0;
  };
  let readRecordingPreview = null;
  const audioBase64 = data => {
    const bytes = new Uint8Array(data);
    let binary = '';
    for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    return btoa(binary);
  };
  let codexInBus = null;
  const codexBusSources = new Map();
  let codexBridge = null;
  let abortCodexSpeech = null;
  let notesSession = null;
  let notesOperation = Promise.resolve();
  const notesPending = [];
  const notesErrors = [];
  const notesRun = operation => {
    const result = notesOperation.then(operation);
    notesOperation = result.catch(() => {});
    return result;
  };
  const notesCaptionCapture = () => {
    // Meet's nMcdL/ygicle turn and Teams' ChatMessageCompact pair have explicit
    // caption leaves. Guest Teams also renders an author and text as direct children of one row.
    const scope = isTeams ? '[data-tid="closed-caption-renderer-wrapper"]' :
      ':is([aria-live]:not([aria-live="off"]), [role="region"][aria-label="Captions"])';
    const namedRow = isTeams ? '.fui-ChatMessageCompact' : '.nMcdL';
    const author = isTeams ? '[data-tid="author"]' : '.NWpY1d, .xoMHSc';
    const body = isTeams ? '[data-tid="closed-caption-text"]' : '.ygicle';
    const evidence = [];
    let previousRows = new Map();
    let active = true;
    const sample = (baseline = false) => {
      // Evidence is optional; a missing or changed captions DOM must not affect audio.
      try {
        const matches = document.querySelectorAll(`${scope} ${isTeams ? '' : `${namedRow} `}${body}`);
        const rows = new Map();
        const seenAtMs = Date.now();
        for (let i = Math.max(0, matches.length - 32); i < matches.length; i++) {
          const textNode = matches[i];
          const knownRow = textNode.closest(namedRow);
          const row = knownRow ?? (isTeams ? textNode.parentElement : null);
          if (!row?.parentElement?.closest(scope)) continue;
          const authors = row.querySelectorAll(knownRow ? author : `:scope > ${author}`);
          const texts = row.querySelectorAll(body);
          if (authors.length !== 1 || texts.length !== 1 || texts[0] !== textNode ||
              authors[0].contains(textNode) || textNode.contains(authors[0])) continue;
          const speaker = authors[0].textContent.trim();
          const text = textNode.textContent.trim();
          if (!speaker || speaker.length > 160 || !text || text.length > 1200 || text === speaker) continue;
          const previous = previousRows.get(row);
          const unchanged = previous?.text === text;
          // Do not carry an in-progress caption from before recording into this interval.
          const stale = baseline || Boolean(previous?.stale && (unchanged ||
            (previous.speaker === speaker && (text.startsWith(previous.text) || previous.text.startsWith(text)))));
          rows.set(row, {speaker, text, stale});
          if (stale || unchanged) continue;
          if (evidence.length === 384) evidence.shift();
          evidence.push({speaker, text, seenAtMs});
        }
        previousRows = rows;
      } catch {}
    };
    sample(true);
    const timer = setInterval(sample, 250);
    return {
      snapshot(startedAtMs, endedAtMs) {
        if (active) sample();
        return evidence.filter(({seenAtMs}) => seenAtMs >= startedAtMs && seenAtMs <= endedAtMs + 3000);
      },
      stop() {
        sample();
        active = false;
        clearInterval(timer);
        previousRows.clear();
      },
    };
  };
  const notesAttach = track => {
    const session = notesSession;
    if (!session || track.kind !== 'audio' || track.readyState !== 'live' || session.sources.has(track)) return;
    try {
      const source = context.createMediaStreamSource(new MediaStream([track]));
      source.connect(session.destination);
      session.sources.set(track, source);
    } catch (error) {
      notesErrors.push(error);
    }
  };
  const notesDetach = track => {
    const source = notesSession?.sources.get(track);
    if (!source) return;
    source.disconnect();
    notesSession.sources.delete(track);
  };
  const notesRecorder = session => {
    const recorder = new MediaRecorder(session.destination.stream, {
      mimeType: 'audio/webm;codecs=opus', audioBitsPerSecond: 64000,
    });
    const entry = {recorder, chunks: [], error: null};
    entry.done = new Promise(resolve => {
      let finished = false;
      entry.finish = () => {
        if (finished) return;
        finished = true;
        resolve({blob: new Blob(entry.chunks, {type: recorder.mimeType}), error: entry.error});
      };
      recorder.ondataavailable = event => {
        if (event.data.size) entry.chunks.push(event.data);
      };
      recorder.onerror = event => {
        entry.error = event.error || new Error('Notes recorder failed');
      };
      recorder.onstop = () => {
        entry.endedAtMs ??= Date.now();
        if (session.current === entry) {
          session.current = null;
          notesPending.push(entry);
          entry.error ||= new Error('Notes recorder stopped unexpectedly');
        }
        entry.finish();
      };
    });
    entry.captions = session.captions;
    entry.startedAtMs = Date.now();
    recorder.start();
    return entry;
  };
  const notesRotate = session => {
    const previous = session.current;
    const next = notesRecorder(session);
    session.current = next;
    if (previous) {
      notesPending.push(previous);
      previous.endedAtMs = next.startedAtMs;
      try {
        if (previous.recorder.state !== 'inactive') previous.recorder.stop();
      } catch (error) {
        previous.error = error;
        previous.finish();
      }
    }
  };
  const notesRead = async () => {
    if (notesErrors.length) throw notesErrors.shift();
    while (notesPending.length) {
      const entry = notesPending[0];
      const {blob, error} = await entry.done;
      if (blob.size) {
        const bytes = new Uint8Array(await blob.arrayBuffer());
        let binary = '';
        for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
        const encoded = btoa(binary);
        notesPending.shift();
        if (error) notesErrors.push(error);
        return {
          audio: encoded,
          startedAtMs: entry.startedAtMs,
          captions: entry.captions.snapshot(entry.startedAtMs, entry.endedAtMs),
        };
      }
      notesPending.shift();
      if (error) notesErrors.push(error);
    }
    if (notesErrors.length) throw notesErrors.shift();
    return null;
  };
  const notesStart = () => notesRun(async () => {
    if (notesSession) return;
    await start();
    if (context.state !== 'running') throw new Error('Notes audio context is not running');
    const session = {destination: context.createMediaStreamDestination(), sources: new Map(), current: null, timer: null};
    notesSession = session;
    try {
      for (const track of remote.keys()) notesAttach(track);
      session.captions = notesCaptionCapture();
      session.current = notesRecorder(session);
      session.timer = setInterval(() => {
        notesRun(() => {
          if (notesSession !== session) return;
          notesRotate(session);
        }).catch(error => notesErrors.push(error));
      }, 15000);
    } catch (error) {
      session.captions?.stop();
      for (const source of session.sources.values()) source.disconnect();
      session.destination.stream.getTracks().forEach(track => track.stop());
      notesSession = null;
      throw error;
    }
  });
  const notesTake = () => notesRun(async () => {
    return notesRead();
  });
  const notesStop = () => notesRun(async () => {
    const session = notesSession;
    if (session) {
      session.captions.stop();
      notesSession = null;
      clearInterval(session.timer);
      if (session.current) {
        const entry = session.current;
        session.current = null;
        entry.endedAtMs = Date.now();
        notesPending.push(entry);
        try {
          if (entry.recorder.state !== 'inactive') entry.recorder.stop();
        } catch (error) {
          entry.error = error;
          entry.finish();
        }
        await entry.done;
      }
      for (const source of session.sources.values()) source.disconnect();
      session.destination.stream.getTracks().forEach(track => track.stop());
    }
    return notesRead();
  });
  const appendDcUnique = (list, raw) => {
    if (typeof raw !== 'string') return;
    const text = raw.trim();
    if (!text) return;
    if (list.length === 0 || list[list.length - 1] !== text) list.push(text);
  };
  const wireCodexDataChannel = (bridge, channel) => {
    if (!channel || bridge.wiredChannels?.has(channel)) return;
    if (!bridge.wiredChannels) bridge.wiredChannels = new Set();
    bridge.wiredChannels.add(channel);
    channel.addEventListener('message', ev => {
      if (codexBridge !== bridge || typeof ev.data !== 'string') return;
      let msg;
      try { msg = JSON.parse(ev.data); } catch { return; }
      if (!msg || typeof msg.type !== 'string') return;
      const eventResponseId = msg.response_id ?? msg.response?.id ?? null;
      if (msg.type === 'response.created') {
        bridge.serverResponseInFlight = true;
        if (msg.response?.id) bridge.activeResponseId = msg.response.id;
      } else if (msg.type === 'response.done') {
        bridge.serverResponseInFlight = false;
        if (!msg.response?.id || bridge.activeResponseId === msg.response.id) {
          bridge.activeResponseId = null;
        }
      }
      if (!bridge.dcAcceptingTurn) return;
      bridge.dcEvents.push(msg.type);
      if (bridge.dcEvents.length > 40) bridge.dcEvents.shift();
      if (eventResponseId && bridge.cancelledResponseIds?.has(eventResponseId)) {
        return;
      }
      switch (msg.type) {
        case 'response.created':
          break;
        case 'response.output_audio_transcript.delta':
        case 'response.audio_transcript.delta':
        case 'response.text.delta':
          if (typeof msg.delta === 'string') bridge.dcReplyDelta += msg.delta;
          break;
        case 'response.output_audio_transcript.done':
        case 'response.audio_transcript.done':
        case 'response.text.done':
          appendDcUnique(bridge.dcReplyParts, msg.transcript ?? msg.text ?? bridge.dcReplyDelta);
          bridge.dcReplyDelta = '';
          break;
        case 'response.done':
          if (msg.response?.status === 'cancelled') {
            if (msg.response?.id) bridge.cancelledResponseIds?.add(msg.response.id);
            if (bridge.activeResponseId === msg.response?.id) bridge.activeResponseId = null;
            break;
          }
          bridge.dcReplyDone = true;
          if (bridge.dcReplyParts.length === 0 && !bridge.dcReplyDelta.trim() && Array.isArray(msg.response?.output)) {
            for (const outItem of msg.response.output) {
              for (const part of outItem?.content ?? []) {
                appendDcUnique(bridge.dcReplyParts, part?.transcript ?? part?.text);
              }
            }
          }
          break;
        case 'conversation.item.input_audio_transcription.delta':
          if (typeof msg.delta === 'string') bridge.dcHeardDelta += msg.delta;
          break;
        case 'conversation.item.input_audio_transcription.completed':
          appendDcUnique(bridge.dcHeardParts, msg.transcript ?? bridge.dcHeardDelta);
          bridge.dcHeardDelta = '';
          break;
      }
    });
  };
  const attachTrackToCodexBus = track => {
    if (!codexInBus || !context || track.kind !== 'audio' || track.readyState !== 'live' || codexBusSources.has(track)) return;
    const source = context.createMediaStreamSource(new MediaStream([track]));
    source.connect(codexInBus);
    codexBusSources.set(track, source);
    track.addEventListener('ended', () => {
      const entry = codexBusSources.get(track);
      if (entry) { try { entry.disconnect(); } catch {} codexBusSources.delete(track); }
    }, {once: true});
  };
  const resetCodexTurnState = (acceptTurn = false) => {
    if (!codexBridge) return;
    codexBridge.dcAcceptingTurn = Boolean(acceptTurn);
    codexBridge.activeResponseId = null;
    codexBridge.dcHeardParts = [];
    codexBridge.dcHeardDelta = '';
    codexBridge.dcReplyParts = [];
    codexBridge.dcReplyDelta = '';
    codexBridge.dcReplyDone = false;
    codexBridge.dcEvents = [];
  };
  const cancelAndClearCodex = () => {
    if (!codexBridge) return;
    const b = codexBridge;
    try { b.inGain.gain.value = 0; } catch {}
    // Realtime v3 turn cleanup is local. Interrupted sessions are stopped by the app server.
    if (b.activeResponseId) {
      b.cancelledResponseIds?.add(b.activeResponseId);
    }
    b.serverResponseInFlight = false;
    resetCodexTurnState(false);
  };
  const destroyCodexBridge = () => {
    abortCodexSpeech?.();
    abortCodexSpeech = null;
    restoreTeamsSenders().catch(() => {});
    if (!codexBridge) return;
    const b = codexBridge;
    codexBridge = null;
    try { b.dc?.close(); } catch {}
    try { b.pc?.close(); } catch {}
    if (b.replyAudio) {
      try { b.replyAudio.pause(); } catch {}
      b.replyAudio.srcObject = null;
    }
    for (const node of [b.outSource, b.outMeter, b.outDelay, b.outGain, b.inPreRoll, b.inGain, b.inMeter]) {
      if (node) { try { node.disconnect(); } catch {} }
    }
  };
  const measureMicRms = () => {
    if (!micMeter || !micMeterBuf) return 0;
    micMeter.getFloatTimeDomainData(micMeterBuf);
    let sum = 0;
    for (let i = 0; i < micMeterBuf.length; i++) sum += micMeterBuf[i] * micMeterBuf[i];
    return Math.sqrt(sum / micMeterBuf.length);
  };
  const start = async () => {
    if (!context) {
      context = new OrigAudioContext();
      mic = context.createMediaStreamDestination();
      try {
        mic.channelCount = 1;
        mic.channelCountMode = 'explicit';
      } catch {}
      micBus = context.createGain();
      micBus.gain.value = 1;
      micMeter = context.createAnalyser();
      micMeter.fftSize = 1024;
      micMeterBuf = new Float32Array(micMeter.fftSize);
      micBus.connect(mic);
      micBus.connect(micMeter);
      const keepSrc = context.createConstantSource();
      keepSrc.offset.value = 0;
      const keepGain = context.createGain();
      keepGain.gain.value = 0;
      keepSrc.connect(keepGain);
      keepGain.connect(micBus);
      keepSrc.start();
      mix = context.createMediaStreamDestination();
    }
    await Promise.race([context.resume().catch(() => {}), new Promise(r => setTimeout(r, 250))]);
  };
  const microphone = async () => {
    await start();
    micCalls++;
    const track = decorateVirtualTrack(mic.stream.getAudioTracks()[0].clone());
    issuedTracks.push(track);
    if (issuedTracks.length > 10) issuedTracks.shift();
    return new MediaStream([track]);
  };
  window.RTCPeerConnection = new Proxy(Peer, {
    construct(Target, args, NewTarget) {
      diagLog.push(`new PC(${JSON.stringify({enc: args[0]?.encodedInsertableStreams, bundle: args[0]?.bundlePolicy})})`);
      const peer = Reflect.construct(Target, args, NewTarget);
      peers.add(peer);
      peer.addEventListener('track', ({track}) => {
        if (track.kind !== 'audio') return;
        const audio = new Audio();
        audio.muted = false;
        audio.srcObject = new MediaStream([track]);
        remote.set(track, {peer, audio});
        attachTrackToCodexBus(track);
        notesAttach(track);
        for (const attachFn of activeRecordTrackAttach) {
          try { attachFn(track); } catch {}
        }
        audio.play().catch(() => {});
        track.addEventListener('ended', () => {
          audio.srcObject = null;
          remote.delete(track);
          notesDetach(track);
        }, {once: true});
      });
      peer.addEventListener('connectionstatechange', () => {
        if (peer.connectionState !== 'closed') return;
        peers.delete(peer);
        for (const [track, entry] of remote) if (entry.peer === peer) {
          entry.audio.srcObject = null;
          remote.delete(track);
          notesDetach(track);
          const source = codexBusSources.get(track);
          if (source) { try { source.disconnect(); } catch {} codexBusSources.delete(track); }
        }
      });
      return peer;
    },
  });
  const devices = navigator.mediaDevices;
  if (devices) {
    const enumerate = devices.enumerateDevices.bind(devices);
    const getMedia = devices.getUserMedia.bind(devices);
    devices.enumerateDevices = async () => {
      if (isTeams) {
        const defIn = {kind: 'audioinput', deviceId: 'default', groupId: 'nail', label: 'Default - Nail'};
        const nailIn = {kind: 'audioinput', deviceId: 'nail-virtual-mic', groupId: 'nail', label: 'Nail'};
        const defOut = {kind: 'audiooutput', deviceId: 'default', groupId: 'nail', label: 'Default'};
        return [
          {...defIn, toJSON: () => defIn},
          {...nailIn, toJSON: () => nailIn},
          {...defOut, toJSON: () => defOut},
        ];
      }
      const virtual = {kind: 'audioinput', deviceId: 'default', groupId: 'nail', label: 'Nail'};
      const others = (await enumerate()).filter(d => d.kind !== 'audioinput' && (!avatarAllowed || d.kind !== 'videoinput'));
      if (avatarAllowed) {
        const video = {kind: 'videoinput', deviceId: avatarDeviceId, groupId: 'nail', label: 'Nail'};
        others.push({...video, toJSON: () => video});
      }
      if (!others.some(d => d.kind === 'audiooutput')) {
        const out = {kind: 'audiooutput', deviceId: 'default', groupId: 'nail', label: 'Default'};
        others.push({...out, toJSON: () => out});
      }
      return [{...virtual, toJSON: () => virtual}, ...others];
    };
    devices.getUserMedia = constraints => {
      if (avatarAllowed && constraints?.video) {
        if (!avatarPrepared && constraints.audio) return microphone();
        const device = constraints.video?.deviceId;
        const requested = typeof device === 'string' ? device : device?.exact;
        const matches = !requested || [requested].flat().some(id => id === avatarDeviceId || id === 'default');
        if (!matches || !avatar?.ready) {
          return Promise.reject(new DOMException('Nail avatar unavailable', 'NotFoundError'));
        }
        const source = avatar;
        return (async () => {
          const audio = constraints.audio ? await microphone() : null;
          const video = avatar === source && source.track.readyState === 'live' ? source.track.clone() : null;
          if (!video) {
            audio?.getTracks().forEach(track => track.stop());
            throw new DOMException('Nail avatar unavailable', 'NotFoundError');
          }
          return new MediaStream([...(audio?.getAudioTracks() ?? []), video]);
        })();
      }
      if (isTeams) {
        if (constraints?.video) {
          pushGum(constraints, 'NotFoundError(video)');
          return Promise.reject(new DOMException('Requested device not found', 'NotFoundError'));
        }
        if (constraints?.audio) {
          pushGum(constraints, 'ok(audio)');
          return microphone();
        }
        pushGum(constraints, 'delegate');
        return getMedia(constraints);
      }
      if (constraints?.audio) {
        pushGum(constraints, 'ok(audio)');
        return microphone();
      }
      return getMedia(constraints);
    };
  }
  Object.defineProperty(window, '__nailMedia', {value: Object.freeze({
    prepareAvatarCamera,
    drawAvatarFrame,
    stopAvatarCamera,
    avatarCameraHasTrack(revision) {
      return avatar?.revision === revision && [...avatar.tracks].some(track => track !== avatar.track && track.readyState === 'live');
    },
    avatarAudioSample() {
      const sending = Boolean(activePlayer || (codexBridge?.outGain?.gain?.value ?? 0) > 0);
      return {rms: sending ? measureMicRms() : 0, sending};
    },
    microphone,
    notesStart,
    notesTake,
    notesStop,
    sending: () => [...peers].some(peer =>
      (peer.connectionState === 'connected' || peer.iceConnectionState === 'connected' || peer.iceConnectionState === 'completed') &&
      peer.getSenders().some(({track}) => track?.kind === 'audio' && track.enabled && track.readyState === 'live' &&
        (virtualTracks.has(track) || micCalls > 0))),
    micDiag: () => ({
      micCalls,
      ctxState: context?.state ?? 'none',
      remoteCount: remote.size,
      gums: gumLog.slice(-15),
      peers: [...peers].map(p => ({
        cs: p.connectionState,
        ice: p.iceConnectionState,
        sig: p.signalingState,
        senders: p.getSenders().filter(s => s.track?.kind === 'audio' || !s.track).map(s => ({
          kind: s.track?.kind ?? null,
          enabled: s.track?.enabled ?? null,
          muted: s.track?.muted ?? null,
          state: s.track?.readyState ?? null,
          virtual: s.track ? virtualTracks.has(s.track) : false,
          label: s.track?.label ?? null,
        })),
        transceivers: p.getTransceivers().map(t => ({
          mid: t.mid,
          kind: t.receiver?.track?.kind ?? null,
          dir: t.direction,
          cur: t.currentDirection,
        })),
      })),
    }),
    async micOutDiag() {
      const baseTrack = mic?.stream?.getAudioTracks?.()[0] ?? null;
      const outTrack = codexBridge?.outTrack ?? null;
      const ra = codexBridge?.replyAudio ?? null;
      const peerDiags = [];
      for (const p of peers) {
        const senders = p.getSenders().filter(s => s.track?.kind === 'audio' || !s.track).map(s => ({
          kind: s.track?.kind ?? null,
          enabled: s.track?.enabled ?? null,
          muted: s.track?.muted ?? null,
          state: s.track?.readyState ?? null,
          virtual: s.track ? virtualTracks.has(s.track) : false,
          label: s.track?.label ?? null,
        }));
        const outbound = [];
        const mediaSource = [];
        try {
          for (const r of (await p.getStats()).values()) {
            if (r.type === 'outbound-rtp' && r.kind === 'audio') {
              outbound.push({
                ssrc: r.ssrc,
                mid: r.mid ?? null,
                packetsSent: r.packetsSent ?? 0,
                bytesSent: r.bytesSent ?? 0,
                active: r.active ?? null,
              });
            } else if (r.type === 'media-source' && r.kind === 'audio') {
              mediaSource.push({
                audioLevel: r.audioLevel ?? null,
                totalAudioEnergy: r.totalAudioEnergy ?? 0,
                totalSamplesDuration: r.totalSamplesDuration ?? 0,
              });
            }
          }
        } catch {}
        peerDiags.push({
          cs: p.connectionState,
          ice: p.iceConnectionState,
          sig: p.signalingState,
          senders,
          outbound,
          mediaSource,
        });
      }
      return {
        ctxState: context?.state ?? 'none',
        micCalls,
        micRms: Math.round(measureMicRms() * 10000) / 10000,
        outGain: codexBridge?.outGain?.gain?.value ?? null,
        outTrack: outTrack ? {enabled: outTrack.enabled, muted: outTrack.muted, state: outTrack.readyState} : null,
        replyAudio: ra ? {paused: ra.paused, muted: ra.muted, ready: ra.readyState, err: ra.error?.message ?? null} : null,
        micBaseTrack: baseTrack ? {enabled: baseTrack.enabled, muted: baseTrack.muted, state: baseTrack.readyState} : null,
        pageContexts: [...pageContexts].map(c => ({state: c.state, sr: c.sampleRate, t: Math.round((c.currentTime || 0) * 10) / 10})),
        pageVirtualSources,
        issuedTracks: issuedTracks.slice(-6).map(t => ({id: t.id?.slice(0, 8) ?? null, enabled: t.enabled, muted: t.muted, state: t.readyState})),
        replacedActive: replacedSenders.size,
        lastInjectedStats,
        peers: peerDiags,
      };
    },
    recordingPreview() {
      return readRecordingPreview?.() ?? '';
    },
    async record(milliseconds, autoListen = false, idleWaitMs = 12000, previews = false) {
      await start();
      if (context.state === 'suspended') await context.resume().catch(() => {});
      if (milliseconds <= 0 || milliseconds > 12000) throw new Error('Invalid capture duration');
      const sources = [];
      const attachedTracks = new Set();
      let onTrackAttach = null;
      const rxStats = async () => {
        let packets = 0, energy = 0;
        for (const peer of peers) {
          try {
            for (const r of (await peer.getStats()).values()) {
              if (r.type === 'inbound-rtp' && r.kind === 'audio') {
                packets += r.packetsReceived ?? 0;
                energy += r.totalAudioEnergy ?? 0;
              }
            }
          } catch {}
        }
        return {packets, energy};
      };
      try {
        const preRoll = context.createDelay(1.0);
        preRoll.delayTime.value = 0.35;
        preRoll.connect(mix);
        const meter = context.createAnalyser();
        meter.fftSize = 1024;
        const meterBuf = new Float32Array(meter.fftSize);
        let notifyTrackAttached = null;
        const attachRemoteTrack = track => {
          if (!track || track.kind !== 'audio' || track.readyState !== 'live' || attachedTracks.has(track)) return;
          try {
            const source = context.createMediaStreamSource(new MediaStream([track]));
            source.connect(preRoll);
            source.connect(meter);
            sources.push(source);
            attachedTracks.add(track);
            notifyTrackAttached?.();
          } catch {}
        };
        onTrackAttach = attachRemoteTrack;
        activeRecordTrackAttach.add(onTrackAttach);
        for (const track of remote.keys()) attachRemoteTrack(track);
        sources.push(preRoll);
        if (!attachedTracks.size && !(await waitForLiveTrack(attachedTracks, attachRemoteTrack, idleWaitMs, fn => { notifyTrackAttached = fn; }))) {
          window.__nailDiagnostics = {tracks: remote.size, live: attachedTracks.size,
            muted: [...remote.keys()].filter(t => t.muted).length};
          return '';
        }
        window.__nailDiagnostics = {tracks: remote.size, live: attachedTracks.size,
          muted: [...remote.keys()].filter(t => t.muted).length};
        const before = await rxStats();
        const maxIdleTicks = Math.max(1, Math.round(idleWaitMs / 100));
        const recorder = new MediaRecorder(mix.stream, {mimeType: 'audio/webm;codecs=opus', audioBitsPerSecond: 64000});
        const startRecorder = () => previews ? recorder.start(400) : recorder.start();
        let wasAutoListen = autoListen;
        const blob = await new Promise((resolve, reject) => {
          const chunks = [];
          let ticks = 0, speechTicks = 0, voicedTicks = 0, silentTicks = 0, onsetStreak = 0;
          let noiseFloor = 0.003;
          let started = !autoListen, aborted = false;
          let poll = null;
          const finish = val => {
            if (poll) { clearInterval(poll); poll = null; }
            if (previews) readRecordingPreview = null;
            window.__nailUpgradeRecord = null;
            window.__nailAbortRecord = null;
            resolve(val);
          };
          if (previews) {
            let readChunks = 0;
            readRecordingPreview = async () => {
              if (aborted || voicedTicks < 3 || chunks.length === readChunks || recorder.state !== 'recording') return '';
              readChunks = chunks.length;
              return audioBase64(await new Blob(chunks).arrayBuffer());
            };
          }
          window.__nailUpgradeRecord = () => {
            autoListen = false;
            wasAutoListen = false;
            ticks = 0;
            speechTicks = 0;
            silentTicks = 0;
            if (!started && recorder.state === 'inactive') { started = true; startRecorder(); }
            return true;
          };
          window.__nailAbortRecord = () => {
            aborted = true;
            if (recorder.state === 'recording') {
              try { recorder.stop(); } catch { finish(null); }
            } else {
              finish(null);
            }
          };
          poll = setInterval(() => {
            ticks++;
            if (voicedTicks > 0) speechTicks++;
            window.__nailDiagnostics = {tracks: remote.size, live: attachedTracks.size,
              muted: [...remote.keys()].filter(t => t.muted).length};
            if (started && recorder.state === 'recording' && voicedTicks > 0 && speechTicks >= Math.round(milliseconds / 100)) {
              recorder.stop();
              return;
            }
            meter.getFloatTimeDomainData(meterBuf);
            let sum = 0;
            for (let i = 0; i < meterBuf.length; i++) sum += meterBuf[i] * meterBuf[i];
            const rms = Math.sqrt(sum / meterBuf.length);
            const inEchoGuard = autoListen && (Date.now() - lastPlayEndedAt < 450);
            const startThreshold = autoListen ? Math.max(0.0055, noiseFloor * 1.8) : 0.0035;
            const sustainThreshold = autoListen ? Math.max(0.004, noiseFloor * 1.45) : 0.003;
            if (!started) {
              if (!inEchoGuard && rms >= startThreshold) {
                onsetStreak++;
                if (onsetStreak >= 2 || rms >= 0.015) {
                  started = true;
                  ticks = 0;
                  speechTicks = 0;
                  voicedTicks = onsetStreak;
                  silentTicks = 0;
                  startRecorder();
                }
              } else {
                onsetStreak = 0;
                noiseFloor = Math.min(0.004, Math.max(0.002, noiseFloor * 0.9 + rms * 0.1));
                if (ticks >= maxIdleTicks) {
                  finish(null);
                }
              }
            } else if (rms >= sustainThreshold) {
              if (voicedTicks === 0) speechTicks = 0;
              voicedTicks++;
              silentTicks = 0;
            } else if (recorder.state === 'recording') {
              silentTicks++;
              if (autoListen && voicedTicks < 3 && silentTicks >= 4) {
                aborted = true;
                recorder.stop();
              } else if (voicedTicks >= (autoListen ? 3 : 2) && silentTicks >= 7) {
                recorder.stop();
              } else if (!autoListen && voicedTicks === 0 && ticks >= maxIdleTicks) {
                recorder.stop();
              }
            }
          }, 100);
          recorder.ondataavailable = e => { if (e.data.size !== 0) chunks.push(e.data); };
          recorder.onstop = () => finish(aborted ? null : new Blob(chunks));
          recorder.onerror = () => {
            if (poll) { clearInterval(poll); poll = null; }
            if (previews) readRecordingPreview = null;
            window.__nailUpgradeRecord = null;
            window.__nailAbortRecord = null;
            reject(new Error('Recorder failed'));
          };
          if (started) startRecorder();
        });
        if (!blob) return '';
        const data = await blob.arrayBuffer();
        const decoded = await context.decodeAudioData(data.slice(0));
        const width = Math.round(decoded.sampleRate * 0.02);
        const frameThreshold = wasAutoListen ? 0.0045 : 0.003;
        let voicedFrames = 0, peak = 0;
        for (let offset = 0; offset + width <= decoded.length; offset += width) {
          let energy = 0;
          for (let channel = 0; channel < decoded.numberOfChannels; channel++) {
            const samples = decoded.getChannelData(channel);
            for (let i = offset; i < offset + width; i++) {
              energy += samples[i] * samples[i];
              peak = Math.max(peak, Math.abs(samples[i]));
            }
          }
          if (energy >= width * decoded.numberOfChannels * frameThreshold ** 2) voicedFrames++;
        }
        const minVoicedFrames = wasAutoListen ? 7 : 3;
        if (voicedFrames < minVoicedFrames) {
          const after = await rxStats();
          Object.assign(window.__nailDiagnostics, {peak: Math.round(20 * Math.log10(peak || 1e-9)),
            voicedFrames, seconds: Math.round(decoded.duration * 10) / 10,
            rxPackets: after.packets - before.packets,
            rxEnergy: Math.round((after.energy - before.energy) * 1000) / 1000});
          const inbound = [];
          for (const peer of peers) {
            try {
              const receivers = peer.getReceivers().filter(r => r.track?.kind === 'audio').map(r => ({
                id: r.track.id, muted: r.track.muted, enabled: r.track.enabled, state: r.track.readyState,
                transform: Boolean(r.transform), ssrcs: r.getSynchronizationSources?.().length ?? -1,
              }));
              const transceivers = peer.getTransceivers().filter(t => t.receiver?.track?.kind === 'audio').map(t => ({
                mid: t.mid, dir: t.direction, cur: t.currentDirection, stopped: t.stopped,
              }));
              const codecs = new Map();
              const stats = [...(await peer.getStats()).values()];
              for (const s of stats) if (s.type === 'codec') codecs.set(s.id, s.mimeType);
              for (const r of stats) {
                if (r.type === 'inbound-rtp' && r.kind === 'audio') inbound.push({
                  ssrc: r.ssrc, mid: r.mid, pkts: r.packetsReceived, lost: r.packetsLost, discarded: r.packetsDiscarded,
                  bytes: r.bytesReceived, samples: r.totalSamplesReceived, concealed: r.concealedSamples,
                  level: r.audioLevel, energy: r.totalAudioEnergy,
                  decoder: r.decoderImplementation, codec: codecs.get(r.codecId), emitted: r.jitterBufferEmittedCount});
              }
              const audioStates = [...remote.values()].filter(e => e.peer === peer).map(e => ({
                paused: e.audio.paused, muted: e.audio.muted, ready: e.audio.readyState, err: e.audio.error?.message,
              }));
              const playout = stats.filter(s => s.type === 'media-playout').map(s => ({
                dur: s.totalSamplesDuration, synth: s.synthesizedSamplesDuration,
              }));
              inbound.push({peerState: peer.connectionState, ua: navigator.userAgent, ctxState: context?.state, ctxTime: context?.currentTime,
                receivers, transceivers, audioStates, playout, encStats, diagLog: diagLog.slice(-20)});
            } catch {}
          }
          window.__nailInbound = inbound;
          return '';
        }
        Object.assign(window.__nailDiagnostics, {peak: Math.round(20 * Math.log10(peak || 1e-9)),
          voicedFrames, seconds: Math.round(decoded.duration * 10) / 10});
        return audioBase64(data);
      } finally {
        if (onTrackAttach) activeRecordTrackAttach.delete(onTrackAttach);
        for (const source of sources) source.disconnect();
      }
    },
    async codexRecordWakePcm(maxSpeakMs = 8000, idleWaitMs = 12000, silenceMs = 450) {
      await start();
      if (context.state === 'suspended') await context.resume().catch(() => {});
      if (maxSpeakMs <= 0) throw new Error('Invalid capture duration');
      if (typeof context.createScriptProcessor !== 'function') {
        return window.__nailMedia.record(Math.min(maxSpeakMs, 12000), true, idleWaitMs, false);
      }
      const sources = [];
      const attachedTracks = new Set();
      let onTrackAttach = null;
      let processorNode = null;
      let result = null;
      try {
        const bus = context.createGain();
        bus.gain.value = 1;
        processorNode = context.createScriptProcessor(2048, 1, 1);
        const sink = context.createGain();
        sink.gain.value = 0;
        bus.connect(processorNode);
        processorNode.connect(sink);
        if (mix) {
          try { sink.connect(mix); } catch {}
        }
        if (context.destination) {
          try { sink.connect(context.destination); } catch {}
        }
        sources.push(bus, processorNode, sink);
        let notifyTrackAttached = null;
        const attachRemoteTrack = track => {
          if (!track || track.kind !== 'audio' || track.readyState !== 'live' || attachedTracks.has(track)) return;
          try {
            const source = context.createMediaStreamSource(new MediaStream([track]));
            source.connect(bus);
            sources.push(source);
            attachedTracks.add(track);
            notifyTrackAttached?.();
          } catch {}
        };
        onTrackAttach = attachRemoteTrack;
        activeRecordTrackAttach.add(onTrackAttach);
        for (const track of remote.keys()) attachRemoteTrack(track);
        if (!attachedTracks.size && !(await waitForLiveTrack(attachedTracks, attachRemoteTrack, idleWaitMs, fn => { notifyTrackAttached = fn; }))) {
          window.__nailDiagnostics = {
            tracks: remote.size,
            live: attachedTracks.size,
            muted: [...remote.keys()].filter(t => t.muted).length,
          };
          return null;
        }
        window.__nailDiagnostics = {
          tracks: remote.size,
          live: attachedTracks.size,
          muted: [...remote.keys()].filter(t => t.muted).length,
        };

        const srcRate = context.sampleRate || 48000;
        const targetRate = 16000;
        const ratio = srcRate / targetRate;
        const bufferSize = processorNode.bufferSize || 2048;
        const frameMs = Math.max(10, (bufferSize / srcRate) * 1000);
        const maxIdleTicks = Math.max(1, Math.ceil(idleWaitMs / frameMs));
        const maxSpeechTicks = Math.max(1, Math.ceil(maxSpeakMs / frameMs));
        const requiredSilentTicks = Math.max(2, Math.ceil(silenceMs / frameMs));
        const earlyAbortSilentTicks = Math.max(5, Math.ceil(360 / frameMs));
        const maxPreRollSamples = Math.round(targetRate * 0.2);
        const maxPcmBytes = 1024 * 1024;
        const maxPcmSamples = maxPcmBytes >> 1;

        let leftover = new Float32Array(0);
        const downsampleToInt16 = input => {
          if (!input || !input.length) return new Int16Array(0);
          if (srcRate === targetRate) {
            const out = new Int16Array(input.length);
            for (let i = 0; i < input.length; i++) {
              const clamped = Math.max(-1, Math.min(1, input[i]));
              out[i] = clamped < 0 ? Math.round(clamped * 32768) : Math.round(clamped * 32767);
            }
            return out;
          }
          let combined = input;
          if (leftover.length) {
            combined = new Float32Array(leftover.length + input.length);
            combined.set(leftover, 0);
            combined.set(input, leftover.length);
          }
          const outLen = Math.floor(combined.length / ratio);
          if (outLen <= 0) {
            leftover = new Float32Array(combined);
            return new Int16Array(0);
          }
          const out = new Int16Array(outLen);
          for (let i = 0; i < outLen; i++) {
            const startIdx = Math.floor(i * ratio);
            const endIdx = Math.max(startIdx + 1, Math.floor((i + 1) * ratio));
            let sum = 0;
            for (let j = startIdx; j < endIdx && j < combined.length; j++) sum += combined[j];
            const avg = sum / (endIdx - startIdx);
            const clamped = Math.max(-1, Math.min(1, avg));
            out[i] = clamped < 0 ? Math.round(clamped * 32768) : Math.round(clamped * 32767);
          }
          const consumed = Math.floor(outLen * ratio);
          leftover = combined.slice(consumed);
          return out;
        };

        result = await new Promise(resolve => {
          const preRollChunks = [];
          let preRollSamples = 0;
          const recordedChunks = [];
          let recordedSamples = 0;
          const waitStartedAt = Date.now();
          let voiceStartedAt = 0;
          let lastVoicedAt = 0;
          let ticks = 0;
          let speechTicks = 0;
          let voicedTicks = 0;
          let silentTicks = 0;
          let onsetStreak = 0;
          let noiseFloor = 0.003;
          let started = false;
          let aborted = false;
          let settled = false;
          let watchdog = null;

          const finish = keep => {
            if (settled) return;
            settled = true;
            if (watchdog) { clearInterval(watchdog); watchdog = null; }
            if (processorNode) processorNode.onaudioprocess = null;
            if (window.__nailAbortRecord === onAbort) window.__nailAbortRecord = null;
            if (!keep || aborted || !started || voicedTicks < 3 || recordedSamples <= 0) {
              if (fallbackToRecord && !aborted) {
                resolve({__fallbackToRecord: true});
              } else {
                resolve(null);
              }
              return;
            }
            const endedAt = Date.now();
            const speechEndedAtMs = lastVoicedAt || endedAt;
            const silenceWaitMs = Math.max(0, endedAt - speechEndedAtMs);
            const totalSamples = Math.min(recordedSamples, maxPcmSamples);
            const bytes = new Uint8Array(totalSamples * 2);
            let byteOffset = 0;
            for (const chunk of recordedChunks) {
              for (let i = 0; i < chunk.length && byteOffset < bytes.length; i++) {
                const sample = chunk[i];
                bytes[byteOffset++] = sample & 0xff;
                bytes[byteOffset++] = (sample >> 8) & 0xff;
              }
              if (byteOffset >= bytes.length) break;
            }
            resolve({
              pcmBase64: audioBase64(bytes),
              sampleRate: targetRate,
              silenceWaitMs,
              speechEndedAtMs,
              durationMs: Math.round((totalSamples / targetRate) * 1000),
            });
          };

          const onAbort = () => {
            aborted = true;
            finish(false);
          };
          window.__nailAbortRecord = onAbort;

          const appendRecordedChunk = pcmChunk => {
            if (!pcmChunk || !pcmChunk.length) return false;
            const remaining = maxPcmSamples - recordedSamples;
            if (remaining <= 0) return true;
            const slice = pcmChunk.length > remaining ? pcmChunk.subarray(0, remaining) : pcmChunk;
            recordedChunks.push(slice);
            recordedSamples += slice.length;
            return recordedSamples >= maxPcmSamples;
          };

          let fallbackToRecord = false;
          watchdog = setInterval(() => {
            const now = Date.now();
            if (ticks === 0 && now - waitStartedAt >= 650) {
              fallbackToRecord = true;
              finish(false);
              return;
            }
            if (!started && now - waitStartedAt >= idleWaitMs) {
              finish(false);
            } else if (started && voiceStartedAt && now - voiceStartedAt >= maxSpeakMs) {
              finish(true);
            }
          }, 100);

          processorNode.onaudioprocess = ev => {
            if (settled) return;
            const input = ev?.inputBuffer?.getChannelData?.(0);
            if (!input || !input.length) return;
            ticks++;
            if (voicedTicks > 0) speechTicks++;
            window.__nailDiagnostics = {
              tracks: remote.size,
              live: attachedTracks.size,
              muted: [...remote.keys()].filter(t => t.muted).length,
            };
            let sum = 0;
            for (let i = 0; i < input.length; i++) sum += input[i] * input[i];
            const rms = Math.sqrt(sum / input.length);
            const now = Date.now();
            const inEchoGuard = now - lastPlayEndedAt < 450;
            const startThreshold = Math.max(0.0055, noiseFloor * 1.8);
            const sustainThreshold = Math.max(0.004, noiseFloor * 1.45);
            const pcmChunk = downsampleToInt16(input);

            if (!started) {
              if (!inEchoGuard && rms >= startThreshold) {
                onsetStreak++;
                if (onsetStreak >= 2 || rms >= 0.015) {
                  started = true;
                  voiceStartedAt = now;
                  lastVoicedAt = now;
                  ticks = 0;
                  speechTicks = 1;
                  voicedTicks = onsetStreak;
                  silentTicks = 0;
                  for (const prior of preRollChunks) {
                    if (appendRecordedChunk(prior)) { finish(true); return; }
                  }
                  preRollChunks.length = 0;
                  preRollSamples = 0;
                  if (appendRecordedChunk(pcmChunk)) { finish(true); return; }
                  return;
                }
              } else {
                onsetStreak = 0;
                noiseFloor = Math.min(0.004, Math.max(0.002, noiseFloor * 0.9 + rms * 0.1));
              }
              if (pcmChunk.length) {
                preRollChunks.push(pcmChunk);
                preRollSamples += pcmChunk.length;
                while (preRollSamples > maxPreRollSamples && preRollChunks.length > 0) {
                  const extra = preRollSamples - maxPreRollSamples;
                  if (preRollChunks[0].length <= extra) {
                    preRollSamples -= preRollChunks[0].length;
                    preRollChunks.shift();
                  } else {
                    preRollChunks[0] = preRollChunks[0].subarray(extra);
                    preRollSamples -= extra;
                  }
                }
              }
              if (ticks >= maxIdleTicks || now - waitStartedAt >= idleWaitMs) {
                finish(false);
              }
              return;
            }

            if (appendRecordedChunk(pcmChunk)) {
              if (rms >= sustainThreshold) {
                voicedTicks++;
                lastVoicedAt = now;
              }
              finish(true);
              return;
            }

            if (rms >= sustainThreshold) {
              voicedTicks++;
              silentTicks = 0;
              lastVoicedAt = now;
            } else {
              silentTicks++;
              if (voicedTicks < 3 && silentTicks >= earlyAbortSilentTicks) {
                aborted = true;
                finish(false);
                return;
              }
              if (voicedTicks >= 3 && silentTicks >= requiredSilentTicks) {
                finish(true);
                return;
              }
            }

            if (speechTicks >= maxSpeechTicks || (voiceStartedAt && now - voiceStartedAt >= maxSpeakMs)) {
              finish(true);
            }
          };
        });
      } finally {
        if (onTrackAttach) activeRecordTrackAttach.delete(onTrackAttach);
        if (processorNode) processorNode.onaudioprocess = null;
        for (const source of sources) {
          try { source.disconnect(); } catch {}
        }
      }
      if (result?.__fallbackToRecord) {
        return window.__nailMedia.record(Math.min(maxSpeakMs, 12000), true, idleWaitMs, false);
      }
      return result;
    },
    async play(encoded) {
      await start();
      if (context.state === 'suspended') await context.resume().catch(() => {});
      resumePageContexts();
      if (activePlayDone) activePlayDone();
      await attachTeamsVirtualSenders();
      try {
        const wav = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
        const buffer = await context.decodeAudioData(wav.buffer);
        const player = context.createBufferSource();
        player.buffer = buffer;
        player.connect(micBus);
        await new Promise(resolve => {
          let settled = false;
          const done = () => {
            if (settled) return;
            settled = true;
            lastPlayEndedAt = Date.now();
            if (activePlayer === player) activePlayer = null;
            if (activePlayDone === done) activePlayDone = null;
            try { player.disconnect(); } catch {}
            resolve();
          };
          activePlayer = player;
          activePlayDone = done;
          player.onended = done;
          player.start();
        });
      } finally {
        await restoreTeamsSenders();
      }
    },
    stopPlay() {
      const player = activePlayer;
      const done = activePlayDone;
      lastPlayEndedAt = Date.now();
      if (player) { try { player.stop(); } catch {} }
      if (done) done();
      restoreTeamsSenders().catch(() => {});
    },
    async codexConnect() {
      await start();
      destroyCodexBridge();
      if (!codexInBus) codexInBus = context.createGain();
      for (const track of remote.keys()) attachTrackToCodexBus(track);

      const inPreRoll = context.createDelay(1.0);
      inPreRoll.delayTime.value = 0.14;
      const inGain = context.createGain();
      inGain.gain.value = 0;
      const inDest = context.createMediaStreamDestination();
      const inMeter = context.createAnalyser();
      inMeter.fftSize = 1024;
      codexInBus.connect(inPreRoll);
      inPreRoll.connect(inGain);
      inGain.connect(inDest);
      codexInBus.connect(inMeter);

      const outMeter = context.createAnalyser();
      outMeter.fftSize = 1024;
      const outDelay = context.createDelay(1.0);
      outDelay.delayTime.value = 0.015;
      const outGain = context.createGain();
      outGain.gain.value = 0;
      outDelay.connect(outGain);
      outGain.connect(micBus);

      const pc = new Peer({iceServers: [{urls: 'stun:stun.cloudflare.com:3478'}, {urls: 'stun:stun.l.google.com:19302'}]});
      pc.addTrack(inDest.stream.getAudioTracks()[0]);
      const dc = pc.createDataChannel('oai-events');
      const bridge = {
        pc, dc, inPreRoll, inGain, inDest, inMeter, inBuf: new Float32Array(inMeter.fftSize),
        outMeter, outBuf: new Float32Array(outMeter.fftSize), outDelay, outGain,
        outSource: null, outTrack: null, replyAudio: null,
        dcAcceptingTurn: false, serverResponseInFlight: false, activeResponseId: null, cancelledResponseIds: new Set(),
        dcHeardParts: [], dcHeardDelta: '', dcReplyParts: [], dcReplyDelta: '',
        dcReplyDone: false, dcEvents: [], wiredChannels: null,
      };
      codexBridge = bridge;
      wireCodexDataChannel(bridge, dc);
      pc.ondatachannel = ev => wireCodexDataChannel(bridge, ev.channel);

      pc.ontrack = ({track}) => {
        if (track.kind !== 'audio' || codexBridge !== bridge) return;
        if (bridge.outSource && bridge.outTrack?.readyState === 'live') return;
        if (bridge.replyAudio) {
          try { bridge.replyAudio.pause(); } catch {}
          bridge.replyAudio.srcObject = null;
        }
        if (bridge.outSource) {
          try { bridge.outSource.disconnect(); } catch {}
        }
        const stream = new MediaStream([track]);
        const replyAudio = new Audio();
        replyAudio.muted = false;
        replyAudio.srcObject = stream;
        replyAudio.play().catch(() => {
          replyAudio.muted = true;
          replyAudio.play().catch(() => {});
        });
        const outSource = context.createMediaStreamSource(stream);
        outSource.connect(outMeter);
        outSource.connect(outDelay);
        bridge.outTrack = track;
        bridge.replyAudio = replyAudio;
        bridge.outSource = outSource;
      };

      await pc.setLocalDescription(await pc.createOffer());
      await new Promise(resolve => {
        if (pc.iceGatheringState === 'complete') return resolve();
        let done = false;
        let hasHostCandidate = false;
        let srflxTimer = null;
        let stunErrorTimer = null;
        const finish = () => {
          if (done) return;
          done = true;
          clearTimeout(hardTimer);
          if (srflxTimer) clearTimeout(srflxTimer);
          if (stunErrorTimer) clearTimeout(stunErrorTimer);
          pc.onicegatheringstatechange = null;
          pc.onicecandidate = null;
          pc.onicecandidateerror = null;
          resolve();
        };
        const hardTimer = setTimeout(finish, 1200);
        pc.onicegatheringstatechange = () => { if (pc.iceGatheringState === 'complete') finish(); };
        pc.onicecandidate = ev => {
          if (!ev.candidate) { finish(); return; }
          const cand = ev.candidate.candidate || '';
          if (ev.candidate.type === 'host' || /\btyp host\b/.test(cand)) {
            hasHostCandidate = true;
          }
          if (!srflxTimer && (ev.candidate.type === 'srflx' || ev.candidate.type === 'relay' || /\btyp (srflx|relay)\b/.test(cand))) {
            srflxTimer = setTimeout(finish, 150);
          }
        };
        pc.onicecandidateerror = () => {
          if (!srflxTimer && !stunErrorTimer && hasHostCandidate) {
            stunErrorTimer = setTimeout(finish, 250);
          }
        };
      });
      return pc.localDescription.sdp;
    },
    async codexAnswer(sdp) {
      if (!codexBridge?.pc) throw new Error('voice-codex-connection');
      await codexBridge.pc.setRemoteDescription({type: 'answer', sdp});
    },
    async codexWaitUserSpeech(maxWaitMs = 8000, maxSpeakMs = 12000, silenceMs = 350) {
      if (!codexBridge) throw new Error('voice-codex-connection');
      for (const track of remote.keys()) attachTrackToCodexBus(track);
      const bridge = codexBridge;
      resetCodexTurnState(true);
      bridge.inGain.gain.value = 0;
      const requiredSilentTicks = Math.max(2, Math.ceil(silenceMs / 40));
      return await new Promise(resolve => {
        const startedAt = Date.now();
        let voiceStartedAt = 0;
        let lastVoicedAt = 0;
        let voicedTicks = 0;
        let silentTicks = 0;
        let onsetStreak = 0;
        let noiseFloor = 0.003;
        let peak = 0;
        let settled = false;
        const cleanup = (aborted = false) => {
          if (settled) return;
          settled = true;
          clearInterval(poll);
          if (abortCodexSpeech === onAbort) abortCodexSpeech = null;
          try { bridge.inGain.gain.value = 0; } catch {}
          const spoke = voicedTicks >= 4;
          if (!spoke || aborted) {
            bridge.dcAcceptingTurn = false;
          }
          const endedAt = Date.now();
          const speechEndedAtMs = lastVoicedAt || endedAt;
          const silenceWaitMs = Math.max(0, endedAt - speechEndedAtMs);
          resolve({
            spoke,
            aborted,
            peak,
            ms: endedAt - startedAt,
            silenceWaitMs,
            speechEndedAtMs,
            liveTracks: remote.size,
          });
        };
        const onAbort = () => cleanup(true);
        abortCodexSpeech = onAbort;
        const poll = setInterval(() => {
          if (codexBridge !== bridge) { cleanup(true); return; }
          bridge.inMeter.getFloatTimeDomainData(bridge.inBuf);
          let sum = 0;
          for (let i = 0; i < bridge.inBuf.length; i++) sum += bridge.inBuf[i] * bridge.inBuf[i];
          const rms = Math.sqrt(sum / bridge.inBuf.length);
          const now = Date.now();
          const inEchoGuard = now - lastPlayEndedAt < 450;
          if (voiceStartedAt || !inEchoGuard) peak = Math.max(peak, rms);
          const onsetThreshold = Math.max(0.0055, noiseFloor * 1.8);
          const silenceThreshold = voicedTicks >= 2 && peak > 0.03
            ? Math.max(0.0045, Math.min(0.011, peak * 0.14))
            : Math.max(0.004, noiseFloor * 1.45);
          const activeThreshold = voiceStartedAt ? silenceThreshold : onsetThreshold;
          if ((voiceStartedAt || !inEchoGuard) && rms >= activeThreshold) {
            if (!voiceStartedAt) {
              onsetStreak++;
              if (onsetStreak >= 2 || rms >= 0.015) {
                voiceStartedAt = now;
                lastVoicedAt = now;
                bridge.inGain.gain.value = 1;
                voicedTicks = onsetStreak;
                silentTicks = 0;
              }
            } else {
              lastVoicedAt = now;
              voicedTicks++;
              silentTicks = 0;
            }
          } else {
            onsetStreak = 0;
            if (!voiceStartedAt) {
              noiseFloor = Math.min(0.0038, Math.max(0.002, noiseFloor * 0.9 + rms * 0.1));
            } else {
              silentTicks++;
              if (voicedTicks < 4 && silentTicks >= 4) {
                voiceStartedAt = 0;
                lastVoicedAt = 0;
                voicedTicks = 0;
                silentTicks = 0;
                onsetStreak = 0;
                try { bridge.inGain.gain.value = 0; } catch {}
              }
            }
            if (voiceStartedAt && voicedTicks >= 4 && silentTicks >= requiredSilentTicks) { cleanup(false); return; }
          }
          if (voicedTicks >= 4 && silentTicks >= 2) {
            bridge.outMeter.getFloatTimeDomainData(bridge.outBuf);
            let outSum = 0;
            for (let i = 0; i < bridge.outBuf.length; i++) outSum += bridge.outBuf[i] * bridge.outBuf[i];
            const outRms = Math.sqrt(outSum / bridge.outBuf.length);
            if (outRms > 0.004 || bridge.dcReplyDelta.length > 0 || bridge.dcReplyParts.length > 0 || bridge.dcReplyDone) {
              cleanup(false);
              return;
            }
          }
          if (voiceStartedAt && now - voiceStartedAt >= maxSpeakMs) { cleanup(false); return; }
          if (!voiceStartedAt && now - startedAt >= maxWaitMs) { cleanup(false); }
        }, 40);
      });
    },
    codexResetTurnState: resetCodexTurnState,
    codexCancelAndClear: cancelAndClearCodex,
    codexCloseIn() {
      if (codexBridge) codexBridge.inGain.gain.value = 0;
    },
    async codexOpenOut() {
      if (context?.state === 'suspended') await context.resume().catch(() => {});
      resumePageContexts();
      if (codexBridge?.replyAudio?.paused) {
        codexBridge.replyAudio.play().catch(() => {
          if (codexBridge?.replyAudio) {
            codexBridge.replyAudio.muted = true;
            codexBridge.replyAudio.play().catch(() => {});
          }
        });
      }
      await attachTeamsVirtualSenders();
      if (codexBridge) codexBridge.outGain.gain.value = 1;
    },
    async codexCloseOut(opts = {}) {
      if (codexBridge) {
        if (codexBridge.outGain.gain.value > 0) lastPlayEndedAt = Date.now();
        codexBridge.outGain.gain.value = 0;
        codexBridge.dcAcceptingTurn = false;
      }
      if (!opts?.keepTeamsSenders) {
        await restoreTeamsSenders();
      }
    },
    restoreTeamsSenders,
    async codexState() {
      if (!codexBridge?.pc) {
        return {
          connected: false,
          iceState: 'closed',
          rxPackets: 0,
          rxEnergy: 0,
          outRms: 0,
          micRms: 0,
          liveTracks: remote.size,
          dcHeard: '',
          dcReply: '',
          dcReplyDone: false,
          dcEvents: [],
        };
      }
      const bridge = codexBridge;
      let rxPackets = 0, rxEnergy = 0;
      try {
        for (const r of (await bridge.pc.getStats()).values()) {
          if (r.type === 'inbound-rtp' && r.kind === 'audio') {
            rxPackets += r.packetsReceived ?? 0;
            rxEnergy += r.totalAudioEnergy ?? 0;
          }
        }
      } catch {}
      bridge.outMeter.getFloatTimeDomainData(bridge.outBuf);
      let sum = 0;
      for (let i = 0; i < bridge.outBuf.length; i++) sum += bridge.outBuf[i] * bridge.outBuf[i];
      const outRms = Math.sqrt(sum / bridge.outBuf.length);
      const dcHeard = [...bridge.dcHeardParts, bridge.dcHeardDelta.trim()].filter(Boolean).join(' ').trim();
      const dcReply = [...bridge.dcReplyParts, bridge.dcReplyDelta.trim()].filter(Boolean).join(' ').trim();
      return {
        connected: bridge.pc.connectionState === 'connected' || bridge.pc.iceConnectionState === 'connected' || bridge.pc.iceConnectionState === 'completed',
        iceState: bridge.pc.iceConnectionState,
        rxPackets,
        rxEnergy,
        outRms,
        micRms: measureMicRms(),
        liveTracks: remote.size,
        dcHeard,
        dcReply,
        dcReplyDone: Boolean(bridge.dcReplyDone),
        serverResponseInFlight: Boolean(bridge.serverResponseInFlight),
        dcEvents: bridge.dcEvents.slice(-12),
      };
    },
    codexAbortSpeech() {
      abortCodexSpeech?.();
    },
    codexInterrupt() {
      if (codexBridge) {
        try { codexBridge.outGain.gain.value = 0; } catch {}
        cancelAndClearCodex();
      }
      restoreTeamsSenders().catch(() => {});
      abortCodexSpeech?.();
    },
    codexDisconnect() {
      destroyCodexBridge();
    },
  })});
}

function isAllowedMediaOrigin(origin) {
  if (typeof origin !== 'string') return false;
  let url;
  try { url = new URL(origin); } catch { return false; }
  if (url.protocol !== 'https:') return false;
  const host = url.hostname.toLowerCase();
  return host === 'meet.google.com'
    || host === 'teams.microsoft.com' || host.endsWith('.teams.microsoft.com')
    || host === 'teams.live.com' || host.endsWith('.teams.live.com')
    || host === 'teams.cloud.microsoft' || host.endsWith('.teams.cloud.microsoft')
    || host === 'm365.cloud.microsoft';
}

if (process.isMainFrame && (isAllowedMediaOrigin(location.origin) ||
    (process.argv.includes('--nail-local-voice-check') && location.protocol === 'data:'))) {
  require('electron').contextBridge.executeInMainWorld({
    func: installMedia,
    args: [process.argv.includes('--nail-meet-avatar')],
  });
}
