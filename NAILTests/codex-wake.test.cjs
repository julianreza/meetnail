const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');
const {createMeetingNotesMemory} = require('../NAIL/Resources/meet.cjs');
const {
  CodexLiveSession,
  INDONESIAN_PRONUNCIATION_GUIDE,
  STYLE_PROMPTS,
  resolveStylePrompt,
} = require('../NAIL/Resources/codex-voice.cjs');

test('CodexLiveSession.runTextTurn resets turn state, syncs notes, appends user text, and cleans up', async t => {
  const memory = createMeetingNotesMemory();
  const baseMs = new Date(2026, 10, 21, 14, 0, 0).getTime();
  memory.addEntry({text: 'Keputusan awal: rilis hari Jumat.', speaker: 'Rina', timestampMs: baseMs});

  const session = new CodexLiveSession({notesMemory: memory});
  t.after(() => session.clearIdleTimer());
  session.child = {};
  session.appReady = Promise.resolve();
  session.threadId = 'thr_wake_1';
  session.webrtcConnected = true;

  const rpcCalls = [];
  const jsCalls = [];
  const progressEvents = [];
  let unmuteCalled = 0;
  let pollCount = 0;
  let appendedUserText = false;

  session.callRpc = async (method, params) => {
    rpcCalls.push({method, params});
    if (method === 'thread/realtime/appendText' && params.role === 'user') {
      appendedUserText = true;
    }
    return {};
  };

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      if (script.includes('codexState')) {
        if (!appendedUserText) {
          return {
            connected: true,
            rxPackets: 10,
            rxEnergy: 0.1,
            outRms: 0,
            micRms: 0,
            dcReply: '',
            dcReplyDone: false,
            dcEvents: [],
          };
        }
        pollCount++;
        if (pollCount === 1) {
          return {
            connected: true,
            rxPackets: 15,
            rxEnergy: 0.25,
            outRms: 0.05,
            micRms: 0.01,
            dcReply: 'Siap, rilis tetap Jumat.',
            dcReplyDone: false,
            dcEvents: ['response.output_audio_transcript.delta'],
          };
        }
        // Wait >= 800ms after lastAudioAt so shouldCompleteTurn triggers with dcReplyDone: true
        await new Promise(resolve => setTimeout(resolve, 850));
        return {
          connected: true,
          rxPackets: 20,
          rxEnergy: 0.25,
          outRms: 0,
          micRms: 0,
          dcReply: 'Siap, rilis tetap Jumat.',
          dcReplyDone: true,
          dcEvents: ['response.done'],
        };
      }
      return null;
    },
  };

  const result = await session.runTextTurn(wc, {
    text: 'Nail, kapan jadwal rilisnya?',
    unmuteMeet: async () => {
      unmuteCalled++;
      return true;
    },
    progress: ev => progressEvents.push(ev),
  });

  assert.equal(unmuteCalled, 1);
  assert.ok(jsCalls.some(s => s.includes('codexResetTurnState')));
  assert.ok(jsCalls.some(s => s.includes('codexOpenOut')));
  assert.ok(jsCalls.some(s => s.includes('codexCloseOut') && s.includes('codexCloseIn')));

  assert.equal(rpcCalls.length, 2);
  assert.equal(rpcCalls[0].method, 'thread/realtime/appendText');
  assert.equal(rpcCalls[0].params.role, 'developer');
  assert.match(rpcCalls[0].params.text, /Keputusan awal: rilis hari Jumat\./);
  assert.equal(rpcCalls[1].method, 'thread/realtime/appendText');
  assert.deepEqual(rpcCalls[1].params, {
    threadId: 'thr_wake_1',
    role: 'user',
    text: 'Jawab sebagai Nail dalam bahasa Indonesia.\n\nNail, kapan jadwal rilisnya?',
  });

  assert.equal(result.heard, 'Nail, kapan jadwal rilisnya?');
  assert.equal(result.reply, 'Siap, rilis tetap Jumat.');
  assert.equal(typeof result.latencyMs, 'number');
  assert.equal(typeof result.timing?.notesSyncMs, 'number');
  assert.equal(typeof result.timing?.unmuteMs, 'number');
  assert.equal(typeof result.timing?.codexTtfbMs, 'number');
  assert.equal(typeof result.timing?.totalTrueEndOfSpeechMs, 'number');
  assert.equal(typeof result.timing?.trueSpeechEndedAtMs, 'number');
  assert.equal(typeof result.timing?.firstAudioAtMs, 'number');
  assert.deepEqual(result.diag, {
    maxOutRms: 0.05,
    maxMicRms: 0.01,
    rxPackets: 10,
    rxEnergy: 0.15,
  });
  assert.ok(progressEvents.includes('voice-codex-heard'));
  assert.ok(progressEvents.includes('voice-sending'));
});

