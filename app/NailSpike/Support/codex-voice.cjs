const { BrowserWindow } = require('electron');
const { spawn } = require('node:child_process');
const { mkdtemp, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { createInterface } = require('node:readline');
const { setTimeout: delay } = require('node:timers/promises');

async function prepare(clip) {
  const pc = new RTCPeerConnection({iceServers: [{urls: 'stun:stun.l.google.com:19302'}]});
  const ctx = new AudioContext({sampleRate: 48000});
  await ctx.resume();
  const wav = Uint8Array.from(atob(clip), c => c.charCodeAt(0));
  const question = ctx.createBufferSource();
  question.buffer = await ctx.decodeAudioData(wav.buffer);
  const destination = ctx.createMediaStreamDestination();
  question.connect(destination);
  pc.addTrack(destination.stream.getAudioTracks()[0]);
  pc.createDataChannel('oai-events');
  let started = false;
  let recorder, chunks = [];
  const meter = ctx.createAnalyser();
  const buffer = new Float32Array(meter.fftSize);
  const recorded = ctx.createMediaStreamDestination();
  meter.connect(recorded);
  let peak = 0;
  pc.onconnectionstatechange = () => {
    if (pc.connectionState !== 'connected' || started) return;
    started = true;
    question.start(ctx.currentTime + 0.6);
  };
  pc.ontrack = ({track}) => {
    if (track.kind !== 'audio' || recorder) return;
    const stream = new MediaStream([track]);
    const audio = new Audio();
    audio.muted = true;
    audio.srcObject = stream;
    window.replyAudio = audio;
    audio.play().catch(() => {});
    ctx.createMediaStreamSource(stream).connect(meter);
    recorder = new MediaRecorder(recorded.stream, {mimeType: 'audio/webm;codecs=opus'});
    recorder.ondataavailable = e => chunks.push(e.data);
    recorder.start();
  };
  window.nailCodex = {
    answer: sdp => pc.setRemoteDescription({type: 'answer', sdp}),
    energy: async () => {
      const stats = [...(await pc.getStats()).values()];
      const audio = stats.find(r => r.type === 'inbound-rtp' && r.kind === 'audio');
      meter.getFloatTimeDomainData(buffer);
      const rms = Math.sqrt(buffer.reduce((sum, x) => sum + x*x, 0) / buffer.length);
      peak = Math.max(peak, rms);
      return {level: audio?.totalAudioEnergy ?? 0, packets: audio?.packetsReceived ?? 0, rms, peak,
        connected: pc.connectionState === 'connected'};
    },
    finish: async () => {
      if (!recorder || recorder.state !== 'recording') throw new Error('voice-no-reply');
      await new Promise(resolve => { recorder.onstop = resolve; recorder.stop(); });
      const bytes = new Uint8Array(await new Blob(chunks).arrayBuffer());
      let binary = '';
      for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
      return btoa(binary);
    },
  };
  await pc.setLocalDescription(await pc.createOffer());
  await new Promise(resolve => {
    if (pc.iceGatheringState === 'complete') return resolve();
    const timer = setTimeout(resolve, 4500);
    pc.onicegatheringstatechange = () => {
      if (pc.iceGatheringState === 'complete') { clearTimeout(timer); resolve(); }
    };
  });
  return pc.localDescription.sdp;
}

function classify(message) {
  return /usage limit|rate limit|quota|too many requests|\b429\b/i.test(message) ? 'voice-codex-quota' : 'voice-codex-error';
}

async function codexVoice(clip, signal, progress = () => {}) {
  const cwd = await mkdtemp(join(tmpdir(), 'nail-codex-'));
  let win, child;
  const pending = new Map();
  let deadline, transportError;
  let heard = '', reply = '';
  let connected = false;
  let rejectTurn;
  const interrupted = new Promise((_resolve, reject) => { rejectTurn = reject; });
  let sequence = 0;
  const abort = () => {
    child?.kill();
    if (win && !win.isDestroyed()) win.destroy();
  };
  const cancel = () => rejectTurn(signal.reason);
  signal.addEventListener('abort', cancel, {once: true});
  const run = async () => {
    signal.throwIfAborted();
    const env = {...process.env};
    for (const key of ['OPENAI_API_KEY', 'CODEX_API_KEY', 'OPENAI_BASE_URL', 'CODEX_BASE_URL']) delete env[key];
    env.PATH = `/opt/homebrew/bin:/usr/local/bin:${env.HOME}/.local/bin:${env.PATH ?? '/usr/bin:/bin'}`;
    child = spawn('codex', ['app-server', '-c', 'forced_login_method="chatgpt"',
      '-c', 'approval_policy="never"', '-c', 'sandbox_mode="read-only"'],
    {cwd, env, stdio: ['pipe', 'pipe', 'ignore']});
    const fail = error => {
      transportError = error;
      for (const {reject} of pending.values()) reject(error);
      pending.clear();
      rejectTurn(error);
    };
    child.on('error', error => fail(new Error(error.code === 'ENOENT' ? 'voice-codex-missing' : 'voice-codex-error')));
    child.on('exit', () => { if (!transportError) fail(new Error('voice-codex-error')); });
    child.stdin.on('error', () => { if (!transportError) fail(new Error('voice-codex-error')); });
    deadline = setTimeout(() => rejectTurn(new Error(heard ? 'voice-codex-timeout' :
      connected ? 'voice-codex-no-transcript' : 'voice-codex-connection')), 50_000);
    const execute = (method, value) => win.webContents.executeJavaScript(`nailCodex.${method}(${value === undefined ? '' : JSON.stringify(value)})`, true);
    createInterface({input: child.stdout}).on('line', line => {
      let message;
      try { message = JSON.parse(line); } catch { return; }
      const request = pending.get(message.id);
      const params = message.params ?? {};
      if (request) {
        pending.delete(message.id);
        if (message.error) request.reject(new Error(classify(message.error.message ?? '')));
        else request.resolve(message.result);
      } else if (message.method === 'thread/realtime/sdp') {
        execute('answer', params.sdp).catch(() => fail(new Error('voice-codex-error')));
      } else if (message.method === 'thread/realtime/error') {
        fail(new Error(classify(params.message ?? '')));
      } else if (message.method === 'thread/realtime/transcript/done') {
        if (typeof params.text !== 'string') return;
        if (params.role === 'user') {
          if (!heard && params.text.trim()) progress('voice-codex-heard');
          heard = params.text;
        }
        if (params.role === 'assistant') reply = params.text;
      }
    });
    const send = (method, params, id) => child.stdin.write(`${JSON.stringify({jsonrpc: '2.0', id, method, params})}\n`);
    const call = (method, params) => new Promise((resolve, reject) => {
      if (transportError) return reject(transportError);
      const id = ++sequence;
      pending.set(id, {resolve, reject});
      send(method, params, id);
    });
    await call('initialize', {clientInfo: {name: 'nail_voice', version: '0.1.0'}, capabilities: {experimentalApi: true}});
    send('initialized', {}, undefined);
    const auth = await call('getAuthStatus', {includeToken: false});
    if (auth.authMethod !== 'chatgpt') throw new Error('voice-codex-login');
    progress('voice-codex-connecting');
    const {thread} = await call('thread/start', {cwd, ephemeral: true, sandbox: 'read-only', approvalPolicy: 'never'});
    win = new BrowserWindow({show: false, webPreferences: {sandbox: true, backgroundThrottling: false}});
    win.webContents.setAudioMuted(true);
    await win.loadURL('data:text/html,<title>Nail Codex Voice</title>');
    const sdp = await win.webContents.executeJavaScript(`(${prepare})(${JSON.stringify(clip)})`, true);
    await call('thread/realtime/start', {threadId: thread.id, version: 'v3', model: 'gpt-live-1-codex', voice: 'cove',
      outputModality: 'audio', includeStartupContext: false, clientManagedHandoffs: true,
      transport: {type: 'webrtc', sdp}});
    let energy = 0, changed = 0;
    while (!signal.aborted && !transportError) {
      const state = await execute('energy');
      const {level, packets, rms, peak} = state;
      if (!connected && state.connected) { connected = true; progress('voice-codex-listening'); }
      if (level > energy + 0.00001 || rms > 0.004) changed = Date.now();
      energy = level;
      if (heard && reply && packets > 0 && (energy > 0.001 || peak > 0.004) && Date.now() - changed >= 850) {
        const audio = await execute('finish');
        return {heard, reply, audio};
      }
      await delay(150, undefined, {signal});
    }
    throw transportError ?? new Error('voice-codex-error');
  };
  try {
    return await Promise.race([run(), interrupted]);
  } catch (error) {
    throw transportError ?? error;
  } finally {
    clearTimeout(deadline);
    signal.removeEventListener('abort', cancel);
    for (const {reject} of pending.values()) reject(new Error('voice-codex-error'));
    pending.clear();
    abort();
    await rm(cwd, {recursive: true, force: true});
  }
}

module.exports = {codexVoice};
