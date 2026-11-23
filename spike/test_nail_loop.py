import pathlib
import runpy
import tempfile
import unittest
import wave
from unittest.mock import patch


class NailLoopTest(unittest.TestCase):
    def test_digital_silence_never_reaches_asr(self):
        run_turn = runpy.run_path(str(pathlib.Path(__file__).with_name("nail-loop.py")))["run_turn"]
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            source = work / "silence.wav"
            with wave.open(str(source), "wb") as wav:
                wav.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                wav.writeframes(bytes(32000))
            with patch.dict(run_turn.__globals__, transcribe=lambda *_: self.fail("silence was sent to ASR")):
                result = run_turn(None, 1, "unused", work, False, source=source)
            self.assertEqual(result, {"rms": 0, "heard": "", "skipped": True})


if __name__ == "__main__":
    unittest.main()