test('manual Codex voice uses direct audio with presentation reading off', async () => {
  const source = readFileSync(join(__dirname, '../NAIL/Resources/meet.cjs'), 'utf8');
  const start = source.indexOf('  async function voiceTurn(');
  const end = source.indexOf('    const work =', start);
  const calls = [];
  const voiceTurn = vm.runInNewContext(`${source.slice(start, end)}\n}; voiceTurn`, {
    provider: 'codex',
    codexSession: {},
    platform: 'meet',
    presentationReadingEnabled: false,
    startCodexWakeDaemon: () => { assert.fail('Manual live audio must not start Whisper'); },
    emit: () => {},
    runCodexLiveTurn: async () => { calls.push('live'); },
  });

  const wc = {};
  await voiceTurn(wc, () => {}, () => {});
  assert.deepEqual(calls, ['live']);
});

test('CodexLiveSession.runTextTurn returns noAudio for empty or whitespace text without calling appendText', async () => {
  const session = new CodexLiveSession();
  const rpcCalls = [];
  session.callRpc = async (method, params) => {
    rpcCalls.push({method, params});
    return {};
  };

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript() {
      throw new Error('should not execute JS for empty text');
    },
  };

  const res = await session.runTextTurn(wc, {
    text: '   \n\t  ',
    unmuteMeet: async () => true,
  });

  assert.deepEqual(res, {noAudio: true});
  assert.equal(rpcCalls.length, 0);
});

test('CodexLiveSession.runTextTurn throws voice-no-mic when unmuteMeet returns false', async () => {
  const session = new CodexLiveSession();
  session.child = {};
  session.appReady = Promise.resolve();
  session.threadId = 'thr_wake_2';
  session.webrtcConnected = true;

  const jsCalls = [];
  const rpcCalls = [];
  session.callRpc = async (method, params) => {
    rpcCalls.push({method, params});
    return {};
  };

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      if (script.includes('codexState')) return {connected: true};
      return null;
    },
  };

  await assert.rejects(
    () => session.runTextTurn(wc, {
      text: 'Nail, cek mic dong',
      unmuteMeet: async () => false,
    }),
    {message: 'voice-no-mic'}
  );

  assert.equal(rpcCalls.length, 0);
  assert.ok(jsCalls.some(s => s.includes('codexCloseOut') && s.includes('codexCloseIn')));
  session.clearIdleTimer();
});

test('STYLE_PROMPTS and resolveStylePrompt include Indonesian native pronunciation guidance for every style', () => {
  assert.equal(typeof INDONESIAN_PRONUNCIATION_GUIDE, 'string');
  assert.match(INDONESIAN_PRONUNCIATION_GUIDE, /aksen penutur asli Indonesia/i);

  for (const style of ['casual', 'professional', 'brainstorm']) {
    const prompt = STYLE_PROMPTS[style];
    assert.ok(prompt.includes(INDONESIAN_PRONUNCIATION_GUIDE), `${style} prompt missing pronunciation guide`);
    assert.match(prompt, /aksen penutur asli Indonesia/i);
    assert.equal(resolveStylePrompt(style), prompt);
  }

  assert.equal(resolveStylePrompt('unknown-style'), STYLE_PROMPTS.casual);
});

