const {test} = require('node:test');
const assert = require('node:assert/strict');
const {EventEmitter} = require('node:events');
const {PassThrough} = require('node:stream');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');

const {createAgyDaemonClient} = require('../NAIL/Resources/meet.cjs');
const {CodexLiveSession} = require('../NAIL/Resources/codex-voice.cjs');

function createFakeWorker() {
  const worker = new EventEmitter();
  worker.stdin = new PassThrough();
  worker.stdout = new PassThrough();
  worker.pid = 42424;
  worker.killed = false;
  worker.kill = () => {
    worker.killed = true;
    worker.emit('exit', 0);
  };
  return worker;
}

test('createAgyDaemonClient correlates responses by request id and discards aborted stale answers', async () => {
  const workers = [];
  let spawnCount = 0;

  const client = createAgyDaemonClient({
    pipeline: '/tmp/agy-voice.py',
    spawnWorker: () => {
      spawnCount++;
      const w = createFakeWorker();
      workers.push(w);
      setImmediate(() => {
        w.stdout.write(`${JSON.stringify({ready: true})}\n`);
      });
      w.stdin.on('data', chunk => {
        const lines = chunk.toString('utf8').split(/\r?\n/).filter(Boolean);
        for (const raw of lines) {
          const req = JSON.parse(raw);
          if (req.id === 1 && req.from_wav) {
            // Delay Turn 1's response so Turn 1 gets aborted while waiting, then Turn 1 STILL emits stale lines before Turn 2!
            setTimeout(() => {
              w.stdout.write(`${JSON.stringify({id: 1, event: 'wake', heard: 'Q1 lama'})}\n`);
              w.stdout.write(`${JSON.stringify({id: 1, heard: 'Q1 lama', reply: 'STALE A1'})}\n`);
            }, 30);
          } else if (req.id === 2 && req.from_wav) {
            setTimeout(() => {
              w.stdout.write(`${JSON.stringify({id: 2, heard: 'Q2 baru', reply: 'FRESH A2'})}\n`);
            }, 50);
          }
        }
      });
      return w;
    },
  });

  const ac1 = new AbortController();
  const p1 = client.runTurn({from_wav: '/tmp/q1.wav', reply_wav: '/tmp/a1.wav'}, {signal: ac1.signal});
  setTimeout(() => ac1.abort(new Error('voice-interrupted')), 10);
  await assert.rejects(p1, /voice-interrupted/);

  // Turn 2 must NOT pick up id=1's late stdout lines; it must get id=2's reply!
  const res2 = await client.runTurn({from_wav: '/tmp/q2.wav', reply_wav: '/tmp/a2.wav'});
  assert.equal(res2.heard, 'Q2 baru');
  assert.equal(res2.reply, 'FRESH A2');
  assert.equal(spawnCount, 1);

  client.recycle();
  assert.equal(workers[0].killed, true);
  assert.equal(client.isRunning, false);
});

test('createAgyDaemonClient sends cancel decision when aborted during transcribed presentation check', async () => {
  const received = [];
  const client = createAgyDaemonClient({
    pipeline: '/tmp/agy-voice.py',
    spawnWorker: () => {
      const w = createFakeWorker();
      setImmediate(() => w.stdout.write(`${JSON.stringify({ready: true})}\n`));
      w.stdin.on('data', chunk => {
        for (const line of chunk.toString('utf8').split(/\r?\n/).filter(Boolean)) {
          const msg = JSON.parse(line);
          received.push(msg);
          if (msg.from_wav) {
            setImmediate(() => w.stdout.write(`${JSON.stringify({id: msg.id, event: 'transcribed', heard: 'bacakan layar'})}\n`));
          }
        }
      });
      return w;
    },
  });

  const ac = new AbortController();
  await assert.rejects(
    client.runTurn(
      {from_wav: '/tmp/q1.wav', reply_wav: '/tmp/a1.wav', defer_reply: true},
      {
        signal: ac.signal,
        onTranscribed: async () => {
          ac.abort(new Error('voice-interrupted'));
          return {action: 'answer', text: 'should not send'};
        },
      }
    ),
    /voice-interrupted/
  );

  const cancelMsg = received.find(m => m.action === 'cancel');
  assert.ok(cancelMsg);
  assert.equal(cancelMsg.id, 1);
  client.recycle();
});

