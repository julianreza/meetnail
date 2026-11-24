const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync, mkdtempSync, rmSync} = require('node:fs');
const {join} = require('node:path');
const {tmpdir} = require('node:os');
const vm = require('node:vm');
const {
  createMeetingNotesMemory,
  resolveCodexWakeWhisperModel,
  createWakePriorityGate,
  buildLatencyLogEntry,
  appendLatencyLog,
  buildWakeDiagEntry,
  appendWakeDiagLog,
  createPresentationSlidePoller,
  executeCodexHandsFreeTurn,
  executeCodexTurnWithFollowUp,
  inspectMeet,
} = require('../NAIL/Resources/meet.cjs');

test('resolveCodexWakeWhisperModel prefers base when cached and falls back otherwise', () => {
  const checkedPaths = [];
  const cachedModel = resolveCodexWakeWhisperModel({
    whisperModel: 'small',
    homeDir: '/Users/tester',
    existsSync: candidate => {
      checkedPaths.push(candidate);
      return true;
    },
  });
  assert.equal(cachedModel, 'base');
  assert.deepEqual(checkedPaths, ['/Users/tester/.cache/huggingface/hub/models--Systran--faster-whisper-base']);

  const fallbackConfigured = resolveCodexWakeWhisperModel({
    whisperModel: 'medium',
    homeDir: '/Users/tester',
    existsSync: () => false,
  });
  assert.equal(fallbackConfigured, 'medium');

  const fallbackDefault = resolveCodexWakeWhisperModel({
    whisperModel: '',
    homeDir: '/Users/tester',
    existsSync: () => false,
  });
  assert.equal(fallbackDefault, 'small');

  assert.equal(resolveCodexWakeWhisperModel('small', () => true), 'base');
  assert.equal(resolveCodexWakeWhisperModel('medium', () => false), 'medium');
  assert.equal(
    resolveCodexWakeWhisperModel({
      whisperModel: 'small',
      codexWakeWhisperModel: 'small',
      homeDir: '/Users/tester',
      existsSync: () => true,
    }),
    'small'
  );
});

test('createWakePriorityGate waits while wake check is in-flight and wakes on completion or timeout', async () => {
  const gate = createWakePriorityGate({defaultMaxWaitMs: 1500});
  assert.equal(gate.activeCount, 0);
  assert.equal(await gate.waitIfBusy(100), true);

  gate.enter();
  assert.equal(gate.activeCount, 1);
  let released = false;
  const waitPromise = gate.waitIfBusy(500).then(res => {
    released = true;
    return res;
  });
  await new Promise(resolve => setTimeout(resolve, 25));
  assert.equal(released, false);
  gate.leave();
  assert.equal(await waitPromise, true);
  assert.equal(gate.activeCount, 0);

  // Bounded timeout when wake check takes longer than maxWaitMs
  gate.enter();
  const timedOut = await gate.waitIfBusy(35);
  assert.equal(timedOut, false);
  gate.leave();
});

test('manual Codex turn uses runCodexLiveTurn even when presentationReadingEnabled === true', async () => {
  const source = readFileSync(join(__dirname, '../NAIL/Resources/meet.cjs'), 'utf8');
  const start = source.indexOf('  async function voiceTurn(');
  const end = source.indexOf('    const work =', start);
  const calls = [];
  const emitted = [];
  const voiceTurn = vm.runInNewContext(`${source.slice(start, end)}\n}; voiceTurn`, {
    provider: 'codex',
    codexSession: {},
    platform: 'meet',
    presentationReadingEnabled: true,
    codexHandsFree: true,
    codexWakeFailed: false,
    startCodexWakeDaemon: () => {
      assert.fail('Manual Codex turn must not start Whisper wake daemon even when presentationReadingEnabled is true');
    },
    runCodexManualTurn: () => {
      assert.fail('Manual Codex turn must never invoke runCodexManualTurn');
    },
    emit: ev => emitted.push(ev),
    runCodexLiveTurn: async () => { calls.push('live'); },
    runCodexHandsFreeTurn: async () => { calls.push('hands-free'); },
  });

  await voiceTurn({}, () => {}, () => {}, false, false);
  assert.deepEqual(calls, ['live']);
  assert.ok(emitted.includes('voice-preview-end'));
});