test('CodexLiveSession.runLiveTurn opens output early on unmute and completes fast replies streamed before outBase', async () => {
  const session = new CodexLiveSession({noTranscriptTimeoutMs: 500, noReplyTimeoutMs: 800, turnTimeoutMs: 1200});
  session.child = {};
  session.appReady = Promise.resolve();
  session.threadId = 'thr_live_fast';
  session.webrtcConnected = true;
  session.callRpc = async () => ({});

  const jsCalls = [];
  const progressEvents = [];
  let speechDone = false;

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      if (script.includes('codexWaitUserSpeech')) {
        await new Promise(resolve => setTimeout(resolve, 40));
        speechDone = true;
        return {spoke: true, aborted: false, peak: 0.08, ms: 40, liveTracks: 1};
      }
      if (script.includes('codexState')) {
        if (!speechDone) {
          return {
            connected: true,
            rxPackets: 100,
            rxEnergy: 2.0,
            outRms: 0,
            micRms: 0,
            dcReply: '',
            dcReplyDone: false,
            dcEvents: [],
          };
        }
        // Simulated fast Turn-2 reply: audio + transcript finished before outBase snapshot.
        return {
          connected: true,
          rxPackets: 150,
          rxEnergy: 2.8,
          outRms: 0,
          micRms: 0,
          dcHeard: 'Pertanyaan kedua Nail?',
          dcReply: 'Ini jawaban langsung untuk pertanyaan kedua.',
          dcReplyDone: true,
          dcEvents: ['response.done'],
        };
      }
      return null;
    },
  };

  const result = await session.runLiveTurn(wc, {
    unmuteMeet: async () => true,
    progress: ev => progressEvents.push(ev),
  });

  const openOutCount = jsCalls.filter(s => s.includes('codexOpenOut')).length;
  assert.equal(openOutCount, 1);
  assert.equal(result.reply, 'Ini jawaban langsung untuk pertanyaan kedua.');
  assert.equal(result.heard, 'Pertanyaan kedua Nail?');
  assert.ok(progressEvents.includes('voice-sending'));
  session.clearIdleTimer();
});

test('CodexLiveSession._awaitReplyTurn resets wedged WebRTC at noTranscriptTimeoutMs so next turn reconnects', async () => {
  const session = new CodexLiveSession({noTranscriptTimeoutMs: 150, noReplyTimeoutMs: 300, turnTimeoutMs: 1000});
  session.child = {};
  session.threadId = 'thr_live_stale';
  session.webrtcConnected = true;

  const rpcCalls = [];
  const jsCalls = [];
  session.callRpc = async (method, params) => {
    rpcCalls.push({method, params});
    return {};
  };

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      if (script.includes('codexState')) {
        return {
          connected: true,
          rxPackets: 50,
          rxEnergy: 1.0,
          outRms: 0,
          micRms: 0,
          dcHeard: '',
          dcReply: '',
          dcReplyDone: false,
          dcEvents: [],
        };
      }
      return null;
    },
  };
  session.activeWc = wc;

  const state = {
    heard: '',
    reply: '',
    heardParts: [],
    heardDelta: '',
    replyParts: [],
    replyDelta: '',
    itemRoles: new Map(),
    itemBuffers: new Map(),
    itemHeard: '',
    itemReply: '',
    agentReply: '',
    rpcEvents: [],
    outSpoke: false,
    completed: false,
    delegationActive: false,
    awaitingPostDelegation: false,
    postDelegationSpoke: false,
    delegationDoneAt: 0,
    rejectTurn: () => {},
  };

  const base = {connected: true, rxPackets: 50, rxEnergy: 1.0};
  await assert.rejects(
    () => session._awaitReplyTurn(wc, state, {
      base,
      outBase: base,
      speechEndedAt: Date.now(),
      interrupted: new Promise(() => {}),
      progress: () => {},
    }),
    {message: 'voice-codex-no-transcript'}
  );

  assert.equal(session.webrtcConnected, false);
  assert.ok(jsCalls.some(s => s.includes('codexDisconnect')));
  assert.ok(rpcCalls.some(c => c.method === 'thread/realtime/stop'));
});

test('CodexLiveSession defaults idleTimeoutMs to 600s, supports prewarmConnection, and completes dcReplyDone at 200ms', async () => {
  const session = new CodexLiveSession();
  assert.equal(session.idleTimeoutMs, 600_000);
  assert.equal(session._notesSyncPromise, null);
  assert.equal(session._lastSyncedSlideText, '');

  const state = {
    outSpoke: true,
    delegationActive: false,
    awaitingPostDelegation: false,
    replyParts: ['Halo.'],
    replyDelta: '',
  };
  assert.equal(CodexLiveSession.shouldCompleteTurn(state, 3, 1000, 1150, {dcReplyDone: true}), false);
  assert.equal(CodexLiveSession.shouldCompleteTurn(state, 3, 1000, 1200, {dcReplyDone: true}), true);
  assert.equal(CodexLiveSession.shouldCompleteTurn(state, 3, 1000, 1750, {dcReplyDone: false}), false);
  assert.equal(CodexLiveSession.shouldCompleteTurn(state, 3, 1000, 1800, {dcReplyDone: false}), true);
  assert.equal(CodexLiveSession.shouldCompleteTurn(state, 3, 1000, 2700, {dcReplyDone: false, serverResponseInFlight: true}), false);
  assert.equal(CodexLiveSession.shouldCompleteTurn(state, 3, 1000, 2800, {dcReplyDone: false, serverResponseInFlight: true}), true);

  let ensureCalls = 0;
  session.ensureConnected = async () => {
    ensureCalls++;
    session.webrtcConnected = true;
  };
  const wc = {isDestroyed: () => false};
  session.prewarmConnection(wc);
  assert.equal(ensureCalls, 1);
  await Promise.resolve();
  assert.equal(session.webrtcConnected, true);

  // No-op when already connected or disposed
  session.prewarmConnection(wc);
  assert.equal(ensureCalls, 1);
  session.webrtcConnected = false;
  session.disposed = true;
  session.prewarmConnection(wc);
  assert.equal(ensureCalls, 1);
});