test('CodexLiveSession fences late RPC notifications on disposed/completed turns and cancels stale DataChannel state in runTextTurn', async () => {
  const session = new CodexLiveSession();
  session.child = {};
  session.appReady = Promise.resolve();
  session.threadId = 'thr_sync';
  session.webrtcConnected = true;

  // Seed a disposed turnState from an aborted Turn 1 and emit late Turn 1 RPC deltas
  session.turnState = {
    completed: false,
    disposed: true,
    heard: '',
    heardParts: [],
    heardDelta: '',
    replyParts: [],
    replyDelta: '',
    agentReply: '',
    rpcEvents: [],
    rejectTurn: () => {},
  };
  session.handleRpcLine(JSON.stringify({
    method: 'thread/realtime/itemAdded',
    params: {threadId: 'thr_sync', item: {type: 'message', role: 'assistant', text: 'STALE A1'}},
  }));
  session.handleRpcLine(JSON.stringify({
    method: 'item/agentMessage/delta',
    params: {threadId: 'thr_sync', delta: 'STALE DELTA'},
  }));
  assert.equal(session.turnState.agentReply, '');
  assert.equal(session.turnState.replyParts.length, 0);

  // Now run Turn 2 via runTextTurn and verify codexCancelAndClear + codexResetTurnState(true) happen before polling
  const jsCalls = [];
  let appendedUser = false;
  let pollN = 0;
  session.callRpc = async (method, params) => {
    if (method === 'thread/realtime/appendText' && params.role === 'user') appendedUser = true;
    return {};
  };
  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      if (script.includes('codexState')) {
        if (!appendedUser) {
          return {connected: true, rxPackets: 1, rxEnergy: 0, outRms: 0, micRms: 0, dcReply: '', dcReplyDone: false};
        }
        pollN++;
        if (pollN === 1) {
          return {connected: true, rxPackets: 3, rxEnergy: 0.2, outRms: 0.05, micRms: 0, dcReply: 'FRESH A2', dcReplyDone: false};
        }
        return {connected: true, rxPackets: 3, rxEnergy: 0.2, outRms: 0, micRms: 0, dcReply: 'FRESH A2', dcReplyDone: true};
      }
      return true;
    },
  };
  const origNow = Date.now;
  let fakeTime = 20_000;
  Date.now = () => fakeTime;
  try {
    const turnPromise = session.runTextTurn(wc, {text: 'Pertanyaan dua', unmuteMeet: async () => true});
    const timer = setInterval(() => { fakeTime += 900; }, 10);
    const res = await turnPromise.finally(() => clearInterval(timer));
    assert.equal(res.reply, 'FRESH A2');
  } finally {
    Date.now = origNow;
    session.clearIdleTimer();
  }

  assert.ok(jsCalls.some(s => s.includes('codexCancelAndClear') && s.includes('codexResetTurnState?.(true)')));
});

