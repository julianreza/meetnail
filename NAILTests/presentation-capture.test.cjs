const {test} = require('node:test');
const assert = require('node:assert/strict');
const {findMeetPresentation, captureMeetPresentation, createPresentationOCRBridge, presentationRequestKind, shouldReadPresentation} = require('../NAIL/Resources/meet.cjs');
const {CodexLiveSession, visionMcpOverrides} = require('../NAIL/Resources/codex-voice.cjs');

function makeVideo({marker = true, tile = 'presenter-1', x = 16, y = 118, width = 910, height = 569, ready = 4} = {}) {
  const tileElement = {
    getAttribute: () => tile,
    getBoundingClientRect: () => ({x, y, width, height, right: x + width, bottom: y + height}),
    querySelectorAll: () => [{getAttribute: () => marker ? 'Lepaskan presentasi dari layar utama' : 'Sematkan kamera ke layar utama'}],
  };
  return {
    readyState: ready,
    getBoundingClientRect: () => ({x, y, width, height, right: x + width, bottom: y + height}),
    closest: selector => {
      if (selector === '[data-tile-media-id]') return tile ? tileElement : null;
      return null;
    },
  };
}

function inspect(videos) {
  const previousDocument = global.document;
  global.document = {querySelectorAll: () => videos};
  try { return findMeetPresentation(); }
  finally { global.document = previousDocument; }
}

test('finds one live presentation and ignores camera video', () => {
  assert.deepEqual(inspect([makeVideo({marker: false}), makeVideo()]), {
    tileId: 'presenter-1', rect: {x: 16, y: 118, width: 910, height: 569},
  });
});

test('rejects missing, ambiguous, or unready presentation', () => {
  assert.equal(inspect([]), null);
  assert.equal(inspect([makeVideo(), makeVideo({tile: 'presenter-2'})]), null);
  assert.equal(inspect([makeVideo({ready: 1})]), null);
  assert.equal(inspect([makeVideo({tile: ''})]), null);
});

test('captures only the presentation rectangle in a hidden page', async () => {
  const presentation = {tileId: 'presenter-1', rect: {x: 16, y: 118, width: 910, height: 569}};
  const captures = [];
  const wc = {
    executeJavaScript: async () => presentation,
    capturePage: async (rect, options) => {
      captures.push({rect, options});
      return {isEmpty: () => false, toPNG: () => Buffer.from('image')};
    },
  };
  assert.deepEqual(await captureMeetPresentation(wc), Buffer.from('image'));
  assert.deepEqual(captures, [{rect: presentation.rect, options: {stayHidden: true}}]);
});

test('rejects a missing or changed source and cancellation', async () => {
  const presentation = {tileId: 'presenter-1', rect: {x: 16, y: 118, width: 910, height: 569}};
  let captureCount = 0;
  let reads = [null];
  const wc = {
    executeJavaScript: async () => reads.shift(),
    capturePage: async () => { captureCount++; return {isEmpty: () => false, toPNG: () => Buffer.from('image')}; },
  };
  assert.equal(await captureMeetPresentation(wc), null);
  assert.equal(captureCount, 0);
  reads = [presentation, {...presentation, tileId: 'presenter-2'}];
  assert.equal(await captureMeetPresentation(wc), null);
  reads = [presentation, {...presentation, rect: {...presentation.rect, x: 20}}];
  assert.equal(await captureMeetPresentation(wc), null);
  const controller = new AbortController();
  controller.abort();
  assert.equal(await captureMeetPresentation(wc, controller.signal), null);
});

test('OCR bridge sends one image and matches its response', async () => {
  const events = [];
  const bridge = createPresentationOCRBridge(event => events.push(event));
  const result = bridge.recognize(Buffer.from('image'));
  const payload = JSON.parse(events[0].slice('presentation-ocr '.length));
  assert.equal(payload.image, Buffer.from('image').toString('base64'));
  bridge.receive({id: payload.id.toUpperCase(), text: 'Error 7249'});
  assert.equal(await result, 'Error 7249');
});

test('OCR bridge cancels pending requests on interrupt', async () => {
  const events = [];
  const bridge = createPresentationOCRBridge(event => events.push(event));
  const controller = new AbortController();
  const result = bridge.recognize(Buffer.from('image'), controller.signal);
  controller.abort();
  await assert.rejects(result, {name: 'AbortError'});
  const payload = JSON.parse(events[0].slice('presentation-ocr '.length));
  assert.equal(bridge.receive({id: payload.id, text: 'late'}), false);
});

test('routes explicit presentation questions and leaves ordinary questions alone', () => {
  assert.equal(presentationRequestKind('Nail, bacakan error di layar'), 'text');
  assert.equal(presentationRequestKind('Nail, jelaskan grafik di slide ini'), 'visual');
  assert.equal(presentationRequestKind('Nail, kapan rilis?'), null);
  assert.equal(presentationRequestKind('Nail, lanjutkan'), null);
});

test('presentation routing is disabled for Teams or when the setting is off', () => {
  assert.equal(shouldReadPresentation('teams', true, 'Baca layar'), false);
  assert.equal(shouldReadPresentation('meet', false, 'Baca layar'), false);
  assert.equal(shouldReadPresentation('meet', true, 'Baca layar'), true);
  assert.equal(shouldReadPresentation('meet', true, 'Kapan rilis?'), false);
});

test('vision turn returns the completed response for the attached image', async () => {
  const session = new CodexLiveSession({visionOnly: true});
  session.threadId = 'vision-thread';
  session.warmup = async () => {};
  session.callRpc = async (method, params) => {
    assert.equal(method, 'turn/start');
    assert.equal(params.input[1].type, 'localImage');
    assert.equal(params.input[1].path, '/tmp/test.png');
    queueMicrotask(() => {
      session.handleRpcLine(JSON.stringify({method: 'item/completed', params: {threadId: 'vision-thread', item: {type: 'agentMessage', text: 'Nilainya 24.'}}}));
      session.handleRpcLine(JSON.stringify({method: 'turn/completed', params: {threadId: 'vision-thread', turn: {status: 'completed'}}}));
    });
    return {};
  };
  assert.equal(await session.analyzeImage('/tmp/test.png', 'Berapa nilainya?'), 'Nilainya 24.');
});

test('vision turn fails on cancellation or a failed model turn', async () => {
  const session = new CodexLiveSession({visionOnly: true});
  session.threadId = 'vision-thread';
  session.warmup = async () => {};
  session.callRpc = async () => {
    queueMicrotask(() => session.handleRpcLine(JSON.stringify({method: 'turn/completed', params: {threadId: 'vision-thread', turn: {status: 'failed'}}})));
    return {};
  };
  await assert.rejects(session.analyzeImage('/tmp/test.png', 'Pertanyaan'), /presentation-vision-failed/);
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(session.analyzeImage('/tmp/test.png', 'Pertanyaan', controller.signal), {name: 'AbortError'});
});

test('vision configuration disables every configured MCP server', () => {
  assert.deepEqual(visionMcpOverrides({mcp_servers: {node_repl: {}, 'local-agent': {}}}), [
    '-c', 'mcp_servers.node_repl.enabled=false',
    '-c', 'mcp_servers.local-agent.enabled=false',
  ]);
  assert.throws(() => visionMcpOverrides({mcp_servers: {'name.with.dots': {}}}), /presentation-vision-tools-enabled/);
});