test('CodexLiveSession.interrupt pre-reconnects WebRTC in the background when wasSpeaking is true', async () => {
  const session = new CodexLiveSession();
  const events = [];
  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      events.push(`js:${script}`);
      return null;
    },
  };
  session.activeWc = wc;
  session.disconnectWebRTC = async targetWc => {
    assert.equal(targetWc, wc);
    events.push('disconnect');
  };
  session.ensureConnected = async targetWc => {
    assert.equal(targetWc, wc);
    events.push('ensureConnected');
  };

  let rejectedErr = null;
  session.turnState = {
    outSpoke: true,
    rejectTurn: err => { rejectedErr = err; },
  };
  session.interrupt(wc);
  assert.equal(rejectedErr?.message, 'voice-interrupted');
  assert.equal(session.turnState.interruptedWithReconnect, true);
  await new Promise(resolve => setImmediate(resolve));
  assert.ok(events.includes('disconnect'));
  assert.ok(events.includes('ensureConnected'));
  assert.ok(events.indexOf('disconnect') < events.indexOf('ensureConnected'));

  // When outSpoke is false, interrupt does not disconnect/reconnect
  events.length = 0;
  rejectedErr = null;
  session.turnState = {
    outSpoke: false,
    rejectTurn: err => { rejectedErr = err; },
  };
  session.interrupt(wc);
  assert.equal(rejectedErr?.message, 'voice-interrupted');
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(events.includes('disconnect'), false);
  assert.equal(events.includes('ensureConnected'), false);
});

test('CodexLiveSession.runTextTurn runs unmuteMeet in parallel with appendText, merges preTiming, and keeps follow-up mic open', async t => {
  const session = new CodexLiveSession();
  t.after(() => session.clearIdleTimer());
  session.child = {};
  session.appReady = Promise.resolve();
  session.threadId = 'thr_parallel';
  session.webrtcConnected = true;

  const timeline = [];
  const jsCalls = [];
  let appendedUserText = false;
  let pollCount = 0;

  session.callRpc = async (method, params) => {
    if (method === 'thread/realtime/appendText' && params.role === 'user') {
      timeline.push('appendText');
      appendedUserText = true;
    }
    return {};
  };

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      if (script.includes('codexOpenOut')) timeline.push('codexOpenOut');
      if (script.includes('codexState')) {
        if (!appendedUserText) {
          return {connected: true, rxPackets: 10, rxEnergy: 0.1, outRms: 0, micRms: 0, dcReply: '', dcReplyDone: false};
        }
        pollCount++;
        if (pollCount === 1) {
          return {connected: true, rxPackets: 14, rxEnergy: 0.2, outRms: 0.04, micRms: 0, dcReply: 'Jawaban cepat.', dcReplyDone: false};
        }
        await new Promise(resolve => setTimeout(resolve, 220));
        return {connected: true, rxPackets: 18, rxEnergy: 0.2, outRms: 0, micRms: 0, dcReply: 'Jawaban cepat.', dcReplyDone: true};
      }
      return null;
    },
  };

  const trueEndMs = Date.now() - 600;
  const result = await session.runTextTurn(wc, {
    text: 'Nail, apa kabar proyek?',
    unmuteMeet: async () => {
      timeline.push('unmute:start');
      await new Promise(resolve => setTimeout(resolve, 60));
      timeline.push('unmute:done');
      return true;
    },
    keepFollowUpMic: true,
    preTiming: {
      vadSilenceMs: 450,
      captureToWorkerMs: 6,
      whisperMs: 140,
      trueSpeechEndedAtMs: trueEndMs,
    },
  });

  // appendText must fire while unmuteMeet is still in-flight, and codexOpenOut after unmute finishes
  assert.ok(timeline.indexOf('unmute:start') < timeline.indexOf('appendText'));
  assert.ok(timeline.indexOf('appendText') < timeline.indexOf('unmute:done'));
  assert.ok(timeline.indexOf('unmute:done') < timeline.indexOf('codexOpenOut'));

  assert.equal(result.reply, 'Jawaban cepat.');
  assert.equal(result.timing.vadSilenceMs, 450);
  assert.equal(result.timing.captureToWorkerMs, 6);
  assert.equal(result.timing.whisperMs, 140);
  assert.equal(result.timing.trueSpeechEndedAtMs, trueEndMs);
  assert.ok(result.timing.unmuteMs >= 50);
  assert.ok(result.timing.totalTrueEndOfSpeechMs >= 600);
  assert.ok(jsCalls.some(s => s.includes('codexCloseOut?.({keepTeamsSenders: true})')));
});

