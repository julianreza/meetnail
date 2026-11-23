const {test} = require('node:test');
const assert = require('node:assert/strict');
const {once} = require('node:events');
const {createConnection} = require('node:net');
const {mkdtemp, rm} = require('node:fs/promises');
const {join} = require('node:path');
const {listenForAvatarFrames, createMeetAvatarController, avatarSpeechTransition} = require('../NAIL/Resources/meet-avatar.cjs');

function packet(revision, value) {
  const payload = Buffer.from(value);
  const header = Buffer.alloc(8);
  header.writeUInt32BE(revision);
  header.writeUInt32BE(payload.length, 4);
  return Buffer.concat([header, payload]);
}

test('receives a fragmented frame, acknowledges drawing and rejects oversized frames', async t => {
  const dir = await mkdtemp('/tmp/nail-avatar-test-');
  t.after(() => rm(dir, {recursive: true, force: true}));
  const path = join(dir, 'frame');
  const frames = [];
  const server = await listenForAvatarFrames(path, async (revision, png) => {
    frames.push([revision, png.toString()]);
    return revision === 7;
  });
  const socket = createConnection(path);
  t.after(() => { socket.destroy(); server.close(); });
  await once(socket, 'connect');
  const frame = packet(7, 'png');
  socket.write(frame.subarray(0, 3));
  socket.write(frame.subarray(3));
  assert.deepEqual((await once(socket, 'data'))[0], Buffer.from([1]));
  socket.write(packet(6, 'stale'));
  assert.deepEqual((await once(socket, 'data'))[0], Buffer.from([0]));
  socket.write(packet(7, Buffer.alloc(1024 * 1024 + 1)).subarray(0, 8));
  await once(socket, 'close');
  assert.deepEqual(frames, [[7, 'png'], [6, 'stale']]);
});

test('a stale camera start cannot override the latest off request', async () => {
  const events = [];
  let completeStart;
  const controller = createMeetAvatarController({
    prepare: async () => true,
    setCamera: enabled => enabled ? new Promise(resolve => { completeStart = resolve; }) : true,
    stop: async () => {},
    emitState: (revision, state) => events.push([revision, state]),
  });
  await controller.request({revision: 1, enabled: true});
  const starting = controller.frameReady(1);
  await new Promise(setImmediate);
  const turningOff = controller.request({revision: 2, enabled: false});
  completeStart(true);
  await Promise.all([starting, turningOff]);
  assert.deepEqual(events.at(-1), [2, 'off']);
  assert.ok(!events.some(([revision, state]) => revision === 1 && state === 'on'));
  assert.equal(controller.accepts(1), false);
});

test('host video denial stops the synthetic source and reports unavailable', async () => {
  const events = [];
  const stopped = [];
  const controller = createMeetAvatarController({
    prepare: async () => true,
    setCamera: enabled => !enabled,
    stop: async revision => { stopped.push(revision); },
    emitState: (revision, state) => events.push([revision, state]),
  });
  await controller.request({revision: 1, enabled: true});
  await controller.frameReady(1);
  assert.deepEqual(events, [[1, 'starting'], [1, 'unavailable']]);
  assert.deepEqual(stopped, [1]);
  assert.equal(controller.accepts(1), false);
});

test('rapid on-off-on turns off any previous camera before replacing its stream', async () => {
  const calls = [];
  let completeStart;
  const controller = createMeetAvatarController({
    prepare: async revision => { calls.push(`prepare ${revision}`); return true; },
    setCamera: enabled => {
      calls.push(enabled ? 'camera on' : 'camera off');
      if (enabled && calls.length === 2) return new Promise(resolve => { completeStart = resolve; });
      return true;
    },
    stop: async () => {},
    emitState() {},
  });
  await controller.request({revision: 1, enabled: true});
  const first = controller.frameReady(1);
  await new Promise(setImmediate);
  const off = controller.request({revision: 2, enabled: false});
  const on = controller.request({revision: 3, enabled: true});
  completeStart(true);
  await Promise.all([first, off, on]);
  await controller.frameReady(3);
  await controller.close();
  assert.deepEqual(calls, ['prepare 1', 'camera on', 'camera off', 'prepare 3', 'camera on']);
});


