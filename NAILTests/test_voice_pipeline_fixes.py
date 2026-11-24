import argparse
import importlib.util
import io
import json
import os
import pathlib
import types
import unittest
from unittest.mock import Mock, patch

import numpy as np


path = pathlib.Path(__file__).resolve().parents[1] / "NAIL/Resources/agy-voice.py"
spec = importlib.util.spec_from_file_location("agy_voice", path)
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


class _FakeSegment:
    def __init__(self, text: str, *, no_speech_prob: float = 0.05, avg_logprob: float = -0.3, words=None):
        self.text = text
        self.no_speech_prob = no_speech_prob
        self.avg_logprob = avg_logprob
        self.words = words or []


class HallucinationAndNoiseFilterTests(unittest.TestCase):
    def test_hallucinated_phrases_are_rejected(self):
        for phantom in [
            "Terima kasih.",
            "Terima kasih banyak!",
            "Terima kasih kerana menonton.",
            "Thanks for watching.",
            "Selamat tinggal.",
            "Subtitles by Amara.org",
            "...",
        ]:
            self.assertTrue(pipeline.is_hallucinated_text(phantom), f"Expected phantom: {phantom}")

        for real in [
            "Nail, bagaimana jadwal rilis minggu ini?",
            "Tolong jelaskan estimasi waktunya.",
            "Oke, lanjut ke agenda berikutnya.",
            "Siap, terima kasih penjelasannya pak",
        ]:
            self.assertFalse(pipeline.is_hallucinated_text(real), f"Unexpected phantom flag: {real}")

    def test_detect_wake_utterance_ignores_hallucinations(self):
        self.assertEqual(
            pipeline.detect_wake_utterance("Terima kasih."),
            {"triggered": False, "has_query": False, "prompt": "", "raw": ""},
        )
        wake_query = pipeline.detect_wake_utterance("Nail, berapa anggaran bulan depan?")
        self.assertTrue(wake_query["triggered"])
        self.assertTrue(wake_query["has_query"])
        self.assertIn("anggaran", wake_query["prompt"])

        wake_only = pipeline.detect_wake_utterance("Halo Nail")
        self.assertTrue(wake_only["triggered"])
        self.assertFalse(wake_only["has_query"])

    def test_self_echo_filter_blocks_playback_leak_only(self):
        reply = "Untuk jadwal rilis fase pertama ditargetkan hari Kamis jam tiga sore ya."
        self.assertTrue(pipeline.is_self_echo("jadwal rilis fase pertama ditargetkan hari Kamis jam tiga sore", reply))
        self.assertTrue(pipeline.is_self_echo("ditargetkan hari Kamis jam tiga sore ya", reply))
        self.assertFalse(pipeline.is_self_echo("Bagaimana dengan backlog QA sebelum Kamis?", reply))

    def test_has_speech_energy_thresholds(self):
        silence = np.full(16000, 0.0004, dtype=np.float32)
        self.assertFalse(pipeline.has_speech_energy(silence))
        weak_noise = np.full(16000, 0.007, dtype=np.float32)
        self.assertFalse(
            pipeline.has_speech_energy(
                weak_noise,
                min_peak=pipeline.WAKE_MIN_PEAK,
                min_rms=pipeline.WAKE_MIN_RMS,
                min_active_ms=pipeline.WAKE_MIN_ACTIVE_MS,
            )
        )
        # Brief 40ms click inside 1s quiet room must fail wake active-duration pre-filter
        click_only = np.full(16000, 0.001, dtype=np.float32)
        t_click = np.linspace(0, 0.04, 640, endpoint=False, dtype=np.float32)
        click_only[3200:3840] = 0.08 * np.sin(2 * np.pi * 300 * t_click)
        self.assertFalse(
            pipeline.has_speech_energy(
                click_only,
                min_peak=pipeline.WAKE_MIN_PEAK,
                min_rms=pipeline.WAKE_MIN_RMS,
                min_active_ms=pipeline.WAKE_MIN_ACTIVE_MS,
            )
        )
        t = np.linspace(0, 1.0, 16000, endpoint=False, dtype=np.float32)
        speech = 0.05 * np.sin(2 * np.pi * 220 * t).astype(np.float32)
        self.assertTrue(pipeline.has_speech_energy(speech))
        # Soft real wake speech (~350ms active @ 0.035 amp inside 1s clip) passes wake pre-filter
        soft_wake = np.full(16000, 0.001, dtype=np.float32)
        t_word = np.linspace(0, 0.35, 5600, endpoint=False, dtype=np.float32)
        soft_wake[3200:8800] = 0.035 * np.sin(2 * np.pi * 210 * t_word)
        self.assertTrue(
            pipeline.has_speech_energy(
                soft_wake,
                min_peak=pipeline.WAKE_MIN_PEAK,
                min_rms=pipeline.WAKE_MIN_RMS,
                min_active_ms=pipeline.WAKE_MIN_ACTIVE_MS,
            )
        )


