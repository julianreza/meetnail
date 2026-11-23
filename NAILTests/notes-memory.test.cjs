const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createMeetingNotesMemory} = require('../NAIL/Resources/meet.cjs');
const {CodexLiveSession} = require('../NAIL/Resources/codex-voice.cjs');

test('createMeetingNotesMemory formats speakers, filters notices, and dedupes consecutive lines', () => {
  const memory = createMeetingNotesMemory();
  const baseMs = new Date(2026, 10, 21, 9, 5, 0).getTime();

  assert.equal(memory.addEntry({text: '[Pencatatan terputus: sebagian percakapan mungkin tidak tercatat.]', timestampMs: baseMs}), null);
  assert.equal(memory.addEntry({text: '[Audio rapat terputus; percakapan selama jeda mungkin tidak tercatat.]', timestampMs: baseMs}), null);
  assert.equal(memory.addEntry({text: '   ', timestampMs: baseMs}), null);

  assert.ok(memory.addEntry({text: 'AI kita pakai Gemini Flash ya.', speaker: 'Rina', timestampMs: baseMs}));
  assert.equal(memory.addEntry({text: 'AI   kita pakai Gemini Flash ya.', speaker: 'Rina', timestampMs: baseMs + 2000}), null);
  assert.ok(memory.addEntry({text: 'Setuju, nanti cek kuotanya.', speaker: 'Pembicara tidak diketahui', timestampMs: baseMs + 10_000}));

  assert.equal(memory.count(), 2);
  const snap = memory.buildSnapshot();
  assert.equal(
    snap,
    '[09:05] Rina: AI kita pakai Gemini Flash ya.\n[09:05] Setuju, nanti cek kuotanya.'
  );
});

test('buildSnapshot preserves early opening context and recent tail when compacting long meetings', () => {
  const memory = createMeetingNotesMemory();
  const baseMs = new Date(2026, 10, 21, 10, 0, 0).getTime();

  memory.addEntry({text: 'Keputusan awal: AI utama pakai Gemini Flash untuk voice assistant.', speaker: 'Rina', timestampMs: baseMs});
  for (let i = 1; i <= 25; i++) {
    memory.addEntry({
      text: `Diskusi detail modul backend nomor ${i} yang lumayan panjang tentang integrasi webhook dan antrean.`,
      speaker: 'Budi',
      timestampMs: baseMs + i * 60_000,
    });
  }
  memory.addEntry({text: 'Sprint 12 fokus implementasi fitur login SSO minggu depan.', speaker: 'Sari', timestampMs: baseMs + 30 * 60_000});

  const maxChars = 420;
  const compacted = memory.buildSnapshot(maxChars);
  assert.ok(compacted.length <= maxChars);
  assert.match(compacted, /AI utama pakai Gemini Flash/);
  assert.match(compacted, /Sprint 12 fokus implementasi fitur login SSO/);
  assert.match(compacted, /dipadatkan/);
});

test('maxEntries overflow drops middle entries while preserving earliest opening notes', () => {
  const memory = createMeetingNotesMemory({maxEntries: 10});
  const baseMs = new Date(2026, 10, 21, 10, 0, 0).getTime();

  memory.addEntry({text: 'Topik awal: AI pakai Gemini.', speaker: 'Rina', timestampMs: baseMs});
  for (let i = 1; i <= 13; i++) {
    memory.addEntry({text: `Bahasan tengah ke-${i}`, speaker: 'Budi', timestampMs: baseMs + i * 1000});
  }
  memory.addEntry({text: 'Topik akhir: sprint plan rilis Senin.', speaker: 'Sari', timestampMs: baseMs + 20_000});

  assert.equal(memory.count(), 10);
  const snap = memory.buildSnapshot();
  assert.match(snap, /Topik awal: AI pakai Gemini/);
  assert.match(snap, /Topik akhir: sprint plan rilis Senin/);
});

test('drainDelta filters command/reply kinds, advances cursor past them, and empties when caught up', () => {
  const memory = createMeetingNotesMemory();
  const baseMs = new Date(2026, 10, 21, 11, 0, 0).getTime();

  const e1 = memory.addEntry({text: 'Kita pilih AI Codex untuk voice.', speaker: 'Rina', timestampMs: baseMs, kind: 'meeting'});
  memory.addExchange({
    heard: 'Nail, tadi pakai AI apa?',
    reply: 'Tadi sepakat pakai AI Codex.',
    heardAtMs: baseMs + 2000,
    replyAtMs: baseMs + 3500,
  });

  assert.match(memory.buildSnapshot(), /Peserta: Nail, tadi pakai AI apa\?/);
  assert.match(memory.buildSnapshot(), /Nail: Tadi sepakat pakai AI Codex\./);

  const deltaOnlyExchanges = memory.drainDelta(e1.id, 4000, {excludeKinds: ['command', 'reply']});
  assert.equal(deltaOnlyExchanges.text, '');
  assert.equal(deltaOnlyExchanges.count, 0);
  assert.equal(deltaOnlyExchanges.nextCursor, memory.latestCursor());

  memory.addEntry({text: 'Sprint plan: backend selesai Kamis.', speaker: 'Budi', timestampMs: baseMs + 10_000, kind: 'meeting'});
  const nextDelta = memory.drainDelta(deltaOnlyExchanges.nextCursor, 4000, {excludeKinds: ['command', 'reply']});
  assert.equal(nextDelta.count, 1);
  assert.match(nextDelta.text, /Budi: Sprint plan: backend selesai Kamis\./);

  const caughtUp = memory.drainDelta(nextDelta.nextCursor, 4000, {excludeKinds: ['command', 'reply']});
  assert.equal(caughtUp.text, '');
  assert.equal(caughtUp.count, 0);
});