test('continuous notulen does not end the animated speech turn', () => {
  assert.equal(avatarSpeechTransition('voice-sending'), 'start');
  assert.equal(avatarSpeechTransition('voice-notulen-codex {"text":"transcript"}'), null);
  assert.equal(avatarSpeechTransition('voice-notulen {"text":"transcript"}'), null);
  assert.equal(avatarSpeechTransition('voice-result {"reply":"done"}'), 'stop');
  assert.equal(avatarSpeechTransition('voice-interrupted'), 'stop');
});

function inspectCameraFixture({active, covered, cameraNotice, lobbyJoinLabel, hasRetry = true}) {
  const {runInNewContext} = require('node:vm');
  const {inspectMeet} = require('../NAIL/Resources/meet.cjs');
  const makeControl = (label, index) => ({
    innerText: label,
    getAttribute: () => null,
    getClientRects: () => [1],
    getBoundingClientRect: () => ({x: index, y: index, width: 2, height: 2}),
    matches: () => false,
    contains(target) { return this === target; },
  });
  const camera = makeControl(active ? 'Nonaktifkan kamera' : 'Aktifkan kamera', 1);
  const close = makeControl('Tutup', 2);
  const retry = makeControl('Coba lagi', 3);
  const leave = makeControl(lobbyJoinLabel ?? 'Tutup panggilan', 4);
  const dialog = {querySelectorAll: () => hasRetry ? [close, retry] : [close]};
  const heading = {...makeControl(cameraNotice, 5), closest: () => dialog};
  const controls = [camera, close, retry, leave];
  const document = {
    body: {innerText: ''},
    getElementById: () => null,
    querySelectorAll: selector => selector.startsWith('h1') ? [heading] : controls,
    elementFromPoint: (x) => covered && x === 2 ? null : controls[x - 2],
  };
  return runInNewContext(`(${inspectMeet})()`, {document, getComputedStyle: () => ({visibility: 'visible'})});
}

test('reports the enabled camera even when Meet overlays its button', () => {
  const state = inspectCameraFixture({active: true, covered: true, cameraNotice: 'Gemini tersedia'});
  assert.equal(state.cameraEnabled, true);
  assert.equal(state.disableCamera, null);
  assert.equal(state.dismissCameraNotice, null);
});

test('finds the close action scoped to the camera unavailable notice', () => {
  const state = inspectCameraFixture({active: false, covered: true, cameraNotice: 'Kamera tidak tersedia'});
  assert.equal(state.cameraEnabled, false);
  assert.equal(state.dismissCameraNotice?.name, 'Tutup');
});

test('finds the close action on a blocked camera warning with no retry button', () => {
  const state = inspectCameraFixture({active: true, covered: true, cameraNotice: 'Kamera mungkin diblokir', hasRetry: false});
  assert.equal(state.dismissCameraNotice?.name, 'Tutup');
});

test('recognizes the lobby join action when Meet cannot open the camera', () => {
  for (const lobbyJoinLabel of [
    'Bergabung sekarang tanpa kamera',
    'Minta untuk bergabung tanpa kamera',
    'Ask to join without camera',
    'Minta untuk bergabung',
  ]) {
    const state = inspectCameraFixture({active: true, cameraNotice: 'Kamera tidak tersedia', lobbyJoinLabel});
    assert.equal(state.inCall, false);
    assert.equal(state.enter?.name, lobbyJoinLabel);
  }
});

test('resets a camera that was already marked on before Nail provided a track', () => {
  const {meetAvatarCameraAction} = require('../NAIL/Resources/meet.cjs');
  const on = inspectCameraFixture({active: true, cameraNotice: ''});
  const off = inspectCameraFixture({active: false, cameraNotice: ''});
  assert.equal(meetAvatarCameraAction(on, true, false, false)?.name, 'Nonaktifkan kamera');
  assert.equal(meetAvatarCameraAction(on, true, false, true), null);
  assert.equal(meetAvatarCameraAction(off, true, false, true)?.name, 'Aktifkan kamera');
  assert.equal(meetAvatarCameraAction(on, true, true, true), null);
});