class WhisperTranscribeFilterTests(unittest.TestCase):
    def test_whisper_uses_vad_and_no_initial_prompt(self):
        calls = []

        class _FakeModel:
            def transcribe(self, audio, **kwargs):
                calls.append(kwargs)
                return [
                    _FakeSegment("Terima kasih.", no_speech_prob=0.91, avg_logprob=-0.4),
                    _FakeSegment("noise", no_speech_prob=0.1, avg_logprob=-1.5),
                    _FakeSegment("Apa kabar Nail?", no_speech_prob=0.05, avg_logprob=-0.25),
                ], None

        t = np.linspace(0, 1.0, 16000, endpoint=False, dtype=np.float32)
        speech = 0.05 * np.sin(2 * np.pi * 200 * t).astype(np.float32)
        heard = pipeline.transcribe(_FakeModel(), speech)

        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["beam_size"], 1)
        self.assertTrue(calls[0]["vad_filter"])
        self.assertFalse(calls[0]["condition_on_previous_text"])
        self.assertNotIn("initial_prompt", calls[0])
        self.assertEqual(heard, "Apa kabar Nail?")

    def test_run_turn_skips_follow_up_self_echo(self):
        t = np.linspace(0, 1.0, 16000, endpoint=False, dtype=np.float32)
        speech = 0.05 * np.sin(2 * np.pi * 200 * t).astype(np.float32)

        class _EchoModel:
            def transcribe(self, audio, **kwargs):
                return [_FakeSegment("Target rilis kita minggu depan hari Selasa.", no_speech_prob=0.04, avg_logprob=-0.2)], None

        fake_agy = Mock()
        with patch.object(pipeline, "decode_pcm16k", return_value=speech):
            out = pipeline.run_turn(
                _EchoModel(),
                fake_agy,
                pathlib.Path("/tmp/in.wav"),
                pathlib.Path("/tmp/out.wav"),
                require_wake=False,
                is_follow_up=True,
                recent_reply="Target rilis kita minggu depan hari Selasa ya pak.",
            )

        self.assertTrue(out["skipped"])
        self.assertEqual(out["reply"], "")
        fake_agy.ask.assert_not_called()