function createMockWc() {
  return {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      if (script.includes('codexConnect')) return 'mock-sdp-offer';
      if (script.includes('codexState')) return {connected: true};
      return null;
    },
  };
}

test('CodexLiveSession injects initialItems on _doConnect and syncs incremental developer deltas', async () => {
  const memory = createMeetingNotesMemory();
  const baseMs = new Date(2026, 10, 21, 13, 0, 0).getTime();
  memory.addEntry({text: 'Awal rapat: AI nya pakai Gemini.', speaker: 'Rina', timestampMs: baseMs});

  const rpcCalls = [];
  const session = new CodexLiveSession({notesMemory: memory});
  session.child = {};
  session.threadId = 'thr_1';
  session.callRpc = async (method, params) => {
    rpcCalls.push({method, params});
    return {};
  };

  await session._doConnect(createMockWc());
  assert.equal(rpcCalls.length, 1);
  assert.equal(rpcCalls[0].method, 'thread/realtime/start');
  assert.equal(rpcCalls[0].params.initialItems?.length, 1);
  assert.equal(rpcCalls[0].params.initialItems[0].role, 'developer');
  assert.match(rpcCalls[0].params.initialItems[0].text, /Awal rapat: AI nya pakai Gemini\./);
  assert.equal(session.syncedNoteCursor, memory.latestCursor());

  // Already caught up -> no appendText call
  assert.equal(await session.syncNotesToLiveSession(), false);
  assert.equal(rpcCalls.length, 1);

  // New Q&A exchange alone should not trigger appendText, only advance cursor
  memory.addExchange({heard: 'Tes?', reply: 'Siap.', heardAtMs: baseMs + 5000, replyAtMs: baseMs + 6000});
  assert.equal(await session.syncNotesToLiveSession(), false);
  assert.equal(rpcCalls.length, 1);

  // New ambient meeting note triggers developer appendText
  memory.addEntry({text: 'Akhir rapat: sprint plan deploy Jumat.', speaker: 'Budi', timestampMs: baseMs + 12_000});
  assert.equal(await session.syncNotesToLiveSession(), true);
  assert.equal(rpcCalls.length, 2);
  assert.equal(rpcCalls[1].method, 'thread/realtime/appendText');
  assert.deepEqual(
    {threadId: rpcCalls[1].params.threadId, role: rpcCalls[1].params.role},
    {threadId: 'thr_1', role: 'developer'}
  );
  assert.match(rpcCalls[1].params.text, /Akhir rapat: sprint plan deploy Jumat\./);
  assert.equal(session.syncedNoteCursor, memory.latestCursor());

  // Non-fatal failure leaves cursor intact for next retry
  memory.addEntry({text: 'Catatan tambahan penting.', timestampMs: baseMs + 15_000});
  const cursorBeforeFailure = session.syncedNoteCursor;
  session.callRpc = async () => { throw new Error('append-rejected'); };
  assert.equal(await session.syncNotesToLiveSession(), false);
  assert.equal(session.syncedNoteCursor, cursorBeforeFailure);

  // disconnectWebRTC resets syncedNoteCursor so reconnect reloads full snapshot
  session.callRpc = async () => ({});
  await session.disconnectWebRTC();
  assert.equal(session.syncedNoteCursor, 0);
});

test('CodexLiveSession _doConnect falls back without initialItems if realtime/start keeps failing', async () => {
  const memory = createMeetingNotesMemory();
  memory.addEntry({text: 'Catatan awal rapat.', speaker: 'Rina'});

  const rpcCalls = [];
  const session = new CodexLiveSession({notesMemory: memory});
  session.child = {};
  session.threadId = 'thr_1';
  session.callRpc = async (method, params) => {
    rpcCalls.push({method, params});
    if (method === 'thread/start') return {thread: {id: 'thr_2'}};
    if (method === 'thread/realtime/start' && params.initialItems) {
      throw new Error('voice-codex-error');
    }
    return {};
  };

  await session._doConnect(createMockWc());
  assert.deepEqual(
    rpcCalls.map(c => ({method: c.method, threadId: c.params?.threadId, hasInitial: Boolean(c.params?.initialItems)})),
    [
      {method: 'thread/realtime/start', threadId: 'thr_1', hasInitial: true},
      {method: 'thread/start', threadId: undefined, hasInitial: false},
      {method: 'thread/realtime/start', threadId: 'thr_2', hasInitial: true},
      {method: 'thread/realtime/start', threadId: 'thr_2', hasInitial: false},
    ]
  );
  assert.equal(session.webrtcConnected, true);
  assert.equal(session.syncedNoteCursor, 0);
});
