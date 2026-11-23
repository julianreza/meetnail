import importlib.util
import io
import pathlib
import unittest
from unittest.mock import Mock, patch

try:
    import numpy as np
    import faster_whisper
except ImportError:
    np = None

pipeline = None
if np is not None:
    path = pathlib.Path(__file__).resolve().parents[1] / "NAIL/Resources/agy-voice.py"
    spec = importlib.util.spec_from_file_location("agy_voice", path)
    pipeline = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pipeline)


@unittest.skipIf(pipeline is None, "Install the Antigravity worker dependencies to run this test")
class PresentationHandshakeTests(unittest.TestCase):
    def test_supplied_answer_is_spoken_without_calling_provider(self):
        provider = Mock()
        with patch.object(pipeline, "decode_pcm16k", return_value=np.ones(100)), \
             patch.object(pipeline, "transcribe", return_value="Nail baca layar"), \
             patch.object(pipeline, "speak") as speak, \
             patch("sys.stdin", io.StringIO('{"action":"answer","text":"Teks 24"}\n')), \
             patch("sys.stdout", new_callable=io.StringIO) as output:
            result = pipeline.run_turn(Mock(), provider, pathlib.Path('/tmp/audio'), pathlib.Path('/tmp/reply'), defer_reply=True)
        self.assertEqual(result["reply"], "Teks 24")
        self.assertIn('"event": "transcribed"', output.getvalue())
        provider.ask.assert_not_called()
        speak.assert_called_once()

    def test_cancelled_turn_does_not_answer_or_speak(self):
        provider = Mock()
        with patch.object(pipeline, "decode_pcm16k", return_value=np.ones(100)), \
             patch.object(pipeline, "transcribe", return_value="Nail baca layar"), \
             patch.object(pipeline, "speak") as speak, \
             patch("sys.stdin", io.StringIO('{"action":"cancel"}\n')), \
             patch("sys.stdout", new_callable=io.StringIO):
            result = pipeline.run_turn(Mock(), provider, pathlib.Path('/tmp/audio'), pathlib.Path('/tmp/reply'), defer_reply=True)
        self.assertTrue(result["skipped"])
        provider.ask.assert_not_called()
        speak.assert_not_called()


if __name__ == "__main__":
    unittest.main()