class AgySessionSyncAndRecoveryTests(unittest.TestCase):
    def test_ask_drains_stale_result_before_sending_new_question(self):
        stdout_r, stdout_w = os.pipe()
        stdin_r, stdin_w = os.pipe()
        stdout_file = os.fdopen(stdout_r, "r", encoding="utf-8", buffering=1)
        stdout_writer = os.fdopen(stdout_w, "w", encoding="utf-8", buffering=1)
        stdin_file = os.fdopen(stdin_w, "w", encoding="utf-8", buffering=1)
        stdin_reader = os.fdopen(stdin_r, "r", encoding="utf-8", buffering=1)

        try:
            session = pipeline.AgySession(system_prompt="test", model="auto")
            session.first_turn = False
            fake_proc = types.SimpleNamespace(
                poll=lambda: None,
                stdin=stdin_file,
                stdout=stdout_file,
                terminate=lambda: None,
                wait=lambda timeout=None: 0,
                kill=lambda: None,
            )
            session.proc = fake_proc

            # Pre-seed stale left-over response from an aborted previous turn
            stdout_writer.write(json.dumps({"event": "result", "result": {"status": "OK", "response": "STALE A1"}}) + "\n")
            stdout_writer.write(json.dumps({"event": "result", "result": {"status": "OK", "response": "FRESH A2"}}) + "\n")
            stdout_writer.flush()

            # Because _drain_pending_stdout drains everything currently readable before writing Q2,
            # patch _drain_pending_stdout to observe it drains first, then supply Q2 response when Q2 is written.
            session.close()
            # Re-test cleanly: put only stale line before ask(); once stdin receives Q2, write FRESH A2!
            r2, w2 = os.pipe()
            in_r2, in_w2 = os.pipe()
            out_r_f = os.fdopen(r2, "r", encoding="utf-8", buffering=1)
            out_w_f = os.fdopen(w2, "w", encoding="utf-8", buffering=1)
            in_w_f = os.fdopen(in_w2, "w", encoding="utf-8", buffering=1)
            in_r_f = os.fdopen(in_r2, "r", encoding="utf-8", buffering=1)
            try:
                out_w_f.write(json.dumps({"event": "result", "result": {"status": "OK", "response": "STALE A1"}}) + "\n")
                out_w_f.flush()

                written_prompts = []

                class _StdinProxy:
                    def write(self, data):
                        written_prompts.append(json.loads(data))
                        out_w_f.write(json.dumps({"event": "result", "result": {"status": "OK", "response": "FRESH A2"}}) + "\n")
                        out_w_f.flush()
                        return len(data)

                    def flush(self):
                        pass

                    def close(self):
                        pass

                session.proc = types.SimpleNamespace(
                    poll=lambda: None,
                    stdin=_StdinProxy(),
                    stdout=out_r_f,
                    terminate=lambda: None,
                    wait=lambda timeout=None: 0,
                    kill=lambda: None,
                )
                reply = session.ask("Pertanyaan dua?")
                self.assertEqual(reply, "FRESH A2")
                self.assertEqual(len(written_prompts), 1)
                self.assertIn("Pertanyaan dua?", written_prompts[0]["message"]["content"])
            finally:
                for fh in (out_r_f, out_w_f, in_w_f, in_r_f):
                    try:
                        fh.close()
                    except Exception:
                        pass
        finally:
            for fh in (stdout_file, stdout_writer, stdin_file, stdin_reader):
                try:
                    fh.close()
                except Exception:
                    pass

    def test_ask_closes_subprocess_on_timeout(self):
        r_fd, w_fd = os.pipe()
        out_r = os.fdopen(r_fd, "r", encoding="utf-8", buffering=1)
        out_w = os.fdopen(w_fd, "w", encoding="utf-8", buffering=1)
        terminated = []
        try:
            session = pipeline.AgySession(system_prompt="test", model="auto")
            session.first_turn = False
            session.proc = types.SimpleNamespace(
                poll=lambda: None,
                stdin=io.StringIO(),
                stdout=out_r,
                terminate=lambda: terminated.append("terminate"),
                wait=lambda timeout=None: 0,
                kill=lambda: terminated.append("kill"),
            )
            with self.assertRaises(TimeoutError):
                session.ask("Pertanyaan macet", timeout_s=0.05)
            self.assertEqual(terminated, ["terminate"])
            self.assertIsNone(session.proc)
            self.assertTrue(session.first_turn)
        finally:
            out_r.close()
            out_w.close()

    def test_ask_reads_multiple_json_lines_from_single_pipe_write_without_stalling(self):
        r_fd, w_fd = os.pipe()
        out_r = os.fdopen(r_fd, "r", encoding="utf-8", buffering=1)
        out_w = os.fdopen(w_fd, "w", encoding="utf-8", buffering=1)
        try:
            session = pipeline.AgySession(system_prompt="test", model="auto")
            session.first_turn = False

            class _BurstStdin:
                def write(self, data):
                    # Write two stream-json lines in a single OS pipe write (reproduces BufferedReader deadlock)
                    burst = (
                        json.dumps({"event": "assistant", "message": {"content": "Halo"}}) + "\n"
                        + json.dumps({"event": "result", "result": {"status": "OK", "response": "Jawaban cepat"}}) + "\n"
                    )
                    os.write(w_fd, burst.encode("utf-8"))
                    return len(data)

                def flush(self):
                    pass

                def close(self):
                    pass

            session.proc = types.SimpleNamespace(
                poll=lambda: None,
                stdin=_BurstStdin(),
                stdout=out_r,
                terminate=lambda: None,
                wait=lambda timeout=None: 0,
                kill=lambda: None,
            )
            reply = session.ask("Tes cepat?", timeout_s=1.0)
            self.assertEqual(reply, "Jawaban cepat")
        finally:
            out_r.close()
            out_w.close()


