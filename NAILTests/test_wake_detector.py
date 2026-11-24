"""Regression samples are synthetic Indonesian speech, not meeting recordings."""
import importlib.util
import pathlib
import unittest
import wave

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('nail_wake', ROOT / 'NAIL/Resources/nail-wake.py')
wake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wake)


class WakeDetectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spotter = wake.make_spotter(ROOT / 'NAIL/Resources/wake-model')

    def sample(self, name):
        with wave.open(str(ROOT / 'NAILTests/fixtures/wake' / name)) as audio:
            self.assertEqual((audio.getframerate(), audio.getnchannels(), audio.getsampwidth()), (16000, 1, 2))
            return np.frombuffer(audio.readframes(audio.getnframes()), dtype='<i2').astype(np.float32) / 32768

    def test_detects_nail_in_indonesian_sentence(self):
        self.assertTrue(wake.detect(self.spotter, self.sample('nail-indonesian-synthetic.wav')))

    def test_detects_standalone_nail_call(self):
        self.assertTrue(wake.detect(self.spotter, self.sample('nail-only-indonesian-synthetic.wav')))

    def test_does_not_trigger_on_other_indonesian_speech(self):
        self.assertFalse(wake.detect(self.spotter, self.sample('other-indonesian-synthetic.wav')))

    def test_does_not_trigger_on_similar_indonesian_words(self):
        self.assertFalse(wake.detect(self.spotter, self.sample('naik-nilai-indonesian-synthetic.wav')))


if __name__ == '__main__':
    unittest.main()
