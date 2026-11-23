import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch


path = pathlib.Path(__file__).resolve().parents[1] / "NAIL/Resources/nail-loop.py"
spec = importlib.util.spec_from_file_location("nail_loop", path)
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


class PresentationPipelineTests(unittest.TestCase):
    def test_transcription_can_be_returned_before_answering(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(pipeline, "record", return_value=1), \
             patch.object(pipeline, "transcribe", return_value='{"text":"Baca layar"}'), \
             patch.object(pipeline, "answer") as answer:
            result = pipeline.run_turn(None, 1, "key", pathlib.Path(directory), False, transcribe_only=True)
        self.assertEqual(result["heard"], "Baca layar")
        answer.assert_not_called()

    def test_existing_transcript_is_used_without_retranscribing(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(pipeline, "record", return_value=1), \
             patch.object(pipeline, "transcribe") as transcribe, \
             patch.object(pipeline, "answer", return_value="Jawaban"):
            result = pipeline.run_turn(None, 1, "key", pathlib.Path(directory), False, transcript="Halo")
        self.assertEqual(result["reply"], "Jawaban")
        transcribe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