test('Hands-Free Turn 1 fast path uses codexRecordWakePcm + format:pcm16k + prewarmConnection without wake-preview', async () => {
  const jsScripts = [];
  const wakeRequests = [];
  const events = [];
  let prewarmCalls = 0;
  let textTurnCalls = [];

  const pcmBytes = Buffer.from([1, 0, -1, 0, 120, 4, -120, -4]);
  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsScripts.push(script);
      if (script.includes('recordingPreview')) {
        assert.fail('Hands-Free fast path must not poll recordingPreview()');
      }
      if (script.includes('codexRecordWakePcm')) {
        return {
          pcmBase64: pcmBytes.toString('base64'),
          sampleRate: 16000,
          silenceWaitMs: 450,
          speechEndedAtMs: 1700000001000,
          durationMs: 1150,
        };
      }
      return null;
    },
  };

  const codexSession = {
    prewarmConnection(targetWc) {
      assert.equal(targetWc, wc);
      prewarmCalls++;
    },
  };

  await executeCodexHandsFreeTurn({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession,
    checkCodexWake: async (audioPath, mode, opts) => {
      // prewarmConnection must be triggered before checkCodexWake finishes
      assert.equal(prewarmCalls, 1);
      const diskBytes = readFileSync(audioPath);
      wakeRequests.push({audioPath, mode, opts, byteLength: diskBytes.length});
      return {
        triggered: true,
        raw: 'Nail kapan jadwal rilisnya',
        prompt: 'kapan jadwal rilisnya',
        has_query: true,
        whisperMs: 142,
      };
    },
    emit: ev => events.push(ev),
    appendWakeDiagLogFn: () => {},
    platform: 'meet',
    presentationReadingEnabled: false,
    runCodexTextTurn: async (_wc, _read, _click, prompt, turnOpts) => {
      textTurnCalls.push({prompt, turnOpts});
    },
    runCodexLiveTurn: async () => {
      assert.fail('Should route wake query to runCodexTextTurn');
    },
    runCodexPresentationTurn: async () => {
      assert.fail('Should not route non-presentation query to runCodexPresentationTurn');
    },
  });

  assert.equal(prewarmCalls, 1);
  assert.equal(wakeRequests.length, 1);
  assert.match(wakeRequests[0].audioPath, /wake\.pcm$/);
  assert.equal(wakeRequests[0].mode, 'wake');
  assert.deepEqual(wakeRequests[0].opts, {format: 'pcm16k'});
  assert.equal(wakeRequests[0].byteLength, pcmBytes.length);
  assert.ok(!jsScripts.some(s => s.includes('recordingPreview')));

  assert.equal(textTurnCalls.length, 1);
  assert.equal(textTurnCalls[0].prompt, 'kapan jadwal rilisnya');
  assert.equal(textTurnCalls[0].turnOpts.mode, 'hands-free');
  const {preTiming} = textTurnCalls[0].turnOpts;
  assert.equal(preTiming.vadSilenceMs, 450);
  assert.equal(preTiming.whisperMs, 142);
  assert.equal(preTiming.trueSpeechEndedAtMs, 1700000001000);
  assert.equal(typeof preTiming.captureToWorkerMs, 'number');
  assert.ok(preTiming.captureToWorkerMs >= 0);
  assert.ok(events.includes('voice-standby'));
  assert.ok(events.some(e => e.startsWith('voice-wake ')));
});

test('Hands-Free Turn 1 falls back gracefully to record() + wake.webm when codexRecordWakePcm is unavailable', async () => {
  const wakeRequests = [];
  const textTurnCalls = [];
  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      if (script.includes('codexRecordWakePcm')) return undefined;
      if (script.includes('record(8000, true, 12000, false)')) {
        return Buffer.from('fake-webm').toString('base64');
      }
      return null;
    },
  };

  await executeCodexHandsFreeTurn({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession: {prewarmConnection: () => {}},
    appendWakeDiagLogFn: () => {},
    checkCodexWake: async (audioPath, mode, opts) => {
      wakeRequests.push({audioPath, mode, opts});
      return {
        triggered: true,
        raw: 'Nail halo',
        prompt: 'halo',
        has_query: true,
        whisperMs: 210,
      };
    },
    runCodexTextTurn: async (_wc, _read, _click, prompt, turnOpts) => {
      textTurnCalls.push({prompt, turnOpts});
    },
  });

  assert.equal(wakeRequests.length, 1);
  assert.match(wakeRequests[0].audioPath, /wake\.webm$/);
  assert.equal(wakeRequests[0].mode, 'wake');
  assert.equal(wakeRequests[0].opts, undefined);
  assert.equal(textTurnCalls.length, 1);
  assert.equal(textTurnCalls[0].prompt, 'halo');
  assert.equal(textTurnCalls[0].turnOpts.preTiming.whisperMs, 210);
});