class DaemonRequestIdCorrelationTests(unittest.TestCase):
    def test_run_agy_daemon_preserves_request_ids_across_events(self):
        stdin_data = "\n".join([
            json.dumps({"id": 7, "from_wav": "/tmp/q.wav", "reply_wav": "/tmp/a.wav", "defer_reply": True}),
            json.dumps({"id": 7, "action": "continue"}),
            "",
        ])
        emitted = []

        def fake_run_turn(*args, **kwargs):
            req_id = kwargs["request_id"]
            pipeline._emit_daemon_line({"event": "wake", "heard": "apa kabar"}, request_id=req_id)
            pipeline._emit_daemon_line({"event": "transcribed", "heard": "apa kabar"}, request_id=req_id)
            return {"heard": "apa kabar", "reply": "Baik"}

        args = argparse.Namespace(
            tts_engine="edge",
            tts_voice="id-ID-GadisNeural",
            tts_rate=185,
            elevenlabs_voice_id="",
            elevenlabs_model="",
        )
        fake_agy = Mock()
        fake_whisper = Mock()
        fake_stdout = io.StringIO()
        with patch.object(pipeline, "run_turn", side_effect=fake_run_turn), \
             patch.object(pipeline.sys, "stdin", io.StringIO(stdin_data)), \
             patch.object(pipeline.sys, "stdout", fake_stdout):
            rc = pipeline._run_agy_daemon(fake_whisper, fake_agy, args)

        self.assertEqual(rc, 0)
        lines = [json.loads(line) for line in fake_stdout.getvalue().strip().splitlines()]
        self.assertEqual(lines[0], {"ready": True})
        self.assertEqual(lines[1], {"event": "wake", "heard": "apa kabar", "id": 7})
        self.assertEqual(lines[2], {"event": "transcribed", "heard": "apa kabar", "id": 7})
        self.assertEqual(lines[3], {"heard": "apa kabar", "reply": "Baik", "id": 7})
        fake_agy.warmup.assert_called_once()

    def test_transcribe_daemon_echoes_request_id_for_codex_wake(self):
        t = np.linspace(0, 1.0, 16000, endpoint=False, dtype=np.float32)
        speech = 0.05 * np.sin(2 * np.pi * 200 * t).astype(np.float32)

        class _WakeModel:
            def transcribe(self, audio, **kwargs):
                return [_FakeSegment("Halo Nail, jadwal besok jam berapa?", no_speech_prob=0.04, avg_logprob=-0.2)], None

        stdin_data = json.dumps({"id": 42, "audio": "/tmp/wake.webm", "mode": "wake"}) + "\n"
        fake_stdout = io.StringIO()
        with patch.object(pipeline, "decode_pcm16k", return_value=speech), \
             patch.object(pipeline.sys, "stdin", io.StringIO(stdin_data)), \
             patch.object(pipeline.sys, "stdout", fake_stdout):
            rc = pipeline._transcribe_daemon(_WakeModel(), None, 1)

        self.assertEqual(rc, 0)
        lines = [json.loads(line) for line in fake_stdout.getvalue().strip().splitlines()]
        self.assertTrue(lines[0]["ready"])
        self.assertEqual(lines[1]["id"], 42)
        self.assertTrue(lines[1]["triggered"])
        self.assertTrue(lines[1]["has_query"])
        self.assertIsInstance(lines[1]["whisperMs"], int)