function createMediaSandbox({
  sampleProvider,
  enableScriptProcessor = true,
  scriptProcessorIntervalMs = 15,
  hostname = 'meet.google.com',
  initialIceGatheringState = 'complete',
} = {}) {
  const source = readFileSync(join(__dirname, '../NAIL/Resources/meet-media.cjs'), 'utf8');
  // Extract installMedia(...) up to helper boundary before isAllowedMediaOrigin
  const endIdx = source.indexOf('\nfunction isAllowedMediaOrigin');
  assert.ok(endIdx > 0);
  const installSrc = `${source.slice(0, endIdx)}\n;installMedia;`;

  let exposedApi = null;
  let currentTimeS = 100;
  const dcSent = [];
  let createdDataChannel = null;
  const createdDelays = [];
  const createdScriptProcessors = [];
  const createdPeers = [];

  class FakeGainNode {
    constructor() { this.gain = {value: 1}; this.disconnected = false; }
    connect() { return this; }
    disconnect() { this.disconnected = true; }
  }
  class FakeAnalyserNode {
    constructor(isMic = false) { this.fftSize = 256; this.isMic = isMic; }
    connect() { return this; }
    disconnect() {}
    getFloatTimeDomainData(buf) {
      if (this.isMic) {
        buf.fill(0);
        return;
      }
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
          for (let i = 0; i < this.bufferSize; i++) {
            chan[i] = next[i % next.length] ?? 0;
          }
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
  class FakeAudioBuffer {
    constructor({length, sampleRate}) {
      this.length = length;
      this.duration = length / sampleRate;
      this.data = new Float32Array(length);
    }
    copyToChannel(src) { this.data.set(src.subarray(0, this.length)); }
    getChannelData() { return this.data; }
  }
  class FakeAudioBufferSourceNode {
    constructor() {
      this.buffer = null;
      this.onended = null;
      this.offset = {value: 0};
    }
    connect() { return this; }
    disconnect() {}
    start() { setTimeout(() => this.onended?.(), 10); }
    stop() {}
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
    createDelay() {
      const node = {delayTime: {value: 0}, connect() { return this; }, disconnect() {}};
      createdDelays.push(node);
      return node;
    }
    createConstantSource() { return {offset: {value: 0}, connect() { return this; }, disconnect() {}, start() {}, stop() {}}; }
    createAnalyser() { return new FakeAnalyserNode(false); }
    createMediaStreamDestination() { return new FakeMediaStreamDestination(); }
    createMediaStreamSource() { return {connect() {}, disconnect() {}}; }
    createBuffer(_ch, length, sampleRate) { return new FakeAudioBuffer({length, sampleRate}); }
    createBufferSource() { return new FakeAudioBufferSourceNode(); }
    decodeAudioData(arr) {
      return Promise.resolve({
        sampleRate: 48000,
        length: 960,
        numberOfChannels: 1,
        duration: 0.02,
        byteLength: arr.byteLength,
        getChannelData: () => new Float32Array(960),
      });
    }
  }
  if (enableScriptProcessor) {
    FakeAudioContext.prototype.createScriptProcessor = function (bufferSize = 2048) {
      return new FakeScriptProcessorNode(bufferSize);
    };
  }

  class FakeMediaStream {
    constructor(tracks = []) {
      this._tracks = tracks;
      this.id = 'stream-1';
    }
    getTracks() { return this._tracks; }
    getAudioTracks() { return this._tracks.filter(t => t.kind === 'audio'); }
    addTrack(t) { this._tracks.push(t); }
    clone() { return new FakeMediaStream([...this._tracks]); }
  }

  class FakeMediaRecorder {
    constructor() {
      this.state = 'inactive';
      this.ondataavailable = null;
      this.onstop = null;
      this._timer = null;
    }
    start(timeslice = 120) {
      this.state = 'recording';
      this._timer = setInterval(() => {
        if (this.state === 'recording') {
          this.ondataavailable?.({data: new Blob([new Uint8Array([1, 2, 3, 4])])});
        }
      }, timeslice);
    }
    stop() {
      if (this._timer) clearInterval(this._timer);
      this.state = 'inactive';
      this.onstop?.();
    }
  }

  class FakeDataChannel extends EventEmitter {
    constructor(label) {
      super();
      this.label = label;
      this.readyState = 'open';
      createdDataChannel = this;
      setTimeout(() => this.onopen?.(), 1);
    }
    send(payload) { dcSent.push(JSON.parse(payload)); }
    close() { this.readyState = 'closed'; }
    addEventListener(type, fn) { this.on(type, fn); }
    emitMessage(obj) {
      const ev = {data: JSON.stringify(obj)};
      this.onmessage?.(ev);
      this.emit('message', ev);
    }
  }

  class FakeRTCPeerConnection extends EventEmitter {
    constructor() {
      super();
      this.connectionState = 'connected';
      this.iceConnectionState = 'connected';
      this.iceGatheringState = initialIceGatheringState;
      this._senders = [];
      createdPeers.push(this);
    }
    addTrack() {}
    createDataChannel(label) { return new FakeDataChannel(label); }
    createOffer() { return Promise.resolve({sdp: 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n', type: 'offer'}); }
    setLocalDescription(d) { this.localDescription = d; return Promise.resolve(); }
    setRemoteDescription(d) { this.remoteDescription = d; return Promise.resolve(); }
    close() { this.connectionState = 'closed'; }
    getStats() { return Promise.resolve(new Map()); }
    getSenders() { return this._senders; }
    getTransceivers() { return []; }
    addEventListener(type, fn) { this.on(type, fn); }
    removeEventListener(type, fn) { this.off(type, fn); }
  }

  const remoteTrack = {
    id: 'r1',
    kind: 'audio',
    readyState: 'live',
    enabled: true,
    stop() {},
    addEventListener() {},
  };
  const FakeMediaStreamTrack = class {};
  FakeMediaStreamTrack.prototype.clone = function () {
    return makeFakeTrack(`${this.id || 'trk'}-clone`);
  };
  const windowObj = {
    location: {hostname, origin: `https://${hostname}`},
    AudioContext: FakeAudioContext,
    Audio: class FakeAudio {
      constructor() { this.muted = false; this.srcObject = null; }
      play() { return Promise.resolve(); }
      pause() {}
    },
    MediaStream: FakeMediaStream,
    MediaStreamTrack: FakeMediaStreamTrack,
    MediaRecorder: FakeMediaRecorder,
    RTCPeerConnection: FakeRTCPeerConnection,
    HTMLMediaElement: {prototype: {}},
    navigator: {mediaDevices: {
      getUserMedia: () => Promise.resolve(new FakeMediaStream([])),
      enumerateDevices: () => Promise.resolve([]),
    }},
    document: {createElement: () => ({})},
    btoa: s => Buffer.from(s, 'binary').toString('base64'),
    atob: s => Buffer.from(s, 'base64').toString('binary'),
    Blob,
    FileReader: class FakeFileReader {
      readAsDataURL(blob) {
        blob.arrayBuffer().then(ab => {
          this.result = `data:audio/webm;base64,${Buffer.from(ab).toString('base64')}`;
          this.onloadend?.();
        });
      }
    },
    crypto: {getRandomValues: arr => arr},
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    Date,
    Math,
    Promise,
    Error,
    Set,
    Map,
    Uint8Array,
    Int16Array,
    Float32Array,
    Object,
    Array,
    Number,
    String,
    Boolean,
    JSON,
    console,
    addRemoteStreamForTest: null,
  };
  Object.defineProperty(windowObj.HTMLMediaElement.prototype, 'srcObject', {
    configurable: true,
    set(v) { this._src = v; },
    get() { return this._src ?? null; },
  });
  windowObj.window = windowObj;
  windowObj.self = windowObj;
  const ctx = vm.createContext(windowObj);
  const installFn = vm.runInContext(installSrc, ctx);
  installFn(false);
  exposedApi = windowObj.__nailMedia;
  const meetPc = new windowObj.RTCPeerConnection();
  meetPc.emit('track', {track: remoteTrack});

  return {
    windowObj,
    api: exposedApi,
    meetPc,
    dcSent,
    createdDelays,
    createdScriptProcessors,
    createdPeers,
    makeFakeTrack,
    getDataChannel: () => createdDataChannel,
  };
}

test('meet-media.cjs aborts click false-starts early (<600ms) instead of stalling 8s in autoListen', async () => {
  let frame = 0;
  const sandbox = createMediaSandbox({
    sampleProvider: () => {
      frame++;
      // Frames 1..2: brief click spike (rms ~ 0.03); Frames 3+: pure quiet room noise (0.0004)
      const val = frame <= 2 ? 0.03 : 0.0004;
      return new Float32Array(256).fill(val);
    },
  });

  const startedAt = Date.now();
  const clip = await sandbox.api.record(8000, true, 12000);
  const elapsed = Date.now() - startedAt;

  assert.equal(clip, '');
  assert.ok(elapsed < 1200, `Expected early click abort well under 1.2s, got ${elapsed}ms`);
});

test('meet-media.cjs __nailUpgradeRecord returns true and immediately starts recording for manual Dengar & Jawab', async () => {
  const sandbox = createMediaSandbox({
    sampleProvider: () => new Float32Array(256).fill(0.0003),
  });

  const recordPromise = sandbox.api.record(8000, true, 12000);
  await new Promise(r => setTimeout(r, 30));
  const upgraded = sandbox.windowObj.__nailUpgradeRecord?.();
  assert.equal(upgraded, true);
  sandbox.windowObj.__nailAbortRecord?.();
  const clip = await recordPromise;
  assert.equal(clip, '');
});

test('meet-media.cjs manual record waits past milliseconds when user pauses before speaking (idleWaitMs)', async () => {
  const sandbox = createMediaSandbox({
    sampleProvider: () => new Float32Array(256).fill(0.0002),
  });
  // milliseconds=300ms, idleWaitMs=650ms: if user stays silent, recorder must NOT stop early at 300ms
  const startedAt = Date.now();
  const clip = await sandbox.api.record(300, false, 650);
  const elapsed = Date.now() - startedAt;
  assert.equal(clip, '');
  assert.ok(elapsed >= 550, `Expected manual idle wait >= 550ms (idleWaitMs=650), got ${elapsed}ms`);
});

test('meet-media.cjs codexWaitUserSpeech ignores single-frame moderate click and stays muted', async () => {
  let frame = 0;
  const sandbox = createMediaSandbox({
    sampleProvider: () => {
      frame++;
      // Single brief tick at 0.009 (below 0.015 spike), then pure silence
      const val = frame === 2 ? 0.009 : 0.0003;
      return new Float32Array(256).fill(val);
    },
  });
  await sandbox.api.codexConnect();
  const res = await sandbox.api.codexWaitUserSpeech(320, 1000, 240);
  assert.equal(res.spoke, false);
  assert.deepEqual(sandbox.dcSent, []);
  sandbox.api.codexDisconnect();
});

test('meet-media.cjs DataChannel ignores stale events outside active turn and drops cancelled response IDs', async () => {
  let rmsVal = 0.0003;
  const sandbox = createMediaSandbox({
    sampleProvider: () => new Float32Array(256).fill(rmsVal),
  });

  const sdp = await sandbox.api.codexConnect();
  assert.ok(sdp.includes('m=audio'));
  await new Promise(r => setTimeout(r, 15));
  const dc = sandbox.getDataChannel();
  assert.ok(dc);

  // Before turn starts: dcAcceptingTurn is false -> late transcripts MUST be ignored
  dc.emitMessage({type: 'response.output_audio_transcript.delta', response_id: 'resp_old', delta: 'STALE ECHO'});
  let state = await sandbox.api.codexState();
  assert.equal(state.dcReply, '');

  // Start text turn cleanly: enables dcAcceptingTurn
  sandbox.api.codexResetTurnState(true);
  dc.emitMessage({type: 'response.created', response: {id: 'resp_1'}});
  dc.emitMessage({type: 'response.output_audio_transcript.delta', response_id: 'resp_1', delta: 'Halo '});
  state = await sandbox.api.codexState();
  assert.equal(state.dcReply, 'Halo');

  // Fence the old response locally without sending unsupported Realtime v3 events.
  sandbox.api.codexCancelAndClear();
  dc.emitMessage({type: 'response.output_audio_transcript.delta', response_id: 'resp_1', delta: 'TAIL LAMA'});
  state = await sandbox.api.codexState();
  assert.equal(state.dcReply, '');
  assert.deepEqual(sandbox.dcSent, []);

  // Re-enable turn 2: resp_1 late event STILL blocked by cancelledResponseIds, while resp_2 succeeds!
  sandbox.api.codexResetTurnState(true);
  dc.emitMessage({type: 'response.created', response: {id: 'resp_2'}});
  dc.emitMessage({type: 'response.output_audio_transcript.delta', response_id: 'resp_1', delta: 'LEAK R1'});
  dc.emitMessage({type: 'response.output_audio_transcript.delta', response_id: 'resp_2', delta: 'Jawaban dua'});
  dc.emitMessage({type: 'response.done', response: {id: 'resp_2', status: 'completed'}});
  state = await sandbox.api.codexState();
  assert.equal(state.dcReply, 'Jawaban dua');
  assert.equal(state.dcReplyDone, true);
  assert.equal(state.serverResponseInFlight, false);

  sandbox.api.codexCancelAndClear();
  assert.deepEqual(sandbox.dcSent, []);
  sandbox.api.codexDisconnect();
});

test('CodexLiveSession ignores benign cancellation errors and avoids splitting in-flight replies', () => {
  const session = new CodexLiveSession();
  session.webrtcConnected = true;
  let rejected = null;
  session.turnState = {
    completed: false,
    disposed: false,
    rpcEvents: [],
    rejectTurn: err => { rejected = err; },
  };
  session.handleRpcLine(JSON.stringify({
    method: 'thread/realtime/error',
    params: {message: 'Cancellation failed: no active response found'},
  }));
  assert.equal(rejected, null);
  assert.equal(session.webrtcConnected, true);

  // shouldCompleteTurn must NOT cut off a 1.1s mid-reply pause while serverResponseInFlight is still true
  const state = {outSpoke: true, delegationActive: false, awaitingPostDelegation: false, replyParts: ['Baik.'], replyDelta: ''};
  assert.equal(
    CodexLiveSession.shouldCompleteTurn(state, 5, 1000, 2100, {dcReplyDone: false, serverResponseInFlight: true}),
    false
  );
  assert.equal(
    CodexLiveSession.shouldCompleteTurn(state, 5, 1000, 1600, {dcReplyDone: true, serverResponseInFlight: false}),
    true
  );
});

test('meet-media.cjs codexConnect sets inPreRoll=0.10, outDelay=0.015, and uses 150ms srflx ICE timer', async () => {
  const sandbox = createMediaSandbox({
    sampleProvider: () => new Float32Array(256).fill(0),
    initialIceGatheringState: 'gathering',
  });

  const startedAt = Date.now();
  const connectPromise = sandbox.api.codexConnect();
  await new Promise(r => setTimeout(r, 10));
  const codexPc = sandbox.createdPeers[sandbox.createdPeers.length - 1];
  assert.ok(codexPc);
  codexPc.onicecandidate?.({candidate: {candidate: 'candidate:1 1 UDP 123 1.2.3.4 9999 typ srflx', type: 'srflx'}});
  const sdp = await connectPromise;
  const elapsed = Date.now() - startedAt;

  assert.ok(sdp.includes('m=audio'));
  assert.ok(elapsed < 280, `Expected srflx ICE gathering timer (~150ms) to finish well under 280ms, got ${elapsed}ms`);
  assert.equal(sandbox.createdDelays.length, 2);
  assert.equal(sandbox.createdDelays[0].delayTime.value, 0.10);
  assert.equal(sandbox.createdDelays[1].delayTime.value, 0.015);
  sandbox.api.codexDisconnect();
});

test('meet-media.cjs codexWaitUserSpeech uses 40ms poll, 350ms default silence, and returns speechEndedAtMs and silenceWaitMs', async () => {
  let frame = 0;
  const sandbox = createMediaSandbox({
    sampleProvider: () => {
      frame++;
      // Frames 1..3: speech (0.04); Frames 4+: silence (0.0003)
      const val = frame <= 3 ? 0.04 : 0.0003;
      return new Float32Array(256).fill(val);
    },
  });

  await sandbox.api.codexConnect();
  const startedAt = Date.now();
  // Use default silenceMs (350ms -> 9 ticks at 40ms = ~360ms after 3 speech ticks = ~480ms total)
  const res = await sandbox.api.codexWaitUserSpeech(2000, 3000);
  const finishedAt = Date.now();

  assert.equal(res.spoke, true);
  assert.equal(res.aborted, false);
  assert.ok(res.speechEndedAtMs >= startedAt && res.speechEndedAtMs <= finishedAt);
  assert.ok(res.silenceWaitMs >= 280 && res.silenceWaitMs <= 650, `Expected silenceWaitMs ~350ms, got ${res.silenceWaitMs}ms`);
  assert.ok(finishedAt - startedAt < 850, `Expected 40ms poll + 350ms default silence to finish under 850ms, got ${finishedAt - startedAt}ms`);
  sandbox.api.codexDisconnect();
});

test('meet-media.cjs codexRecordWakePcm downsamples 48kHz to 16kHz Int16le PCM and retains ~200ms pre-roll', async () => {
  let chunkIdx = 0;
  const sandbox = createMediaSandbox({
    scriptProcessorIntervalMs: 10,
    sampleProvider: () => {
      chunkIdx++;
      // Chunks 1..2: quiet pre-roll with known non-zero marker value 0.002 (below onset threshold 0.0055)
      if (chunkIdx <= 2) return new Float32Array(2048).fill(0.002);
      // Chunks 3..6: speech at 0.25 (4 voiced chunks >= 3)
      if (chunkIdx <= 6) return new Float32Array(2048).fill(0.25);
      // Chunks 7+: silence
      return new Float32Array(2048).fill(0.0002);
    },
  });

  const res = await sandbox.api.codexRecordWakePcm(4000, 4000, 180);
  assert.ok(res, 'Expected non-null PCM result');
  assert.equal(res.sampleRate, 16000);
  assert.ok(typeof res.pcmBase64 === 'string' && res.pcmBase64.length > 0);
  assert.ok(typeof res.speechEndedAtMs === 'number' && res.speechEndedAtMs > 0);
  assert.ok(typeof res.silenceWaitMs === 'number' && res.silenceWaitMs >= 0);
  assert.ok(res.durationMs > 200);

  const rawBytes = Buffer.from(res.pcmBase64, 'base64');
  assert.equal(rawBytes.length % 2, 0);
  const sampleCount = rawBytes.length / 2;
  const int16 = new Int16Array(sampleCount);
  for (let i = 0; i < sampleCount; i++) {
    int16[i] = rawBytes.readInt16LE(i * 2);
  }

  // First samples come from the 2 pre-roll chunks (0.002 * 32767 ≈ 66)
  const expectedPreRoll = Math.round(0.002 * 32767);
  assert.equal(int16[0], expectedPreRoll);
  // Voiced samples after the 2 pre-roll chunks (2 * 2048 / 3 = 1365 samples) must match 0.25 * 32767 = 8192
  const expectedVoiced = Math.round(0.25 * 32767);
  assert.equal(int16[1400], expectedVoiced);

  // Verify ScriptProcessorNode was cleanly disconnected in finally
  assert.equal(sandbox.createdScriptProcessors.length, 1);
  assert.equal(sandbox.createdScriptProcessors[0].disconnected, true);
});

test('meet-media.cjs codexRecordWakePcm aborts early on click false-start and resolves null', async () => {
  let chunkIdx = 0;
  const sandbox = createMediaSandbox({
    scriptProcessorIntervalMs: 10,
    sampleProvider: () => {
      chunkIdx++;
      // Chunks 1..2: brief click spike (0.03), then quiet background (0.0003)
      return new Float32Array(2048).fill(chunkIdx <= 2 ? 0.03 : 0.0003);
    },
  });

  const res = await sandbox.api.codexRecordWakePcm(8000, 12000, 450);
  assert.equal(res, null);
  assert.ok(chunkIdx <= 10, `Expected early click abort within ~6 chunks, got ${chunkIdx}`);
  assert.equal(sandbox.createdScriptProcessors[0].disconnected, true);
});

test('meet-media.cjs codexRecordWakePcm respects window.__nailAbortRecord() cancellation', async () => {
  const sandbox = createMediaSandbox({
    scriptProcessorIntervalMs: 15,
    sampleProvider: () => new Float32Array(2048).fill(0.0003),
  });

  const promise = sandbox.api.codexRecordWakePcm(8000, 12000, 450);
  await new Promise(r => setTimeout(r, 35));
  assert.equal(typeof sandbox.windowObj.__nailAbortRecord, 'function');
  sandbox.windowObj.__nailAbortRecord();
  const res = await promise;
  assert.equal(res, null);
  assert.equal(sandbox.createdScriptProcessors[0].disconnected, true);
});

test('meet-media.cjs codexRecordWakePcm falls back to record() when createScriptProcessor is unavailable', async () => {
  let chunkIdx = 0;
  const sandbox = createMediaSandbox({
    enableScriptProcessor: false,
    sampleProvider: () => {
      chunkIdx++;
      return new Float32Array(256).fill(chunkIdx <= 2 ? 0.03 : 0.0004);
    },
  });

  const res = await sandbox.api.codexRecordWakePcm(8000, 12000, 450);
  assert.equal(res, '');
  assert.equal(sandbox.createdScriptProcessors.length, 0);
});

test('meet-media.cjs codexCloseOut({keepTeamsSenders: true}) keeps Teams virtual senders until restoreTeamsSenders()', async () => {
  const sandbox = createMediaSandbox({
    hostname: 'teams.microsoft.com',
    sampleProvider: () => new Float32Array(256).fill(0),
  });

  const origTrack = sandbox.makeFakeTrack('teams-orig-mic');
  const sender = {
    track: origTrack,
    async replaceTrack(next) {
      this.track = next;
    },
  };
  sandbox.meetPc._senders.push(sender);

  await sandbox.api.codexConnect();
  await sandbox.api.codexOpenOut();
  assert.notEqual(sender.track, origTrack, 'Expected Teams sender track to be replaced with virtual track');
  let diag = await sandbox.api.micOutDiag();
  assert.equal(diag.outGain, 1);
  assert.equal(diag.replacedActive, 1);

  await sandbox.api.codexCloseOut({keepTeamsSenders: true});
  diag = await sandbox.api.micOutDiag();
  assert.equal(diag.outGain, 0);
  assert.equal(diag.replacedActive, 1, 'Expected Teams virtual sender to remain active when keepTeamsSenders is true');
  assert.notEqual(sender.track, origTrack);

  await sandbox.api.restoreTeamsSenders();
  diag = await sandbox.api.micOutDiag();
  assert.equal(diag.replacedActive, 0);
  assert.equal(sender.track, origTrack, 'Expected restoreTeamsSenders() to restore original Teams track');

  // Verify default codexCloseOut() restores Teams senders automatically
  await sandbox.api.codexOpenOut();
  assert.notEqual(sender.track, origTrack);
  await sandbox.api.codexCloseOut();
  assert.equal(sender.track, origTrack);
  sandbox.api.codexDisconnect();
});