test('Follow-up loop keeps mic unmuted across multiple turns and restores mute + Teams senders when 7s returns noAudio', async () => {
  const events = [];
  const jsCalls = [];
  const latencyEntries = [];
  const liveTurnOpts = [];
  let unmuteCount = 0;
  let restoreMuteCalls = 0;
  const notesMemory = createMeetingNotesMemory();

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      return null;
    },
  };

  const followUpResponses = [
    {
      heard: 'Bagaimana dengan tim backend?',
      reply: 'Tim backend selesai hari Kamis.',
      heardAtMs: 2000,
      replyAtMs: 2600,
      latencyMs: 600,
      timing: {
        vadSilenceMs: 350,
        notesSyncMs: 12,
        unmuteMs: 0,
        codexTtfbMs: 310,
        totalTrueEndOfSpeechMs: 660,
      },
    },
    {
      heard: 'Lalu siapa PIC QA?',
      reply: 'PIC QA adalah Budi.',
      heardAtMs: 4000,
      replyAtMs: 4550,
      latencyMs: 550,
      timing: {
        vadSilenceMs: 350,
        notesSyncMs: 0,
        unmuteMs: 0,
        codexTtfbMs: 290,
        totalTrueEndOfSpeechMs: 640,
      },
    },
    {noAudio: true},
  ];

  const codexSession = {
    async runLiveTurn(_wc, opts) {
      liveTurnOpts.push(opts);
      return followUpResponses.shift() || {noAudio: true};
    },
  };

  const preTiming = {
    vadSilenceMs: 450,
    captureToWorkerMs: 8,
    whisperMs: 135,
    trueSpeechEndedAtMs: 500,
  };

  await executeCodexTurnWithFollowUp({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession,
    unmuteAndVerifyMicFn: async (_wc, _read, _click, state) => {
      unmuteCount++;
      state.restoreMute = true;
      return true;
    },
    restoreMeetMuteFn: async (_wc, _read, _click, shouldRestore) => {
      if (shouldRestore) restoreMuteCalls++;
    },
    meetingNotes: notesMemory,
    emit: ev => events.push(ev),
    appendLatencyLogFn: entry => latencyEntries.push(buildLatencyLogEntry(entry)),
    platform: 'teams',
    provider: 'codex',
    mode: 'hands-free',
    preTiming,
    executeTurn: async opts => {
      assert.equal(opts.keepFollowUpMic, true);
      const ok = await opts.unmuteMeet();
      assert.equal(ok, true);
      return {
        heard: 'Nail, apa status rilis?',
        reply: 'Rilis siap hari Jumat.',
        heardAtMs: 1000,
        replyAtMs: 1500,
        latencyMs: 500,
        timing: {
          notesSyncMs: 20,
          unmuteMs: 110,
          codexTtfbMs: 340,
          totalTrueEndOfSpeechMs: 933,
        },
      };
    },
  });

  // Mic unmuted once at Turn 1, kept unmuted through 2 follow-up replies + 1 final 7s silent window, restored once at exit
  assert.equal(unmuteCount, 1);
  assert.equal(liveTurnOpts.length, 3);
  for (const opt of liveTurnOpts) {
    assert.equal(opt.maxWaitMs, 7000);
    assert.equal(opt.silenceMs, 350);
    assert.equal(opt.skipUnmute, true);
    assert.equal(opt.keepFollowUpMic, true);
  }
  assert.equal(restoreMuteCalls, 1);
  assert.ok(jsCalls.some(s => s.includes('restoreTeamsSenders')));

  // Events sequence: voice-result (Turn 1) -> voice-followup -> voice-result (Follow-up 1) -> voice-followup -> voice-result (Follow-up 2) -> voice-followup -> voice-standby
  const resultEvents = events.filter(e => e.startsWith('voice-result '));
  const followUpEvents = events.filter(e => e === 'voice-followup');
  assert.equal(resultEvents.length, 3);
  assert.equal(followUpEvents.length, 3);
  assert.equal(events[events.length - 1], 'voice-standby');

  // Latency log recorded for Turn 1 (hands-free) and both completed follow-up turns (follow-up)
  assert.equal(latencyEntries.length, 3);
  assert.equal(latencyEntries[0].mode, 'hands-free');
  assert.equal(latencyEntries[0].vadSilenceMs, 450);
  assert.equal(latencyEntries[0].captureToWorkerMs, 8);
  assert.equal(latencyEntries[0].whisperMs, 135);
  assert.equal(latencyEntries[1].mode, 'follow-up');
  assert.equal(latencyEntries[2].mode, 'follow-up');

  // Exchanges recorded in meetingNotes (3 user commands + 3 Nail replies = 6 entries)
  assert.equal(notesMemory.count(), 6);
});

test('Proactive background notes sync is triggered from emitNotes', async () => {
  const source = readFileSync(join(__dirname, '../NAIL/Resources/meet.cjs'), 'utf8');
  const start = source.indexOf('  const emitNotes = lines => {');
  const end = source.indexOf('  function syncCodexNotes()', start);
  const syncCalls = [];
  const emitted = [];
  const notesMemory = createMeetingNotesMemory();

  const emitNotes = vm.runInNewContext(`${source.slice(start, end)}; emitNotes`, {
    meetingNotes: notesMemory,
    emit: ev => emitted.push(ev),
    codexSession: {
      async syncNotesToLiveSession(signal, opts) {
        syncCalls.push({signal, opts: opts ? {...opts} : opts});
        return true;
      },
    },
  });

  emitNotes([{text: 'Kita sepakati anggaran Q4.', speaker: 'Andi', timestampMs: 1700000000000}]);
  assert.equal(notesMemory.count(), 1);
  assert.equal(emitted.length, 1);
  assert.match(emitted[0], /^voice-notulen-codex /);
  assert.deepEqual(syncCalls, [{signal: undefined, opts: {background: true}}]);
});

