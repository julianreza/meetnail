// Synthetic Indonesian voice round trip with Codex Live Voice (ChatGPT sign-in, no API key).
// Plays the reply on the default output device and measures time to first audible reply frame.
import { chromium } from 'playwright';
import { spawn, execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';

const QUESTION = 'Jawab dalam bahasa Indonesia. Berapa dua tambah dua?';
const dir = mkdtempSync(join(tmpdir(), 'nail-voice-'));
let browser, proc, timer;

const fail = (message) => {
  throw new Error(message);
};

async function main() {
  timer = setTimeout(() => { proc?.kill(); fail('global timeout'); }, 70000);
  const clip = join(dir, 'question.aiff');
  execFileSync('say', ['-v', 'Damayanti', '-o', clip, QUESTION]);
  const wav = execFileSync('ffmpeg', ['-v', 'error', '-i', clip, '-ac', '1', '-ar', '48000', '-f', 'wav', '-']).toString('base64');

  browser = await chromium.launch({ channel: 'chrome', args: ['--autoplay-policy=no-user-gesture-required'] });
  const page = await browser.newPage();
  const sdp = await page.evaluate(async (wav) => {
    const pc = (window.pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] }));
    const ctx = (window.ctx = new AudioContext({ sampleRate: 48000 }));
    await ctx.resume();
    const source = (window.source = ctx.createBufferSource());
    const toPeer = ctx.createMediaStreamDestination();
    source.buffer = await ctx.decodeAudioData(Uint8Array.from(atob(wav), (c) => c.charCodeAt(0)).buffer);
    source.connect(toPeer);
    pc.addTrack(toPeer.stream.getAudioTracks()[0]);
    pc.createDataChannel('oai-events');
    window.reply = null;
    window.startedAt = 0;
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === 'connected' && !window.startedAt) {
        window.startedAt = ctx.currentTime;
        source.start(ctx.currentTime + 0.6);
      }
    };
    pc.ontrack = ({ track }) => {
      const reply = (window.reply = new Audio());
      reply.srcObject = new MediaStream([track]);
      reply.play();
    };
    await pc.setLocalDescription(await pc.createOffer());
    if (pc.iceGatheringState !== 'complete') {
      await new Promise((resolve) => {
        pc.addEventListener('icegatheringstatechange', () => pc.iceGatheringState === 'complete' && resolve());
        setTimeout(resolve, 4500);
      });
    }
    return pc.localDescription.sdp;
  }, wav);

  const env = { ...process.env };
  delete env.OPENAI_API_KEY;
  delete env.CODEX_API_KEY;
  proc = spawn('codex', ['app-server', '-c', 'approval_policy="never"', '-c', 'sandbox_mode="read-only"'],
    { cwd: dir, env, stdio: ['pipe', 'pipe', 'ignore'] });

  let id = 0, heard = false, answered = false, error = null, firstEnergyAt = 0;
  const pending = new Map();
  createInterface({ input: proc.stdout }).on('line', (line) => {
    const message = JSON.parse(line);
    const params = message.params ?? {};
    if (pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    }
    if (message.method === 'thread/realtime/sdp') {
      page.evaluate((sdp) => pc.setRemoteDescription({ sdp, type: 'answer' }), params.sdp).catch((e) => (error = e));
    }
    if (message.method === 'thread/realtime/error') error = new Error(params.message);
    if (message.method === 'thread/realtime/transcript/done') {
      console.log(`${params.role}: ${params.text.trim()}`);
      if (params.role === 'user') heard ||= /tambah|2\s*\+\s*2/i.test(params.text);
      if (params.role === 'assistant') answered ||= /empat|\b4\b/i.test(params.text);
    }
  });

  const send = (method, params, requestId) =>
    proc.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id: requestId, method, params })}\n`);
  const call = (method, params) => new Promise((resolve, reject) => {
    const requestId = ++id;
    pending.set(requestId, (m) => (m.error ? reject(new Error(m.error.message)) : resolve(m.result)));
    send(method, params, requestId);
  });

  await call('initialize', { clientInfo: { name: 'nail_voice', version: '0.1.0' }, capabilities: { experimentalApi: true } });
  send('initialized', {}, 0);
  const auth = await call('getAuthStatus', { includeToken: false });
  if (auth.authMethod !== 'chatgpt') fail(`expected chatgpt auth, got ${auth.authMethod}`);
  const { thread } = await call('thread/start', { cwd: dir, ephemeral: true, sandbox: 'read-only', approvalPolicy: 'never' });
  await call('thread/realtime/start', {
    threadId: thread.id, version: 'v3', model: 'gpt-live-1-codex', voice: 'cove',
    outputModality: 'audio', includeStartupContext: false, clientManagedHandoffs: true,
    transport: { type: 'webrtc', sdp },
  });

  const probe = async () => page.evaluate(async () => {
    const audio = (await pc.getStats()).values();
    const inbound = [...audio].find((s) => s.type === 'inbound-rtp' && s.kind === 'audio');
    return {
      status: pc.connectionState,
      energy: inbound?.totalAudioEnergy ?? 0,
      packets: inbound?.packetsReceived ?? 0,
      questionEndsAt: window.source?.buffer ? window.startedAt + 0.6 + window.source.buffer.duration : 0,
      now: window.ctx?.currentTime ?? 0,
    };
  });

  let questionEnded = 0;
  for (let tick = 0; tick < 32; tick++) {
    if (error) throw error;
    await new Promise((resolve) => setTimeout(resolve, 500));
    const state = await probe();
    if (!firstEnergyAt && state.energy > 0.001) firstEnergyAt = state.now;
    if (state.status === 'connected' && state.questionEndsAt && !questionEnded) {
      questionEnded = state.questionEndsAt;
      console.log(`question sent, ends at t=${questionEnded.toFixed(2)}s`);
    }
    if (heard && answered && firstEnergyAt) {
      const latency = firstEnergyAt - questionEnded;
      console.log(`PASS: audible reply ${latency.toFixed(2)}s after the question ended (${state.packets} packets)`);
      await call('thread/realtime/stop', { threadId: thread.id });
      return;
    }
  }
  fail(`no verified round trip (heard=${heard}, answered=${answered}, energy=${firstEnergyAt > 0})`);
}

try {
  await main();
  process.exitCode = 0;
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
} finally {
  clearTimeout(timer);
  proc?.kill();
  await browser?.close();
  rmSync(dir, { recursive: true, force: true });
}
