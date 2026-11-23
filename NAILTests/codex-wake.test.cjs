const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createMeetingNotesMemory} = require('../NAIL/Resources/meet.cjs');
const {
  CodexLiveSession,
  INDONESIAN_PRONUNCIATION_GUIDE,
  STYLE_PROMPTS,
  resolveStylePrompt,
} = require('../NAIL/Resources/codex-voice.cjs');

test('CodexLiveSession.runTextTurn resets turn state, syncs notes, appends user text, and cleans up', async () => {
  const memory = createMeetingNotesMemory();
  const baseMs = new Date(2026, 10, 21, 14, 0, 0).getTime();
  memory.addEntry({text: 'Keputusan awal: rilis hari Jumat.', speaker: 'Rina', timestampMs: baseMs});

  const session = new CodexLiveSession({notesMemory: memory});
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
    text: 'Nail, kapan jadwal rilisnya?',
  });

  assert.equal(result.heard, 'Nail, kapan jadwal rilisnya?');
  assert.equal(result.reply, 'Siap, rilis tetap Jumat.');
  assert.equal(typeof result.latencyMs, 'number');
  assert.deepEqual(result.diag, {
    maxOutRms: 0.05,
    maxMicRms: 0.01,
    rxPackets: 10,
    rxEnergy: 0.15,
  });
  assert.ok(progressEvents.includes('voice-codex-heard'));
  assert.ok(progressEvents.includes('voice-sending'));
  session.clearIdleTimer();
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