test('Structured latency.jsonl payload formatting writes expected schema for all turn modes', () => {
  const tempDir = mkdtempSync(join(tmpdir(), 'nail-latency-test-'));
  const logFilePath = join(tempDir, 'Logs', 'Nail', 'latency.jsonl');
  try {
    const written = appendLatencyLog({
      ts: '2026-11-23T16:50:00.000Z',
      platform: 'meet',
      mode: 'hands-free',
      preTiming: {
        vadSilenceMs: 450,
        captureToWorkerMs: 6,
        whisperMs: 128,
        trueSpeechEndedAtMs: 1000,
      },
      result: {
        reply: 'Halo, saya Nail siap membantu.',
        latencyMs: 520,
        timing: {
          notesSyncMs: 0,
          unmuteMs: 45,
          codexTtfbMs: 310,
          firstAudioAtMs: 1894,
        },
      },
    }, {logFilePath});

    assert.deepEqual(written, {
      ts: '2026-11-23T16:50:00.000Z',
      platform: 'meet',
      mode: 'hands-free',
      vadSilenceMs: 450,
      captureToWorkerMs: 6,
      whisperMs: 128,
      notesSyncMs: 0,
      unmuteMs: 45,
      codexTtfbMs: 310,
      totalTrueEndOfSpeechMs: 894,
      latencyMs: 520,
      replyLen: 30,
    });

    const lines = readFileSync(logFilePath, 'utf8').trim().split('\n');
    assert.equal(lines.length, 1);
    assert.deepEqual(JSON.parse(lines[0]), written);
  } finally {
    rmSync(tempDir, {recursive: true, force: true});
  }
});

test('Teams unmuteAndVerifyMic uses 40ms poll delay, 100ms settle delay, and skips micOutDiag on UNMUTE_OK', async () => {
  const source = readFileSync(join(__dirname, '../NAIL/Resources/meet.cjs'), 'utf8');
  const start = source.indexOf('  async function unmuteAndVerifyMic(');
  const end = source.indexOf('  async function restoreMeetMute(', start);
  const delays = [];
  const teamsLogs = [];
  const jsCalls = [];
  let readCalls = 0;

  const unmuteAndVerifyMic = vm.runInNewContext(`${source.slice(start, end)}\n; unmuteAndVerifyMic`, {
    platform: 'teams',
    stopping: false,
    turnInterrupted: false,
    delay: async ms => { delays.push(ms); },
    appendTeamsLog: line => teamsLogs.push(line),
    saveNoMicDiag: async () => { assert.fail('Should not call saveNoMicDiag on UNMUTE_OK'); },
  });

  const wc = {
    mainFrame: {routingId: 1},
    async executeJavaScript(script) {
      jsCalls.push(script);
      if (script.includes('micOutDiag')) {
        assert.fail('UNMUTE_OK hot path must not call micOutDiag synchronously');
      }
      if (script.includes('__nailMedia.sending()')) return true;
      return null;
    },
  };

  const state = {restoreMute: false};
  const ok = await unmuteAndVerifyMic(
    wc,
    async () => {
      readCalls++;
      if (readCalls <= 2) return {unmute: {x: 10, y: 20, name: 'Unmute'}, mute: null};
      return {unmute: null, mute: {x: 10, y: 20, name: 'Mute'}};
    },
    async () => true,
    state
  );

  assert.equal(ok, true);
  assert.equal(state.restoreMute, true);
  assert.deepEqual(delays, [40, 100]);
  assert.equal(teamsLogs.length, 1);
  assert.match(teamsLogs[0], /^UNMUTE_OK /);
  assert.ok(!jsCalls.some(s => s.includes('micOutDiag')));
});

test('Notulen worker payload in recordCodexNotes includes mode: transcript for beam_size=5 accuracy', async () => {
  const {PassThrough} = require('node:stream');
  const {EventEmitter} = require('node:events');
  const {mkdtemp, writeFile, rm} = require('node:fs/promises');
  const source = readFileSync(join(__dirname, '../NAIL/Resources/meet.cjs'), 'utf8');
  const start = source.indexOf('  async function recordCodexNotes() {');
  const end = source.indexOf('  let activeWin = null;', start);

  const stdinWrites = [];
  const emittedNotes = [];
  const emittedEvents = [];
  let meetingJoined = true;
  let takeCount = 0;

  const fakeWorker = new EventEmitter();
  fakeWorker.stdout = new PassThrough();
  fakeWorker.stderr = new PassThrough();
  fakeWorker.stdin = new EventEmitter();
  fakeWorker.stdin.writable = true;
  fakeWorker.stdin.write = chunk => {
    const str = String(chunk).trim();
    stdinWrites.push(JSON.parse(str));
    queueMicrotask(() => {
      fakeWorker.stdout.write(`${JSON.stringify({
        entries: [{text: 'Selamat pagi tim engineering', start: 0, end: 2, speaker: 1}],
        nextSpeaker: 2,
      })}\n`);
    });
    return true;
  };
  fakeWorker.stdin.end = () => {};

  const recordCodexNotes = vm.runInNewContext(`${source.slice(start, end)}; recordCodexNotes`, {
    process,
    Buffer,
    Promise,
    activeWc: {
      async executeJavaScript(script) {
        if (script.includes('notesStart')) return true;
        if (script.includes('notesTake')) {
          takeCount++;
          if (takeCount === 1) {
            return {
              audio: Buffer.from('fake-audio').toString('base64'),
              startedAtMs: 1700000000000,
              captions: [],
            };
          }
          meetingJoined = false;
          return null;
        }
        if (script.includes('micDiag().remoteCount')) return 1;
        if (script.includes('notesStop')) return null;
        return null;
      },
    },
    mkdtemp,
    writeFile,
    rm,
    join,
    tmpdir,
    homedir: () => '/Users/tester',
    runtimeConfig: {whisperModel: 'small'},
    __dirname: join(__dirname, '../NAIL/Resources'),
    nextNotesSpeaker: 1,
    notesWorker: null,
    notesFailed: false,
    stopping: false,
    get meetingJoined() { return meetingJoined; },
    listeningMode: 'notulen',
    spawn: () => {
      queueMicrotask(() => {
        fakeWorker.stdout.write(`${JSON.stringify({ready: true, speakerLabels: true})}\n`);
      });
      return fakeWorker;
    },
    createInterface: require('node:readline').createInterface,
    emitNotes: entries => emittedNotes.push(entries),
    emit: ev => emittedEvents.push(ev),
    codexWakeGate: {waitIfBusy: async () => true},
    attributeNotes: entries => entries,
    delay: async () => {},
    stopNotesWorker: () => {},
  });

  await recordCodexNotes();
  assert.equal(stdinWrites.length, 1);
  assert.equal(stdinWrites[0].mode, 'transcript');
  assert.match(stdinWrites[0].audio, /\.webm$/);
  assert.equal(emittedNotes.length, 1);
});