test('CodexLiveSession.runLiveTurn supports custom wait/silence params, skipUnmute, keepFollowUpMic, and timing fields', async t => {
  const session = new CodexLiveSession();
  t.after(() => session.clearIdleTimer());
  session.child = {};
  session.appReady = Promise.resolve();
  session.threadId = 'thr_followup';
  session.webrtcConnected = true;
  session.callRpc = async () => ({});

  const jsCalls = [];
  let speechDone = false;
  let unmuteCalled = 0;
  const trueEndMs = Date.now() - 350;

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      if (script.includes('codexWaitUserSpeech')) {
        speechDone = true;
        return {
          spoke: true,
          aborted: false,
          peak: 0.06,
          ms: 500,
          silenceWaitMs: 350,
          speechEndedAtMs: trueEndMs,
          liveTracks: 1,
        };
      }
      if (script.includes('codexState')) {
        if (!speechDone) {
          return {connected: true, rxPackets: 20, rxEnergy: 0.5, outRms: 0, micRms: 0, dcReply: '', dcReplyDone: false};
        }
        return {
          connected: true,
          rxPackets: 30,
          rxEnergy: 0.8,
          outRms: 0,
          micRms: 0,
          dcHeard: 'Lanjut pertanyaan kedua?',
          dcReply: 'Siap, ini kelanjutannya.',
          dcReplyDone: true,
        };
      }
      return null;
    },
  };

  const result = await session.runLiveTurn(wc, {
    unmuteMeet: async () => {
      unmuteCalled++;
      return true;
    },
    maxWaitMs: 7000,
    maxSpeakMs: 12000,
    silenceMs: 350,
    skipUnmute: true,
    keepFollowUpMic: true,
  });

  assert.equal(unmuteCalled, 0);
  assert.ok(jsCalls.some(s => s.includes('codexWaitUserSpeech(7000, 12000, 350)')));
  assert.ok(jsCalls.some(s => s.includes('codexOpenOut')));
  assert.ok(jsCalls.some(s => s.includes('codexCloseOut?.({keepTeamsSenders: true})')));
  assert.equal(result.heard, 'Lanjut pertanyaan kedua?');
  assert.equal(result.reply, 'Siap, ini kelanjutannya.');
  assert.equal(result.timing.vadSilenceMs, 350);
  assert.equal(result.timing.unmuteMs, 0);
  assert.equal(result.timing.trueSpeechEndedAtMs, trueEndMs);
  assert.ok(result.timing.totalTrueEndOfSpeechMs >= 350);

  // When 7s follow-up window expires with no speech (spoke: false), codexCloseOut() is called without keepTeamsSenders
  jsCalls.length = 0;
  const silentWc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      if (script.includes('codexWaitUserSpeech')) {
        return {spoke: false, aborted: false, peak: 0, ms: 7000, silenceWaitMs: 0, speechEndedAtMs: Date.now(), liveTracks: 1};
      }
      if (script.includes('codexState')) {
        return {connected: true, rxPackets: 30, rxEnergy: 0.8, outRms: 0, micRms: 0};
      }
      return null;
    },
  };
  const silentRes = await session.runLiveTurn(silentWc, {
    unmuteMeet: async () => true,
    maxWaitMs: 7000,
    silenceMs: 350,
    skipUnmute: true,
    keepFollowUpMic: true,
  });
  assert.deepEqual(silentRes, {noAudio: true});
  assert.ok(jsCalls.some(s => s.includes('codexCloseOut?.()')));
});