class TranscribeDaemonOptimizationTests(unittest.TestCase):
    def _make_pcm_file(self, directory: pathlib.Path, name: str) -> tuple[pathlib.Path, np.ndarray]:
        t = np.linspace(0, 1.0, 16000, endpoint=False, dtype=np.float32)
        speech = (0.05 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)
        int16_pcm = (speech * 32768.0).astype("<i2")
        pcm_path = directory / name
        pcm_path.write_bytes(int16_pcm.tobytes())
        expected = int16_pcm.astype(np.float32) / 32768.0
        return pcm_path, expected

    def test_pcm16k_format_and_suffix_skip_ffmpeg_subprocess(self):
        import tempfile

        recorded_audio = []
        recorded_beams = []

        class _RecordingModel:
            def transcribe(self, audio, **kwargs):
                recorded_audio.append(audio)
                recorded_beams.append(kwargs.get("beam_size"))
                return [_FakeSegment("Halo Nail, cek suara.", no_speech_prob=0.04, avg_logprob=-0.2)], None

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            raw_no_ext, expected_fmt = self._make_pcm_file(tmp, "chunk.raw")
            pcm_ext, expected_ext = self._make_pcm_file(tmp, "chunk.pcm")

            stdin_data = "\n".join([
                json.dumps({"id": 1, "audio": str(raw_no_ext), "mode": "wake", "format": "pcm16k"}),
                json.dumps({"id": 2, "audio": str(pcm_ext), "mode": "wake-preview"}),
                "",
            ])
            fake_stdout = io.StringIO()
            with patch.object(pipeline.subprocess, "run", side_effect=AssertionError("ffmpeg must not be called")), \
                 patch.object(pipeline, "decode_pcm16k", side_effect=AssertionError("decode_pcm16k must not be called")), \
                 patch.object(pipeline.sys, "stdin", io.StringIO(stdin_data)), \
                 patch.object(pipeline.sys, "stdout", fake_stdout):
                rc = pipeline._transcribe_daemon(_RecordingModel(), None, 1)

        self.assertEqual(rc, 0)
        self.assertEqual(len(recorded_audio), 2)
        np.testing.assert_allclose(recorded_audio[0], expected_fmt, atol=1e-6)
        np.testing.assert_allclose(recorded_audio[1], expected_ext, atol=1e-6)
        self.assertEqual(recorded_beams, [1, 1])

        lines = [json.loads(line) for line in fake_stdout.getvalue().strip().splitlines()]
        self.assertEqual(len(lines), 3)
        self.assertEqual(lines[1]["id"], 1)
        self.assertEqual(lines[2]["id"], 2)
        self.assertIsInstance(lines[1]["whisperMs"], int)
        self.assertIsInstance(lines[2]["whisperMs"], int)

    def test_beam_size_by_mode_and_whisper_ms_in_all_responses(self):
        import tempfile

        recorded_beams = []

        class _BeamModel:
            def transcribe(self, audio, **kwargs):
                recorded_beams.append(kwargs.get("beam_size"))
                return [_FakeSegment("Halo Nail, catat rapat ini.", no_speech_prob=0.04, avg_logprob=-0.2)], None

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            pcm_path, _ = self._make_pcm_file(tmp, "sample.pcm")
            silence_path = tmp / "silence.pcm"
            silence_path.write_bytes(np.zeros(16000, dtype="<i2").tobytes())
            weak_noise_path = tmp / "weak_noise.pcm"
            t_noise = np.linspace(0, 1.0, 16000, endpoint=False, dtype=np.float32)
            weak_noise_pcm = ((0.010 * np.sin(2 * np.pi * 120 * t_noise)) * 32768.0).astype("<i2")
            weak_noise_path.write_bytes(weak_noise_pcm.tobytes())
            click_path = tmp / "click.pcm"
            click_arr = np.full(16000, 0.001, dtype=np.float32)
            click_arr[1600:2240] = 0.08 * np.sin(2 * np.pi * 300 * np.linspace(0, 0.04, 640, endpoint=False))
            click_path.write_bytes((click_arr * 32768.0).astype("<i2").tobytes())

            stdin_data = "\n".join([
                json.dumps({"id": 10, "audio": str(pcm_path), "mode": "wake"}),
                json.dumps({"id": 11, "audio": str(pcm_path), "mode": "wake-preview"}),
                json.dumps({"id": 12, "audio": str(pcm_path), "mode": "preview"}),
                json.dumps({"id": 13, "audio": str(pcm_path), "mode": "transcript"}),
                json.dumps({"id": 14, "audio": str(silence_path), "mode": "wake"}),
                json.dumps({"id": 15, "audio": "relative/path.pcm", "mode": "wake"}),
                json.dumps({"id": 16, "audio": str(weak_noise_path), "mode": "wake"}),
                json.dumps({"id": 17, "audio": str(click_path), "mode": "wake"}),
                "",
            ])
            fake_stdout = io.StringIO()
            with patch.object(pipeline.sys, "stdin", io.StringIO(stdin_data)), \
                 patch.object(pipeline.sys, "stdout", fake_stdout):
                rc = pipeline._transcribe_daemon(_BeamModel(), None, 1)

        self.assertEqual(rc, 0)
        # wake, wake-preview, preview -> beam_size=1; transcript -> beam_size=5 (weak_noise and click must skip Whisper)
        self.assertEqual(recorded_beams, [1, 1, 1, 5])

        lines = [json.loads(line) for line in fake_stdout.getvalue().strip().splitlines()]
        self.assertEqual(len(lines), 9)
        for resp in lines[1:]:
            self.assertIn("whisperMs", resp)
            self.assertIsInstance(resp["whisperMs"], int)
            self.assertGreaterEqual(resp["whisperMs"], 0)
        self.assertEqual(lines[5]["id"], 14)
        self.assertFalse(lines[5]["triggered"])
        self.assertEqual(lines[6]["id"], 15)
        self.assertIn("error", lines[6])
        self.assertEqual(lines[7]["id"], 16)
        self.assertFalse(lines[7]["triggered"])
        self.assertEqual(lines[7]["raw"], "")
        self.assertEqual(lines[8]["id"], 17)
        self.assertFalse(lines[8]["triggered"])
        self.assertEqual(lines[8]["raw"], "")

    def test_low_priority_flag_calls_os_nice_safely(self):
        with patch.object(pipeline.sys, "argv", ["agy-voice.py", "--transcribe-daemon", "--low-priority"]), \
             patch.object(pipeline.os, "nice") as nice_mock, \
             patch.object(pipeline, "WhisperModel", return_value=Mock()), \
             patch.object(pipeline, "_transcribe_daemon", return_value=0):
            rc = pipeline.main()
        self.assertEqual(rc, 0)
        nice_mock.assert_called_once_with(10)

        # os.nice failure must be swallowed safely
        with patch.object(pipeline.sys, "argv", ["agy-voice.py", "--transcribe-daemon", "--low-priority"]), \
             patch.object(pipeline.os, "nice", side_effect=PermissionError("not permitted")) as nice_err_mock, \
             patch.object(pipeline, "WhisperModel", return_value=Mock()), \
             patch.object(pipeline, "_transcribe_daemon", return_value=0):
            rc = pipeline.main()
        self.assertEqual(rc, 0)
        nice_err_mock.assert_called_once_with(10)

        # Without --low-priority, os.nice is not called
        with patch.object(pipeline.sys, "argv", ["agy-voice.py", "--transcribe-daemon"]), \
             patch.object(pipeline.os, "nice") as nice_unused_mock, \
             patch.object(pipeline, "WhisperModel", return_value=Mock()), \
             patch.object(pipeline, "_transcribe_daemon", return_value=0):
            rc = pipeline.main()
        self.assertEqual(rc, 0)
        nice_unused_mock.assert_not_called()