test('executeCodexTurnWithFollowUp records a completed follow-up turn even if isTurnRequested() flips true during that turn', async () => {
  const events = [];
  const latencyEntries = [];
  const notesMemory = createMeetingNotesMemory();
  let turnRequested = false;
  let followUpCalls = 0;

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript() { return null; },
  };

  const codexSession = {
    async runLiveTurn() {
      followUpCalls++;
      // User presses manual Tanya while follow-up speech reply is completing
      turnRequested = true;
      return {
        heard: 'Follow-up terakhir sebelum manual turn',
        reply: 'Jawaban follow-up tetap tercatat.',
        heardAtMs: 3000,
        replyAtMs: 3500,
        latencyMs: 500,
      };
    },
  };

  await executeCodexTurnWithFollowUp({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession,
    unmuteAndVerifyMicFn: async (_wc, _read, _click, state) => {
      state.restoreMute = true;
      return true;
    },
    restoreMeetMuteFn: async () => {},
    meetingNotes: notesMemory,
    emit: ev => events.push(ev),
    appendLatencyLogFn: entry => latencyEntries.push(buildLatencyLogEntry(entry)),
    isTurnRequested: () => turnRequested,
    platform: 'meet',
    provider: 'codex',
    mode: 'hands-free',
    executeTurn: async () => ({
      heard: 'Pertanyaan pertama',
      reply: 'Jawaban pertama.',
      heardAtMs: 1000,
      replyAtMs: 1500,
      latencyMs: 500,
    }),
  });

  assert.equal(followUpCalls, 1);
  const resultEvents = events.filter(e => e.startsWith('voice-result '));
  assert.equal(resultEvents.length, 2);
  assert.deepEqual(JSON.parse(resultEvents[1].slice('voice-result '.length)), {
    heard: 'Follow-up terakhir sebelum manual turn',
    reply: 'Jawaban follow-up tetap tercatat.',
    heardAtMs: 3000,
    replyAtMs: 3500,
    latencyMs: 500,
  });
  assert.equal(latencyEntries.length, 2);
  assert.equal(latencyEntries[1].mode, 'follow-up');
  assert.equal(notesMemory.count(), 4);
  // Should not emit voice-standby when exiting follow-up because a manual turn is requested
  assert.ok(!events.includes('voice-standby'));
});

test('executeCodexHandsFreeTurn logs voice-no-audio diagnostics on primary manual noAudio', async () => {
  const events = [];
  const loggedErrors = [];
  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      if (script.includes('__nailDiagnostics')) return {tracks: 0};
      return null;
    },
  };

  await executeCodexTurnWithFollowUp({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession: {},
    emit: ev => events.push(ev),
    logVoiceError: async err => { loggedErrors.push(err); },
    mode: 'manual',
    executeTurn: async () => ({noAudio: true}),
  });

  assert.equal(loggedErrors.length, 1);
  assert.match(loggedErrors[0].message, /voice-no-audio \(manual\)/);
  assert.equal(events.length, 1);
  assert.match(events[0], /^voice-no-audio /);
});

