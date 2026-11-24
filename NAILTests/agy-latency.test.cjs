const {test} = require('node:test');
const assert = require('node:assert/strict');
const {EventEmitter} = require('node:events');
const {PassThrough} = require('node:stream');
const {mkdtemp, readFile, rm, writeFile, access} = require('node:fs/promises');
const {readFileSync, realpathSync} = require('node:fs');
const {join} = require('node:path');
const {tmpdir} = require('node:os');
const vm = require('node:vm');

const {
  createAgyDaemonClient,
  createMeetingNotesMemory,
  captureAntigravityAudio,
  executeAntigravityTurn,
} = require('../NAIL/Resources/meet.cjs');

function createFakeWorker() {
  const worker = new EventEmitter();
  worker.stdin = new PassThrough();
  worker.stdout = new PassThrough();
  worker.pid = 51515;
  worker.killed = false;
  worker.kill = () => {
    worker.killed = true;
    worker.emit('exit', 0);
  };
  return worker;
}

function createMediaSandbox({
  sampleProvider = () => new Float32Array(2048).fill(0),
  enableScriptProcessor = true,
  scriptProcessorIntervalMs = 10,
  hostname = 'meet.google.com',
  decodedDurationS = 0.08,
  manualTriggerOnended = false,
  decodeDelayMs = 0,
} = {}) {
  const source = readFileSync(join(__dirname, '../NAIL/Resources/meet-media.cjs'), 'utf8');
  const endIdx = source.indexOf('\nfunction isAllowedMediaOrigin');
  assert.ok(endIdx > 0);
  const installSrc = `${source.slice(0, endIdx)}\n;installMedia;`;

  let currentTimeS = 100;
  const createdBufferSources = [];
  const createdPeers = [];
  const createdScriptProcessors = [];

  class FakeGainNode {
    constructor() { this.gain = {value: 1}; this.disconnected = false; }
    connect() { return this; }
    disconnect() { this.disconnected = true; }
  }
  class FakeAnalyserNode {
    constructor() { this.fftSize = 256; }
    connect() { return this; }
    disconnect() {}
    getFloatTimeDomainData(buf) {
      const next = sampleProvider();
      for (let i = 0; i < buf.length; i++) buf[i] = next[i] ?? 0;
    }
  }
  class FakeScriptProcessorNode {
    constructor(bufferSize = 2048) {
      this.bufferSize = bufferSize;
      this.onaudioprocess = null;
      this.disconnected = false;
      this._timer = setInterval(() => {
        if (this.disconnected || typeof this.onaudioprocess !== 'function') return;
        const next = sampleProvider();
        const chan = new Float32Array(this.bufferSize);
        if (next && next.length > 0) {
          for (let i = 0; i < this.bufferSize; i++) chan[i] = next[i % next.length] ?? 0;
        }
        this.onaudioprocess({
          inputBuffer: {
            numberOfChannels: 1,
            length: this.bufferSize,
            sampleRate: 48000,
            getChannelData: () => chan,
          },
        });
      }, scriptProcessorIntervalMs);
      createdScriptProcessors.push(this);
    }
    connect() { return this; }
    disconnect() {
      this.disconnected = true;
      if (this._timer) {
        clearInterval(this._timer);
        this._timer = null;
      }
    }
  }
  const makeFakeTrack = (id = 'out-1') => ({
    id,
    kind: 'audio',
    readyState: 'live',
    enabled: true,
    muted: false,
    stop() { this.readyState = 'ended'; },
    clone() { return makeFakeTrack(`${id}-clone`); },
    getSettings() { return {}; },
  });
  class FakeMediaStreamDestination {
    constructor() {
      const track = makeFakeTrack('out-1');
      this.stream = {getAudioTracks: () => [track], getTracks: () => [track]};
    }
  }
  class FakeAudioBufferSourceNode {
    constructor() {
      this.buffer = null;
      this.onended = null;
      this.started = false;
      this.stopped = false;
      this.disconnected = false;
      this.startWhen = null;
      this.connectedTo = [];
      createdBufferSources.push(this);
    }
    connect(target) { this.connectedTo.push(target); return this; }
    disconnect() { this.disconnected = true; }
    start(when = 0) {
      this.started = true;
      this.startWhen = when;
      if (!manualTriggerOnended) {
        setTimeout(() => {
          if (!this.stopped) this.onended?.();
        }, 25);
      }
    }
    stop() {
      this.stopped = true;
      this.onended?.();
    }
  }
  class FakeAudioContext {
    constructor() {
      this.sampleRate = 48000;
      this.state = 'running';
      this.destination = {maxChannelCount: 2};
    }
    get currentTime() { return currentTimeS; }
    resume() { return Promise.resolve(); }
    createGain() { return new FakeGainNode(); }
    createDelay() { return {delayTime: {value: 0}, connect() { return this; }, disconnect() {}}; }
    createConstantSource() { return {offset: {value: 0}, connect() { return this; }, disconnect() {}, start() {}, stop() {}}; }
    createAnalyser() { return new FakeAnalyserNode(); }
    createMediaStreamDestination() { return new FakeMediaStreamDestination(); }
    createMediaStreamSource() { return {disconnected: false, connect() {}, disconnect() { this.disconnected = true; }}; }
    createBuffer(_ch, length, sampleRate) {
      return {
        length,
        sampleRate,
        numberOfChannels: 1,
        duration: length / sampleRate,
        data: new Float32Array(length),
        copyToChannel(src) { this.data.set(src.subarray(0, this.length)); },
        getChannelData() { return this.data; },
      };
    }
    createBufferSource() { return new FakeAudioBufferSourceNode(); }
    async decodeAudioData(arr) {
      if (decodeDelayMs > 0) await new Promise(r => setTimeout(r, decodeDelayMs));
      return {
        sampleRate: 16000,
        length: Math.round(16000 * decodedDurationS),
        numberOfChannels: 1,
        duration: decodedDurationS,
        byteLength: arr.byteLength,
        getChannelData: () => new Float32Array(Math.round(16000 * decodedDurationS)),
      };
    }
  }
  if (enableScriptProcessor) {
    FakeAudioContext.prototype.createScriptProcessor = function (bufferSize = 2048) {
      return new FakeScriptProcessorNode(bufferSize);
    };
  }
  class FakeMediaStream {
    constructor(tracks = []) { this._tracks = tracks; }
    getTracks() { return this._tracks; }
    getAudioTracks() { return this._tracks.filter(t => t.kind === 'audio'); }
    addTrack(t) { this._tracks.push(t); }
    clone() { return new FakeMediaStream([...this._tracks]); }
  }
  class FakeMediaRecorder {
    constructor() { this.state = 'inactive'; this.ondataavailable = null; this.onstop = null; }
    start() { this.state = 'recording'; }
    stop() { this.state = 'inactive'; this.onstop?.(); }
  }
  class FakeRTCPeerConnection extends EventEmitter {
    constructor() {
      super();
      this.connectionState = 'connected';
      this.iceConnectionState = 'connected';
      this.iceGatheringState = 'complete';
      this._senders = [];
      createdPeers.push(this);
    }
    addTrack() {}
    createDataChannel() { return new EventEmitter(); }
    createOffer() { return Promise.resolve({sdp: 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n', type: 'offer'}); }
    setLocalDescription() { return Promise.resolve(); }
    setRemoteDescription() { return Promise.resolve(); }
    close() { this.connectionState = 'closed'; }
    getStats() { return Promise.resolve(new Map()); }
    getSenders() { return this._senders; }
    getTransceivers() { return []; }
    addEventListener(type, fn) { this.on(type, fn); }
    removeEventListener(type, fn) { this.off(type, fn); }
  }
  const remoteTrack = {id: 'r1', kind: 'audio', readyState: 'live', enabled: true, stop() {}, addEventListener() {}};
  const FakeMediaStreamTrack = class {};
  FakeMediaStreamTrack.prototype.clone = function () { return makeFakeTrack(`${this.id || 'trk'}-clone`); };
  const windowObj = {
    location: {hostname, origin: `https://${hostname}`},
    AudioContext: FakeAudioContext,
    Audio: class { constructor() { this.muted = false; this.srcObject = null; } play() { return Promise.resolve(); } pause() {} },
    MediaStream: FakeMediaStream,
    MediaStreamTrack: FakeMediaStreamTrack,
    MediaRecorder: FakeMediaRecorder,
    RTCPeerConnection: FakeRTCPeerConnection,
    HTMLMediaElement: {prototype: {}},
    navigator: {mediaDevices: {getUserMedia: () => Promise.resolve(new FakeMediaStream([])), enumerateDevices: () => Promise.resolve([])}},
    document: {createElement: () => ({})},
    btoa: s => Buffer.from(s, 'binary').toString('base64'),
    atob: s => Buffer.from(s, 'base64').toString('binary'),
    Blob,
    FileReader: class {
      readAsDataURL(blob) {
        blob.arrayBuffer().then(ab => {
          this.result = `data:audio/webm;base64,${Buffer.from(ab).toString('base64')}`;
          this.onloadend?.();
        });
      }
    },
    crypto: {getRandomValues: arr => arr},
    setTimeout, clearTimeout, setInterval, clearInterval,
    Date, Math, Promise, Error, Set, Map, Uint8Array, Int16Array, Float32Array,
    Object, Array, Number, String, Boolean, JSON, console,
  };
  Object.defineProperty(windowObj.HTMLMediaElement.prototype, 'srcObject', {
    configurable: true,
    set(v) { this._src = v; },
    get() { return this._src ?? null; },
  });
  windowObj.window = windowObj;
  windowObj.self = windowObj;
  const ctx = vm.createContext(windowObj);
  vm.runInContext(installSrc, ctx)(false);
  const meetPc = new windowObj.RTCPeerConnection();
  meetPc.emit('track', {track: remoteTrack});

  return {
    windowObj,
    api: windowObj.__nailMedia,
    meetPc,
    makeFakeTrack,
    createdBufferSources,
    createdScriptProcessors,
    setCurrentTimeS: t => { currentTimeS = t; },
  };
}

test('meet-media.cjs recordPcm16k supports manual pause, configurable silenceMs, standby echo-guard, and __nailUpgradeRecord', async () => {
  // 1) Manual mode: tolerates initial pause before soft speech and finishes after custom silenceMs
  let manualIdx = 0;
  const manualSandbox = createMediaSandbox({
    scriptProcessorIntervalMs: 10,
    sampleProvider: () => {
      manualIdx++;
      if (manualIdx <= 4) return new Float32Array(2048).fill(0.0005); // initial pause
      if (manualIdx <= 7) return new Float32Array(2048).fill(0.02);   // manual speech
      return new Float32Array(2048).fill(0.0002);                      // silence
    },
  });
  const manualRes = await manualSandbox.api.recordPcm16k(4000, false, 4000, 180);
  assert.ok(manualRes && typeof manualRes.pcmBase64 === 'string');
  assert.equal(manualRes.sampleRate, 16000);
  assert.ok(manualRes.durationMs >= 200);
  assert.equal(manualSandbox.createdScriptProcessors[0].disconnected, true);

  // 2) Standby autoListen + __nailUpgradeRecord() upgrades immediately and keeps pre-roll
  let upgradeIdx = 0;
  const upgradeSandbox = createMediaSandbox({
    scriptProcessorIntervalMs: 10,
    sampleProvider: () => {
      upgradeIdx++;
      if (upgradeIdx <= 3) return new Float32Array(2048).fill(0.001);
      if (upgradeIdx <= 6) return new Float32Array(2048).fill(0.08);
      return new Float32Array(2048).fill(0.0002);
    },
  });
  const pending = upgradeSandbox.api.recordPcm16k(4000, true, 4000, 180);
  await new Promise(r => setTimeout(r, 25));
  assert.equal(upgradeSandbox.windowObj.__nailUpgradeRecord?.(), true);
  const upgradedRes = await pending;
  assert.ok(upgradedRes && typeof upgradedRes.pcmBase64 === 'string');
  assert.equal(upgradedRes.sampleRate, 16000);

  // 3) Standby echo-guard ignores audio within 450ms of lastPlayEndedAt
  let echoActive = true;
  const echoSandbox = createMediaSandbox({
    scriptProcessorIntervalMs: 10,
    manualTriggerOnended: true,
    sampleProvider: () => new Float32Array(2048).fill(echoActive ? 0.08 : 0.0002),
  });
  const playPromise = echoSandbox.api.play(Buffer.from('RIFF').toString('base64'));
  await new Promise(r => setTimeout(r, 20));
  echoSandbox.createdBufferSources[0].onended?.();
  await playPromise;
  setTimeout(() => { echoActive = false; }, 120);
  const echoRes = await echoSandbox.api.recordPcm16k(2000, true, 250, 180);
  assert.equal(echoRes, null);
});

test('meet-media.cjs playChunk schedules gaplessly on micBus, keeps Teams senders until waitPlayback, and stops cleanly on stopPlay', async () => {
  const sandbox = createMediaSandbox({
    hostname: 'teams.microsoft.com',
    decodedDurationS: 0.25,
    manualTriggerOnended: true,
  });
  const origTrack = sandbox.makeFakeTrack('teams-orig');
  const sender = {
    track: origTrack,
    async replaceTrack(next) { this.track = next; },
  };
  sandbox.meetPc._senders.push(sender);

  const b64 = Buffer.from('fake-wav').toString('base64');
  const ok0 = await sandbox.api.playChunk(b64);
  const ok1 = await sandbox.api.playChunk(b64);
  assert.equal(ok0, true);
  assert.equal(ok1, true);
  assert.equal(sandbox.createdBufferSources.length, 2);

  const [src0, src1] = sandbox.createdBufferSources;
  assert.equal(src0.startWhen, 100);
  assert.equal(src1.startWhen, 100.25);
  assert.equal(sandbox.api.avatarAudioSample().sending, true);
  assert.notEqual(sender.track, origTrack, 'Teams sender must remain virtual while chunks are queued');

  let waitedDone = false;
  const waitPromise = sandbox.api.waitPlayback().then(() => { waitedDone = true; });
  src0.onended();
  await new Promise(r => setTimeout(r, 10));
  assert.equal(waitedDone, false, 'waitPlayback must wait for chunk 1');
  assert.notEqual(sender.track, origTrack, 'Teams sender must remain virtual between chunks');

  src1.onended();
  await waitPromise;
  assert.equal(waitedDone, true);
  assert.equal(sandbox.api.avatarAudioSample().sending, false);
  assert.equal(sender.track, origTrack, 'Teams sender must restore after waitPlayback completes');

  // Now verify stopPlay() mid-decode/mid-queue cancels in-flight and queued playback immediately
  const slowSandbox = createMediaSandbox({
    hostname: 'teams.microsoft.com',
    decodedDurationS: 0.5,
    decodeDelayMs: 40,
    manualTriggerOnended: true,
  });
  const slowOrig = slowSandbox.makeFakeTrack('teams-slow');
  const slowSender = {track: slowOrig, async replaceTrack(next) { this.track = next; }};
  slowSandbox.meetPc._senders.push(slowSender);

  const p0 = slowSandbox.api.playChunk(b64);
  const p1 = slowSandbox.api.playChunk(b64);
  await new Promise(r => setTimeout(r, 10));
  slowSandbox.api.stopPlay();
  assert.equal(await p0, false);
  assert.equal(await p1, false);
  await slowSandbox.api.waitPlayback();
  assert.equal(slowSandbox.createdBufferSources.length, 0);
  assert.equal(slowSandbox.api.avatarAudioSample().sending, false);
  assert.equal(slowSender.track, slowOrig);
});

test('createAgyDaemonClient sends cancel immediately on mid-turn abort and routes audio_chunk events', async () => {
  const received = [];
  const seenChunks = [];
  const client = createAgyDaemonClient({
    pipeline: '/tmp/agy-voice.py',
    spawnWorker: () => {
      const w = createFakeWorker();
      setImmediate(() => w.stdout.write(`${JSON.stringify({ready: true})}\n`));
      w.stdin.on('data', chunk => {
        for (const line of chunk.toString('utf8').split(/\r?\n/).filter(Boolean)) {
          const msg = JSON.parse(line);
          received.push(msg);
          if (msg.id === 1 && msg.from_wav) {
            setTimeout(() => {
              w.stdout.write(`${JSON.stringify({id: 1, event: 'audio_chunk', index: 0, wav: '/tmp/c0.wav', text: 'Halo.', final: false})}\n`);
            }, 10);
          }
        }
      });
      return w;
    },
  });

  const ac = new AbortController();
  const turnPromise = client.runTurn(
    {from_wav: '/tmp/in.pcm', input_format: 'pcm16k', reply_wav: '/tmp/reply.wav', stream_audio: true},
    {
      signal: ac.signal,
      onAudioChunk: async msg => {
        seenChunks.push(msg);
        ac.abort(new Error('voice-interrupted'));
      },
    }
  );
  await assert.rejects(turnPromise, /voice-interrupted/);
  assert.equal(seenChunks.length, 1);
  assert.equal(seenChunks[0].index, 0);
  const cancelMsgs = received.filter(m => m.action === 'cancel' && m.id === 1);
  assert.equal(cancelMsgs.length, 1);
  client.recycle();
});

test('executeAntigravityTurn streams PCM16k + chunks, unmutes in parallel, cleans chunk WAVs, and restores mute', async () => {
  const work = await mkdtemp(join(tmpdir(), 'nail-agy-stream-'));
  try {
    const chunk0 = join(work, 'reply.chunk0.wav');
    const chunk1 = join(work, 'reply.chunk1.wav');
    await writeFile(chunk0, Buffer.from('WAV0'));
    await writeFile(chunk1, Buffer.from('WAV1'));

    const events = [];
    const jsCalls = [];
    const playedChunks = [];
    let muted = true;
    let unmuteStartedAt = 0;
    let runTurnStartedAt = 0;
    const notes = createMeetingNotesMemory();

    const wc = {
      async executeJavaScript(script) {
        jsCalls.push(script);
        const match = script.match(/playChunk\(([^)]+)\)/);
        if (match) {
          playedChunks.push(Buffer.from(JSON.parse(match[1]), 'base64').toString('utf8'));
        }
        return true;
      },
    };
    const agyClient = {
      async ensureReady() {},
      async runTurn(payload, {onAudioChunk}) {
        runTurnStartedAt = Date.now();
        assert.equal(payload.input_format, 'pcm16k');
        assert.equal(payload.stream_audio, true);
        assert.ok(payload.from_wav.endsWith('meeting.pcm'));
        // On macOS, tmpdir() is /var/folders/... while Python's reply_wav.resolve() emits /private/var/folders/...
        await onAudioChunk({event: 'audio_chunk', index: 0, wav: realpathSync(chunk0), text: 'Halo.', final: false});
        await onAudioChunk({event: 'audio_chunk', index: 1, wav: chunk1, text: 'Siap.', final: true});
        return {heard: 'Halo Nail', reply: 'Halo. Siap.', streamed: true, chunks: 2};
      },
    };

    const res = await executeAntigravityTurn({
      wc,
      work,
      read: async () => ({mute: {name: 'Mute'}, unmute: muted ? {name: 'Unmute'} : null}),
      click: async btn => {
        if (btn.name === 'Unmute') { muted = false; return true; }
        if (btn.name === 'Mute') { muted = true; return true; }
        return false;
      },
      manual: true,
      clip: {pcmBase64: Buffer.from([1, 0, 2, 0]).toString('base64'), sampleRate: 16000},
      heardAtMs: Date.now() - 10,
      agyClient,
      meetingNotes: notes,
      unmuteAndVerifyMicFn: async (_wc, _read, clickFn, state) => {
        unmuteStartedAt = Date.now();
        state.restoreMute = await clickFn({name: 'Unmute'});
        return true;
      },
      restoreMeetMuteFn: async (_wc, _read, clickFn, shouldRestore) => {
        if (shouldRestore) await clickFn({name: 'Mute'});
      },
      emit: ev => events.push(ev),
      delayFn: async () => {},
    });

    assert.equal(res.status, 'completed');
    assert.equal(res.streamedChunks, 2);
    assert.ok(unmuteStartedAt <= runTurnStartedAt, 'Manual turn must start unmute before runTurn');
    assert.deepEqual(playedChunks, ['WAV0', 'WAV1']);
    assert.equal(events.filter(e => e === 'voice-sending').length, 1);
    assert.ok(events.some(e => e.startsWith('voice-result ')));
    assert.ok(events.includes('voice-followup'));
    assert.ok(jsCalls.some(s => s.includes('waitPlayback')));
    assert.equal(muted, true, 'Mic must be restored to muted after turn');
    await assert.rejects(access(chunk0));
    await assert.rejects(access(chunk1));
  } finally {
    await rm(work, {recursive: true, force: true});
  }
});

test('executeAntigravityTurn starts unmute in onWake and always restores mic mute when skipped or aborted', async () => {
  // 1) Hands-free standby: unmute starts in onWake, then turn is skipped -> in-flight unmute settles and restores mute!
  const work1 = await mkdtemp(join(tmpdir(), 'nail-agy-skip-'));
  try {
    let muted = true;
    let clickCalls = 0;
    let restoreCalls = 0;
    const notes = createMeetingNotesMemory();
    const res = await executeAntigravityTurn({
      wc: {async executeJavaScript() { return true; }},
      work: work1,
      read: async () => ({mute: {name: 'Mute'}}),
      click: async btn => {
        if (btn.name === 'Unmute') {
          clickCalls++;
          await new Promise(r => setTimeout(r, 30));
          muted = false;
          return true;
        }
        if (btn.name === 'Mute') {
          restoreCalls++;
          muted = true;
          return true;
        }
        return false;
      },
      manual: false,
      clip: {pcmBase64: Buffer.from([1, 0, 2, 0]).toString('base64'), sampleRate: 16000},
      heardAtMs: Date.now(),
      agyClient: {
        async ensureReady() {},
        async runTurn(_payload, {onWake}) {
          onWake({event: 'wake', heard: 'Nail bacakan layar'});
          // Return skipped immediately while unmute click is still in flight
          return {heard: 'Nail bacakan layar', reply: '', skipped: true};
        },
      },
      meetingNotes: notes,
      unmuteAndVerifyMicFn: async (_wc, _read, clickFn, state) => {
        state.restoreMute = await clickFn({name: 'Unmute'});
        return true;
      },
      restoreMeetMuteFn: async (_wc, _read, clickFn, shouldRestore) => {
        if (shouldRestore) await clickFn({name: 'Mute'});
      },
      delayFn: async () => {},
    });

    assert.equal(res.status, 'skipped');
    assert.equal(clickCalls, 1);
    assert.equal(restoreCalls, 1);
    assert.equal(muted, true, 'Mic must be re-muted even when skipped while unmute click was in flight');
  } finally {
    await rm(work1, {recursive: true, force: true});
  }

  // 2) Barge-in abort mid-stream: calls stopPlay() and restores mic mute cleanly
  const work2 = await mkdtemp(join(tmpdir(), 'nail-agy-abort-'));
  try {
    const chunk0 = join(work2, 'reply.chunk0.wav');
    await writeFile(chunk0, Buffer.from('WAV0'));
    let muted = true;
    let stopPlayCalled = false;
    const ac = new AbortController();
    const events = [];

    const res = await executeAntigravityTurn({
      wc: {
        async executeJavaScript(script) {
          if (script.includes('stopPlay')) stopPlayCalled = true;
          return true;
        },
      },
      work: work2,
      read: async () => ({mute: {name: 'Mute'}}),
      click: async btn => {
        if (btn.name === 'Mute') { muted = true; return true; }
        return false;
      },
      manual: true,
      clip: {pcmBase64: Buffer.from([1, 0, 2, 0]).toString('base64'), sampleRate: 16000},
      heardAtMs: Date.now(),
      agyClient: {
        async ensureReady() {},
        async runTurn(_payload, {signal, onAudioChunk}) {
          await onAudioChunk({event: 'audio_chunk', index: 0, wav: chunk0, text: 'Halo.', final: false});
          ac.abort(new Error('voice-interrupted'));
          throw signal.reason;
        },
      },
      meetingNotes: createMeetingNotesMemory(),
      unmuteAndVerifyMicFn: async (_wc, _read, _click, state) => {
        muted = false;
        state.restoreMute = true;
        return true;
      },
      restoreMeetMuteFn: async (_wc, _read, clickFn, shouldRestore) => {
        if (shouldRestore) await clickFn({name: 'Mute'});
      },
      emit: ev => events.push(ev),
      signal: ac.signal,
      delayFn: async () => {},
    });

    assert.equal(res.status, 'aborted');
    assert.equal(stopPlayCalled, true);
    assert.equal(muted, true);
    assert.equal(events.includes('voice-failed'), false);
  } finally {
    await rm(work2, {recursive: true, force: true});
  }

  // 3) Abort arriving while awaiting waitPlayback() triggers stopPlay() immediately and unblocks
  const work3 = await mkdtemp(join(tmpdir(), 'nail-agy-wait-abort-'));
  try {
    const chunk0 = join(work3, 'reply.chunk0.wav');
    await writeFile(chunk0, Buffer.from('WAV0'));
    let muted = true;
    let stopPlayCalled = false;
    let resolveWaitPlayback = null;
    const ac = new AbortController();

    const res = await executeAntigravityTurn({
      wc: {
        executeJavaScript(script) {
          if (script.includes('waitPlayback')) {
            setTimeout(() => ac.abort(new Error('voice-interrupted')), 15);
            return new Promise(resolve => { resolveWaitPlayback = resolve; });
          }
          if (script.includes('stopPlay')) {
            stopPlayCalled = true;
            resolveWaitPlayback?.();
          }
          return Promise.resolve(true);
        },
      },
      work: work3,
      read: async () => ({mute: {name: 'Mute'}}),
      click: async btn => {
        if (btn.name === 'Mute') { muted = true; return true; }
        return false;
      },
      manual: true,
      clip: {pcmBase64: Buffer.from([1, 0, 2, 0]).toString('base64'), sampleRate: 16000},
      heardAtMs: Date.now(),
      agyClient: {
        async ensureReady() {},
        async runTurn(_payload, {onAudioChunk}) {
          await onAudioChunk({event: 'audio_chunk', index: 0, wav: realpathSync(chunk0), text: 'Halo.', final: true});
          return {heard: 'Halo', reply: 'Halo.', streamed: true, chunks: 1};
        },
      },
      meetingNotes: createMeetingNotesMemory(),
      unmuteAndVerifyMicFn: async (_wc, _read, _click, state) => {
        muted = false;
        state.restoreMute = true;
        return true;
      },
      restoreMeetMuteFn: async (_wc, _read, clickFn, shouldRestore) => {
        if (shouldRestore) await clickFn({name: 'Mute'});
      },
      signal: ac.signal,
      delayFn: async () => {},
    });

    assert.equal(res.status, 'aborted');
    assert.equal(stopPlayCalled, true);
    assert.equal(muted, true);
  } finally {
    await rm(work3, {recursive: true, force: true});
  }
});

test('executeAntigravityTurn falls back to single reply.wav and captureAntigravityAudio falls back to record()', async () => {
  // 1) captureAntigravityAudio falls back to record() when recordPcm16k is absent
  const calls = [];
  const legacyClip = await captureAntigravityAudio(
    {
      async executeJavaScript(script) {
        calls.push(script);
        return script.includes('recordPcm16k') ? undefined : Buffer.from('WEBM').toString('base64');
      },
    },
    true,
    12000,
    450
  );
  assert.equal(calls.length, 2);
  assert.equal(Buffer.from(legacyClip, 'base64').toString('utf8'), 'WEBM');

  // 2) executeAntigravityTurn uses meeting.webm and falls back to __nailMedia.play() when no audio_chunk is emitted
  const work = await mkdtemp(join(tmpdir(), 'nail-agy-fallback-'));
  try {
    const replyWav = join(work, 'reply.wav');
    await writeFile(replyWav, Buffer.from('FULL_WAV'));
    let playedSingle = '';
    const events = [];
    const seenPayload = {};

    const res = await executeAntigravityTurn({
      wc: {
        async executeJavaScript(script) {
          const match = script.match(/__nailMedia\.play\(([^)]+)\)/);
          if (match) playedSingle = Buffer.from(JSON.parse(match[1]), 'base64').toString('utf8');
          return true;
        },
      },
      work,
      read: async () => ({mute: {name: 'Mute'}}),
      click: async () => true,
      manual: true,
      clip: Buffer.from('WEBM_CLIP').toString('base64'),
      heardAtMs: Date.now(),
      agyClient: {
        async ensureReady() {},
        async runTurn(payload) {
          Object.assign(seenPayload, payload);
          return {heard: 'Tes', reply: 'Oke siap'};
        },
      },
      meetingNotes: createMeetingNotesMemory(),
      unmuteAndVerifyMicFn: async (_wc, _read, _click, state) => { state.restoreMute = true; return true; },
      restoreMeetMuteFn: async () => {},
      emit: ev => events.push(ev),
      delayFn: async () => {},
    });

    assert.equal(res.status, 'completed');
    assert.equal(res.streamedChunks, 0);
    assert.equal(seenPayload.input_format, undefined);
    assert.ok(seenPayload.from_wav.endsWith('meeting.webm'));
    assert.equal(playedSingle, 'FULL_WAV');
    assert.equal(events.filter(e => e === 'voice-sending').length, 1);
  } finally {
    await rm(work, {recursive: true, force: true});
  }
});
