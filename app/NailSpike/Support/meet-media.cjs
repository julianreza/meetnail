function installMedia() {
  // Both destinations are in-memory Web Audio streams, never hardware devices.
  const Peer = window.RTCPeerConnection;
  const remote = new Map();
  const peers = new Set();
  const virtualTracks = new WeakSet();
  const origClone = MediaStreamTrack.prototype.clone;
  MediaStreamTrack.prototype.clone = function () {
    const cloned = origClone.apply(this, arguments);
    if (virtualTracks.has(this)) virtualTracks.add(cloned);
    return cloned;
  };
  let micCalls = 0;
  const perms = navigator.permissions;
  if (perms?.query) {
    const origQuery = perms.query.bind(perms);
    perms.query = desc => desc?.name === 'microphone'
      ? Promise.resolve({state: 'granted', name: 'microphone', onchange: null})
      : origQuery(desc);
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
      const st = {id, inC: 0, outC: 0, inBytes: 0, outBytes: 0, err: null, sample: []};
      encStats.push(st);
      const writer = streams.writable.getWriter();
      let meetActive = false;
      const inTap = new TransformStream({async transform(f, c) {
        st.inC++; st.inBytes += f.data?.byteLength ?? 0;
        if (st.sample.length < 4 && (f.data.byteLength > 20 || st.sample.length === 0)) {
          const b = new Uint8Array(f.data, 0, Math.min(80, f.data.byteLength));
          st.sample.push({len: f.data.byteLength, ts: f.timestamp, meta: f.getMetadata?.(),
            hex: [...b].map(x => x.toString(16).padStart(2, '0')).join(' ')});
        }
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
  let context, mic, mix;
  const start = async () => {
    if (!context) {
      context = new AudioContext();
      mic = context.createMediaStreamDestination();
      mix = context.createMediaStreamDestination();
    }
    await context.resume();
  };
  const microphone = async () => {
    await start();
    micCalls++;
    const track = mic.stream.getAudioTracks()[0].clone();
    virtualTracks.add(track);
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
        audio.play().catch(() => {});
        track.addEventListener('ended', () => {
          audio.srcObject = null;
          remote.delete(track);
        }, {once: true});
      });
      peer.addEventListener('connectionstatechange', () => {
        if (peer.connectionState !== 'closed') return;
        peers.delete(peer);
        for (const [track, entry] of remote) if (entry.peer === peer) {
          entry.audio.srcObject = null;
          remote.delete(track);
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
      const virtual = {kind: 'audioinput', deviceId: 'default', groupId: 'nail', label: 'Nail'};
      return [{...virtual, toJSON: () => virtual}, ...(await enumerate()).filter(d => d.kind !== 'audioinput')];
    };
    devices.getUserMedia = constraints => constraints?.audio ? microphone() : getMedia(constraints);
  }
  Object.defineProperty(window, '__nailMedia', {value: Object.freeze({
    microphone,
    sending: () => [...peers].some(peer => peer.connectionState === 'connected' &&
      peer.getSenders().some(({track}) => track?.enabled && track.readyState === 'live' &&
        (virtualTracks.has(track) || (micCalls > 0 && track.label === 'MediaStreamAudioDestinationNode')))),
    micDiag: () => ({
      micCalls,
      senders: [...peers].filter(p => p.connectionState === 'connected').flatMap(p =>
        p.getSenders().filter(s => s.track?.kind === 'audio').map(s => ({
          enabled: s.track.enabled, muted: s.track.muted, state: s.track.readyState,
          virtual: virtualTracks.has(s.track), label: s.track.label,
        }))),
    }),
    async record(milliseconds, autoListen = false) {
      await start();
      if (milliseconds <= 0 || milliseconds > 8000) throw new Error('Invalid capture duration');
      const sources = [];
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
        preRoll.delayTime.value = 0.45;
        preRoll.connect(mix);
        const meter = context.createAnalyser();
        meter.fftSize = 1024;
        const meterBuf = new Float32Array(meter.fftSize);
        for (const track of remote.keys()) if (track.readyState === 'live') {
          const source = context.createMediaStreamSource(new MediaStream([track]));
          source.connect(preRoll);
          source.connect(meter);
          sources.push(source);
        }
        sources.push(preRoll);
        window.__nailDiagnostics = {tracks: remote.size, live: sources.length - 1,
          muted: [...remote.keys()].filter(t => t.muted).length};
        if (sources.length <= 1) return '';
        const before = await rxStats();
        const recorder = new MediaRecorder(mix.stream, {mimeType: 'audio/webm;codecs=opus', audioBitsPerSecond: 64000});
        const blob = await new Promise((resolve, reject) => {
          const chunks = [];
          let ticks = 0, voicedTicks = 0, silentTicks = 0, started = !autoListen;
          window.__nailUpgradeRecord = () => {
            autoListen = false;
            ticks = 0;
            if (!started && recorder.state === 'inactive') { started = true; recorder.start(); }
          };
          const poll = setInterval(() => {
            ticks++;
            if (started && recorder.state === 'recording' && ticks >= Math.round(milliseconds / 100)) {
              recorder.stop();
              return;
            }
            meter.getFloatTimeDomainData(meterBuf);
            let sum = 0;
            for (let i = 0; i < meterBuf.length; i++) sum += meterBuf[i] * meterBuf[i];
            const rms = Math.sqrt(sum / meterBuf.length);
            if (rms >= 0.004) {
              if (!started && recorder.state === 'inactive') { started = true; ticks = 0; recorder.start(); }
              voicedTicks++;
              silentTicks = 0;
            } else if (started && recorder.state === 'recording') {
              if (voicedTicks >= 3 && ++silentTicks >= 11) recorder.stop();
            } else if (!started && ticks >= 120) {
              clearInterval(poll);
              resolve(null);
            }
          }, 100);
          recorder.ondataavailable = e => chunks.push(e.data);
          recorder.onstop = () => { clearInterval(poll); resolve(new Blob(chunks)); };
          recorder.onerror = () => { clearInterval(poll); reject(new Error('Recorder failed')); };
          if (started) recorder.start();
        });
        if (!blob) return '';
        const after = await rxStats();
        const data = await blob.arrayBuffer();
        const decoded = await context.decodeAudioData(data.slice(0));
        const width = Math.round(decoded.sampleRate * 0.02);
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
          if (energy >= width * decoded.numberOfChannels * 0.003 ** 2) voicedFrames++;
        }
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
            const audioSdp = (peer.remoteDescription?.sdp ?? '').split(/\r?\n/)
              .filter(l => /^(m=audio|a=(rtpmap|fmtp|ssrc|mid|send|recv|inact))/.test(l)).slice(0, 30);
            inbound.push({peerState: peer.connectionState, ua: navigator.userAgent, ctxState: context?.state, ctxTime: context?.currentTime,
              receivers, transceivers, audioStates, playout, encStats, diagLog: diagLog.slice(-20), audioSdp});
          } catch {}
        }
        window.__nailInbound = inbound;
        if (voicedFrames < 5) return '';
        const bytes = new Uint8Array(data);
        let binary = '';
        for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
        return btoa(binary);
      } finally {
        for (const source of sources) source.disconnect();
      }
    },
    async play(encoded) {
      await start();
      const wav = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
      const buffer = await context.decodeAudioData(wav.buffer);
      const player = context.createBufferSource();
      player.buffer = buffer;
      player.connect(mic);
      await new Promise(resolve => { player.onended = resolve; player.start(); });
      player.disconnect();
    },
  })});
}

if (process.isMainFrame && (location.origin === 'https://meet.google.com' ||
    (process.argv.includes('--nail-local-voice-check') && location.protocol === 'data:'))) {
  require('electron').contextBridge.executeInMainWorld({func: installMedia});
}