test('executeCodexHandsFreeTurn backs off on rapid null capture and suppresses redundant voice-standby emissions right after errors', async () => {
  const events = [];
  const delays = [];
  let nowMs = 10_000;
  const standbyState = {inStandby: false, lastVoiceErrorAt: 0};

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript() {
      // Rapid null capture (e.g., attachedTracks.size === 0, 10ms elapsed)
      nowMs += 10;
      return null;
    },
  };

  // Cycle 1: enters standby, emits voice-standby once, backs off 500ms on rapid null capture
  await executeCodexHandsFreeTurn({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession: {},
    checkCodexWake: async () => ({triggered: false}),
    emit: ev => events.push(ev),
    standbyState,
    nowFn: () => nowMs,
    delayFn: async ms => { delays.push(ms); nowMs += ms; },
  });

  assert.deepEqual(events, ['voice-standby']);
  assert.deepEqual(delays, [500]);
  assert.equal(standbyState.inStandby, true);

  // Cycle 2: already in standby -> suppresses duplicate voice-standby, still backs off 500ms on rapid null capture
  await executeCodexHandsFreeTurn({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession: {},
    checkCodexWake: async () => ({triggered: false}),
    emit: ev => events.push(ev),
    standbyState,
    nowFn: () => nowMs,
    delayFn: async ms => { delays.push(ms); nowMs += ms; },
  });

  assert.deepEqual(events, ['voice-standby']);
  assert.deepEqual(delays, [500, 500]);

  // Simulate a voice error just occurred 100ms ago: standby is cleared, but within 4s holdoff
  standbyState.inStandby = false;
  standbyState.lastVoiceErrorAt = nowMs - 100;

  await executeCodexHandsFreeTurn({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession: {},
    checkCodexWake: async () => ({triggered: false}),
    emit: ev => events.push(ev),
    standbyState,
    nowFn: () => nowMs,
    delayFn: async ms => { delays.push(ms); nowMs += ms; },
  });

  // Must NOT emit voice-standby within 4s of voice error
  assert.deepEqual(events, ['voice-standby']);
  assert.equal(standbyState.inStandby, false);

  // Advance clock past 4s error holdoff -> now emits voice-standby again
  nowMs += 4500;
  await executeCodexHandsFreeTurn({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession: {},
    checkCodexWake: async () => ({triggered: false}),
    emit: ev => events.push(ev),
    standbyState,
    nowFn: () => nowMs,
    delayFn: async ms => { delays.push(ms); nowMs += ms; },
  });

  assert.deepEqual(events, ['voice-standby', 'voice-standby']);
  assert.equal(standbyState.inStandby, true);
});

test('Meet join loop accepts state.inCall && !joined even when submitted === false', async () => {
  const source = readFileSync(join(__dirname, '../NAIL/Resources/meet.cjs'), 'utf8');
  const start = source.indexOf('    if (platform === \'meet\') {');
  const end = source.indexOf('    // Microsoft Teams guest join loop', start);

  const emitted = [];
  let readCount = 0;
  let notesSynced = false;
  let pollerStarted = false;
  let connectedEnsured = false;

  const runMeetLoop = vm.runInNewContext(`(async () => {\n${source.slice(start, end)}\n})`, {
    platform: 'meet',
    provider: 'codex',
    stopping: false,
    avatarSocketPath: null,
    avatarUnmuted: false,
    turnRequested: false,
    codexHandsFree: false,
    codexWakeFailed: false,
    followUpUntil: 0,
    meetingJoined: false,
    wc: {
      getURL: () => 'https://meet.google.com/abc-defg-hij',
      executeJavaScript: async () => true,
    },
    validNavigation: () => true,
    read: async () => {
      readCount++;
      // User manually clicked Join in browser window, so state.inCall is true while submitted is still false
      if (readCount === 1) return {inCall: true, signedIn: true};
      return {inCall: false, signedIn: true};
    },
    click: async () => false,
    emit: ev => emitted.push(ev),
    emitAvatarAudio: () => {},
    syncCodexNotes: () => { notesSynced = true; },
    slidePoller: {
      start: () => { pollerStarted = true; },
      stop: () => {},
    },
    codexSession: {
      ensureConnected: async () => { connectedEnsured = true; },
      dispose: async () => {},
    },
    voiceTurn: async () => {},
    gracefulLeaveCall: async () => 'left',
    delay: async () => {},
  });

  const outcome = await runMeetLoop();
  assert.equal(outcome, 'left');
  assert.ok(emitted.includes('joined'));
  assert.equal(notesSynced, true);
  assert.equal(pollerStarted, true);
  assert.equal(connectedEnsured, true);
});

test('inspectMeet() dispatches mousemove safely when MouseEvent is available and works when unavailable', () => {
  const dispatched = [];
  const prevDocument = global.document;
  const prevMouseEvent = global.MouseEvent;
  const prevGetComputedStyle = global.getComputedStyle;
  try {
    global.MouseEvent = class FakeMouseEvent {
      constructor(type, init) {
        this.type = type;
        this.init = init;
      }
    };
    global.getComputedStyle = () => ({visibility: 'visible'});
    global.document = {
      body: {
        innerText: '',
        dispatchEvent: ev => dispatched.push(ev),
      },
      querySelectorAll: () => [],
      getElementById: () => null,
      elementFromPoint: () => null,
    };

    const res = inspectMeet();
    assert.equal(dispatched.length, 1);
    assert.equal(dispatched[0].type, 'mousemove');
    assert.deepEqual(dispatched[0].init, {bubbles: true, clientX: 200, clientY: 200});
    assert.equal(res.inCall, false);

    // Also safe when MouseEvent is undefined
    delete global.MouseEvent;
    assert.doesNotThrow(() => inspectMeet());
  } finally {
    global.document = prevDocument;
    global.MouseEvent = prevMouseEvent;
    global.getComputedStyle = prevGetComputedStyle;
  }
});