class WakePatternAndFfmpegAndNailLoopTests(unittest.TestCase):
    def test_expanded_wake_pattern_aliases_and_greeting_guards(self):
        for should_trigger in [
            "Nails, tolong cek jadwal.",
            "Naila, bagaimana progresnya?",
            "Halo Nayla, ada update?",
            "Halo naik, tolong bantu.",
            "Hei nabil, gimana hasilnya?",
            "Hai naik, coba cek lagi.",
            "Oke nabil, lanjutkan.",
            "Ok naik, siap.",
        ]:
            res = pipeline.detect_wake_utterance(should_trigger)
            self.assertTrue(res["triggered"], f"Expected wake trigger for: {should_trigger!r}")

        for should_not_trigger in [
            "Grafik penjualan naik terus bulan ini.",
            "Ya naik sedikit sih.",
            "Nabil baru saja masuk rapat.",
            "Ya nabil, nanti kita bahas.",
        ]:
            res = pipeline.detect_wake_utterance(should_not_trigger)
            self.assertFalse(res["triggered"], f"Unexpected wake trigger for: {should_not_trigger!r}")

    def test_decode_pcm16k_uses_ffmpeg_bin(self):
        fake_proc = types.SimpleNamespace(stdout=b"\x00\x00\x01\x00")
        with patch.object(pipeline, "_ffmpeg_bin", return_value="/custom/bin/ffmpeg"), \
             patch.object(pipeline.subprocess, "run", return_value=fake_proc) as run_mock:
            samples = pipeline.decode_pcm16k(pathlib.Path("/tmp/sample.webm"))
        self.assertEqual(len(samples), 2)
        run_mock.assert_called_once()
        cmd = run_mock.call_args.args[0]
        self.assertEqual(cmd[0], "/custom/bin/ffmpeg")

    def test_nail_loop_phonetic_wake_matching(self):
        import tempfile

        loop_path = pathlib.Path(__file__).resolve().parents[1] / "NAIL/Resources/nail-loop.py"
        loop_spec = importlib.util.spec_from_file_location("nail_loop", loop_path)
        nail_loop = importlib.util.module_from_spec(loop_spec)
        loop_spec.loader.exec_module(nail_loop)

        with tempfile.TemporaryDirectory() as tmpdir:
            work = pathlib.Path(tmpdir)
            for heard in ["Halo Nayla, cek dulu", "Nails, gimana?", "Nael tolong jelaskan", "Nayu coba jawab"]:
                with patch.object(nail_loop, "record", return_value=120), \
                     patch.object(nail_loop, "answer", return_value="Siap."):
                    out = nail_loop.run_turn(
                        pid=1,
                        seconds=1,
                        api_key="k",
                        work=work,
                        speak_out=False,
                        require="nail",
                        transcript=heard,
                    )
                self.assertFalse(out.get("skipped", False), f"Expected wake match for: {heard!r}")
                self.assertEqual(out["reply"], "Siap.")

            with patch.object(nail_loop, "record", return_value=120), \
                 patch.object(nail_loop, "answer") as answer_mock:
                skipped = nail_loop.run_turn(
                    pid=1,
                    seconds=1,
                    api_key="k",
                    work=work,
                    speak_out=False,
                    require="nail",
                    transcript="Pembahasan biasa tanpa nama.",
                )
                self.assertTrue(skipped["skipped"])
                answer_mock.assert_not_called()

            # Custom require word still uses literal substring matching
            with patch.object(nail_loop, "record", return_value=120), \
                 patch.object(nail_loop, "answer") as answer_mock:
                custom_skip = nail_loop.run_turn(
                    pid=1,
                    seconds=1,
                    api_key="k",
                    work=work,
                    speak_out=False,
                    require="kunci",
                    transcript="Halo Naila",
                )
                self.assertTrue(custom_skip["skipped"])
                answer_mock.assert_not_called()

            with patch.object(nail_loop, "record", return_value=120), \
                 patch.object(nail_loop, "answer", return_value="Oke."):
                custom_ok = nail_loop.run_turn(
                    pid=1,
                    seconds=1,
                    api_key="k",
                    work=work,
                    speak_out=False,
                    require="kunci",
                    transcript="Kata KUNCI ditemukan.",
                )
                self.assertFalse(custom_ok.get("skipped", False))
                self.assertEqual(custom_ok["reply"], "Oke.")


if __name__ == "__main__":
    unittest.main()
