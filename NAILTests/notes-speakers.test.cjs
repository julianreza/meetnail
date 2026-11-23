const {test} = require('node:test');
const assert = require('node:assert/strict');
const {attributeNotes} = require('../NAIL/Resources/meet.cjs');

test('only unambiguous captions near the utterance can replace its local speaker label', () => {
  const utterance = {text: 'Produk ini rilis hari Jumat.', start: 2, end: 4, speaker: 2};
  const rina = {speaker: 'Rina', text: 'Baik, produk ini rilis hari Jumat ya.', seenAtMs: 105000};
  const budi = {speaker: 'Budi', text: rina.text, seenAtMs: 105500};
  const resolve = (captions, entry = utterance) => attributeNotes([entry], 100000, captions)[0];
  assert.deepEqual(resolve([rina]), {text: utterance.text, speaker: 'Rina', timestampMs: 102000});
  assert.equal(resolve([rina, budi]).speaker, 'Pembicara 2');
  assert.equal(resolve([{...rina, seenAtMs: 125000}]).speaker, 'Pembicara 2');
  assert.equal(resolve([{...rina, text: 'Produk ini batal rilis.'}]).speaker, 'Pembicara 2');
  assert.equal(resolve([rina], {...utterance, text: 'hari Jumat', speaker: null}).speaker, 'Pembicara tidak diketahui');
});