test('Google Meet unmuteAndVerifyMic retries click(after.unmute) once if sending() is still false after 300ms', async () => {
  const source = readFileSync(join(__dirname, '../NAIL/Resources/meet.cjs'), 'utf8');
  const start = source.indexOf('  async function unmuteAndVerifyMic(');
  const end = source.indexOf('  async function restoreMeetMute(', start);

  let clickCount = 0;
  let sendingPolls = 0;
  const unmuteBtn = {x: 100, y: 200, name: 'Turn on microphone'};

  const unmuteAndVerifyMic = vm.runInNewContext(`${source.slice(start, end)}\n; unmuteAndVerifyMic`, {
    platform: 'meet',
    stopping: false,
    turnInterrupted: false,
    delay: async () => {},
    appendTeamsLog: () => {},
    saveNoMicDiag: async () => { assert.fail('Should not fail with saveNoMicDiag when retry succeeds'); },
  });

  const wc = {
    async executeJavaScript(script) {
      if (script.includes('__nailMedia.sending()')) {
        sendingPolls++;
        return clickCount >= 2 && sendingPolls >= 12;
      }
      return null;
    },
  };

  const state = {restoreMute: false};
  const ok = await unmuteAndVerifyMic(
    wc,
    async () => ({unmute: clickCount < 2 ? unmuteBtn : null, mute: null}),
    async () => {
      clickCount++;
      return true;
    },
    state
  );

  assert.equal(ok, true);
  assert.equal(clickCount, 2);
  assert.equal(state.restoreMute, true);
});

test('Follow-up voice-codex-no-transcript logs via logVoiceError, restores mute + Teams senders, emits voice-standby, and does not emit error event', async () => {
  const events = [];
  const jsCalls = [];
  const loggedErrors = [];
  let restoreMuteCalls = 0;

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      jsCalls.push(script);
      return null;
    },
  };

  const noTranscriptErr = new Error('voice-codex-no-transcript');
  const codexSession = {
    async runLiveTurn() {
      throw noTranscriptErr;
    },
  };

  await executeCodexTurnWithFollowUp({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession,
    unmuteAndVerifyMicFn: async (_wc, _read, _click, state) => {
      state.restoreMute = true;
      return true;
    },
    restoreMeetMuteFn: async (_wc, _read, _click, shouldRestore) => {
      if (shouldRestore) restoreMuteCalls++;
    },
    emit: ev => events.push(ev),
    appendLatencyLogFn: () => {},
    logVoiceError: async err => { loggedErrors.push(err); },
    platform: 'teams',
    provider: 'codex',
    mode: 'hands-free',
    executeTurn: async opts => {
      await opts.unmuteMeet();
      return {
        heard: 'Nail, apa kabar?',
        reply: 'Kabar baik, siap bantu rapat.',
        heardAtMs: 1000,
        replyAtMs: 1400,
        latencyMs: 400,
      };
    },
  });

  assert.deepEqual(loggedErrors, [noTranscriptErr]);
  assert.equal(restoreMuteCalls, 1);
  assert.ok(jsCalls.some(s => s.includes('restoreTeamsSenders')));
  assert.ok(events.includes('voice-followup'));
  assert.equal(events[events.length - 1], 'voice-standby');
  assert.equal(events.includes('voice-codex-no-transcript'), false);
  assert.equal(events.includes('voice-failed'), false);

  // Non-no-transcript follow-up error (e.g. voice-codex-quota) still surfaces as HUD error event
  const fatalEvents = [];
  const fatalLogged = [];
  const quotaErr = new Error('voice-codex-quota');
  await executeCodexTurnWithFollowUp({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession: {
      async runLiveTurn() {
        throw quotaErr;
      },
    },
    unmuteAndVerifyMicFn: async (_wc, _read, _click, state) => {
      state.restoreMute = true;
      return true;
    },
    restoreMeetMuteFn: async () => {},
    emit: ev => fatalEvents.push(ev),
    appendLatencyLogFn: () => {},
    logVoiceError: async err => { fatalLogged.push(err); },
    platform: 'meet',
    provider: 'codex',
    mode: 'hands-free',
    executeTurn: async opts => {
      await opts.unmuteMeet();
      return {heard: 'Halo', reply: 'Halo juga', heardAtMs: 100, replyAtMs: 200, latencyMs: 100};
    },
  });
  assert.deepEqual(fatalLogged, [quotaErr]);
  assert.ok(fatalEvents.includes('voice-codex-quota'));
  assert.equal(fatalEvents.includes('voice-standby'), false);

  // Primary manual turn throwing voice-codex-no-transcript still emits voice-codex-no-transcript
  const manualEvents = [];
  const manualLogged = [];
  await executeCodexTurnWithFollowUp({
    wc,
    read: async () => ({}),
    click: async () => true,
    codexSession: {},
    emit: ev => manualEvents.push(ev),
    appendLatencyLogFn: () => {},
    logVoiceError: async err => { manualLogged.push(err); },
    mode: 'manual',
    executeTurn: async () => {
      throw new Error('voice-codex-no-transcript');
    },
  });
  assert.equal(manualLogged.length, 1);
  assert.equal(manualLogged[0].message, 'voice-codex-no-transcript');
  assert.deepEqual(manualEvents, ['voice-codex-no-transcript']);
});

test('executeCodexHandsFreeTurn logs wake diagnostics via appendWakeDiagLogFn and appendWakeDiagLog writes valid JSONL', async () => {
  const diagEntries = [];
  const pcmBytes = Buffer.from([1, 0, -1, 0, 64, 2, -64, -2]);
  let nextClip = null;
  let nextWakeRes = null;

  const wc = {
    isDestroyed: () => false,
    async executeJavaScript(script) {
      if (script.includes('codexRecordWakePcm')) {
        return nextClip;
      }
      return null;
    },
  };

  const runCycle = async () => {
    await executeCodexHandsFreeTurn({
      wc,
      read: async () => ({}),
      click: async () => true,
      codexSession: {prewarmConnection: () => {}},
      checkCodexWake: async () => nextWakeRes,
      appendWakeDiagLogFn: entry => diagEntries.push(entry),
      runCodexTextTurn: async () => {},
      runCodexLiveTurn: async () => {},
      runCodexPresentationTurn: async () => {},
    });
  };

  // 1) triggered: false with non-empty raw -> logged
  nextClip = {
    pcmBase64: pcmBytes.toString('base64'),
    sampleRate: 16000,
    silenceWaitMs: 450,
    speechEndedAtMs: 1700000002000,
    durationMs: 220,
  };
  nextWakeRes = {
    triggered: false,
    raw: 'lanjut bahas agenda berikutnya',
    prompt: '',
    has_query: false,
    whisperMs: 95,
  };
  await runCycle();
  assert.equal(diagEntries.length, 1);
  assert.deepEqual(diagEntries[0], {
    triggered: false,
    raw: 'lanjut bahas agenda berikutnya',
    prompt: '',
    whisperMs: 95,
    durationMs: 220,
    pcmMode: true,
  });

  // 2) triggered: false with empty raw but durationMs >= 300 -> logged
  nextClip = {
    pcmBase64: pcmBytes.toString('base64'),
    sampleRate: 16000,
    silenceWaitMs: 450,
    speechEndedAtMs: 1700000003000,
    durationMs: 480,
  };
  nextWakeRes = {
    triggered: false,
    raw: '',
    prompt: '',
    has_query: false,
    whisperMs: 88,
  };
  await runCycle();
  assert.equal(diagEntries.length, 2);
  assert.deepEqual(diagEntries[1], {
    triggered: false,
    raw: '',
    prompt: '',
    whisperMs: 88,
    durationMs: 480,
    pcmMode: true,
  });

  // 3) triggered: false with empty raw and durationMs < 300 -> skipped
  nextClip = {
    pcmBase64: pcmBytes.toString('base64'),
    sampleRate: 16000,
    silenceWaitMs: 450,
    speechEndedAtMs: 1700000003500,
    durationMs: 180,
  };
  nextWakeRes = {
    triggered: false,
    raw: '   ',
    prompt: '',
    has_query: false,
    whisperMs: 50,
  };
  await runCycle();
  assert.equal(diagEntries.length, 2);

  // 4) triggered: true wake attempt -> logged
  nextClip = {
    pcmBase64: pcmBytes.toString('base64'),
    sampleRate: 16000,
    silenceWaitMs: 450,
    speechEndedAtMs: 1700000004000,
    durationMs: 1320,
  };
  nextWakeRes = {
    triggered: true,
    raw: 'Halo Nail tolong rangkum rapat',
    prompt: 'tolong rangkum rapat',
    has_query: true,
    whisperMs: 134,
  };
  await runCycle();
  assert.equal(diagEntries.length, 3);
  assert.deepEqual(diagEntries[2], {
    triggered: true,
    raw: 'Halo Nail tolong rangkum rapat',
    prompt: 'tolong rangkum rapat',
    whisperMs: 134,
    durationMs: 1320,
    pcmMode: true,
  });

  // 5) buildWakeDiagEntry and appendWakeDiagLog write valid JSONL
  const tempDir = mkdtempSync(join(tmpdir(), 'nail-wake-diag-test-'));
  const logFilePath = join(tempDir, 'Logs', 'Nail', 'wake-diag.jsonl');
  try {
    const written1 = appendWakeDiagLog({
      ts: '2026-11-24T02:50:00.000Z',
      ...diagEntries[0],
    }, {logFilePath});
    const written2 = appendWakeDiagLog({
      ts: '2026-11-24T02:50:05.000Z',
      ...diagEntries[2],
    }, {logFilePath});

    assert.deepEqual(written1, buildWakeDiagEntry({
      ts: '2026-11-24T02:50:00.000Z',
      ...diagEntries[0],
    }));
    assert.deepEqual(written2, {
      ts: '2026-11-24T02:50:05.000Z',
      triggered: true,
      raw: 'Halo Nail tolong rangkum rapat',
      prompt: 'tolong rangkum rapat',
      whisperMs: 134,
      durationMs: 1320,
      pcmMode: true,
    });

    const lines = readFileSync(logFilePath, 'utf8').trim().split('\n');
    assert.equal(lines.length, 2);
    assert.deepEqual(JSON.parse(lines[0]), written1);
    assert.deepEqual(JSON.parse(lines[1]), written2);

    // Safe error catching on FS failure
    const failed = appendWakeDiagLog(diagEntries[2], {
      logFilePath,
      appendFileSyncFn: () => { throw new Error('disk full'); },
    });
    assert.equal(failed, null);
  } finally {
    rmSync(tempDir, {recursive: true, force: true});
  }
});


