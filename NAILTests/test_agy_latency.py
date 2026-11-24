import argparse
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import threading
import time
import types
import unittest
from unittest.mock import Mock, patch

import numpy as np


path = pathlib.Path(__file__).resolve().parents[1] / "NAIL/Resources/agy-voice.py"
spec = importlib.util.spec_from_file_location("agy_voice", path)
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


class _FakeSegment:
    def __init__(self, text: str, *, no_speech_prob: float = 0.05, avg_logprob: float = -0.25):
        self.text = text
        self.no_speech_prob = no_speech_prob
        self.avg_logprob = avg_logprob
        self.words = []


def _write_pcm_speech(dest: pathlib.Path) -> np.ndarray:
    t = np.linspace(0, 0.8, 12800, endpoint=False, dtype=np.float32)
    speech = (0.06 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)
    int16 = (speech * 32768.0).astype("<i2")
    dest.write_bytes(int16.tobytes())
    return int16.astype(np.float32) / 32768.0


class RawPcmInputInRunTurnTests(unittest.TestCase):
    def test_pcm16k_format_and_pcm_suffix_skip_ffmpeg(self):
        seen_audio = []

        class _Model:
            def transcribe(self, audio, **kwargs):
                seen_audio.append(audio)
                return [_FakeSegment("Halo Nail, tes cepat.")], None

        agy = Mock()
        agy.ask.return_value = "Siap, aman."

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = pathlib.Path(tmp)
            raw_path = tmp_dir / "capture.raw"
            pcm_path = tmp_dir / "meeting.pcm"
            reply_wav = tmp_dir / "reply.wav"
            exp_raw = _write_pcm_speech(raw_path)
            exp_pcm = _write_pcm_speech(pcm_path)

            with patch.object(pipeline, "decode_pcm16k", side_effect=AssertionError("ffmpeg decode must not run")), \
                 patch.object(pipeline, "speak", return_value={"engine_used": "edge"}):
                out1 = pipeline.run_turn(_Model(), agy, raw_path, reply_wav, input_format="pcm16k")
                out2 = pipeline.run_turn(_Model(), agy, pcm_path, reply_wav)

        self.assertEqual(out1["reply"], "Siap, aman.")
        self.assertEqual(out2["reply"], "Siap, aman.")
        np.testing.assert_allclose(seen_audio[0], exp_raw, atol=1e-6)
        np.testing.assert_allclose(seen_audio[1], exp_pcm, atol=1e-6)

    def test_webm_input_still_uses_decode_pcm16k(self):
        t = np.linspace(0, 0.5, 8000, endpoint=False, dtype=np.float32)
        speech = (0.06 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)

        class _Model:
            def transcribe(self, audio, **kwargs):
                return [_FakeSegment("Cek format webm.")], None

        agy = Mock()
        agy.ask.return_value = "Oke."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = pathlib.Path(tmp)
            webm_path = tmp_dir / "meeting.webm"
            webm_path.write_bytes(b"WEBM")
            with patch.object(pipeline, "decode_pcm16k", return_value=speech) as dec_mock, \
                 patch.object(pipeline, "speak", return_value={"engine_used": "edge"}):
                out = pipeline.run_turn(_Model(), agy, webm_path, tmp_dir / "reply.wav")
        dec_mock.assert_called_once()
        self.assertEqual(out["reply"], "Oke.")


class SentenceSplittingTests(unittest.TestCase):
    def test_incremental_splitting_respects_numbers_abbreviations_and_short_fragments(self):
        buf = "Harganya Rp. 50.000 saja, ya... "
        chunks, rest = pipeline._extract_ready_sentences(buf, flush=False)
        self.assertEqual(chunks, [])
        self.assertEqual(rest, buf)

        # Short leading sentence ("Oke.") must merge with the next sentence rather than splitting alone.
        chunks_short, rest_short = pipeline._extract_ready_sentences(
            "Oke. Ini kalimat pertama yang cukup panjang. Lalu ini kalimat kedua",
            flush=False,
        )
        self.assertEqual(chunks_short, ["Oke. Ini kalimat pertama yang cukup panjang."])
        self.assertEqual(rest_short, "Lalu ini kalimat kedua")

        final_chunks, final_rest = pipeline._extract_ready_sentences(rest_short + "!", flush=True)
        self.assertEqual(final_chunks, ["Lalu ini kalimat kedua!"])
        self.assertEqual(final_rest, "")

    def test_single_short_reply_flushes_cleanly(self):
        chunks, rest = pipeline._extract_ready_sentences("Siap!", flush=True)
        self.assertEqual(chunks, ["Siap!"])
        self.assertEqual(rest, "")


class StreamingAudioChunkAndOrderingTests(unittest.TestCase):
    def test_incremental_agy_deltas_emit_chunk0_before_llm_finishes_and_keep_order(self):
        r_fd, w_fd = os.pipe()
        out_r = os.fdopen(r_fd, "r", encoding="utf-8", buffering=1)
        try:
            session = pipeline.AgySession(model="auto")
            session.first_turn = False
            chunk0_emitted = threading.Event()

            class _StreamingStdin:
                def write(self, data):
                    def _feed():
                        ev1 = {"event": "step_update", "step_update": {"step_type": "agent_response", "text_delta": "Kalimat pertama sudah selesai diucapkan. "}}
                        os.write(w_fd, (json.dumps(ev1) + "\n").encode("utf-8"))
                        # Wait until chunk 0 is actually synthesized and emitted before sending sentence 2!
                        chunk0_emitted.wait(timeout=2.0)
                        ev2 = {"event": "step_update", "step_update": {"step_type": "agent_response", "text_delta": "Kalimat kedua menyusul di belakang."}}
                        ev_done = {"event": "result", "result": {"status": "SUCCESS", "response": "Kalimat pertama sudah selesai diucapkan. Kalimat kedua menyusul di belakang."}}
                        os.write(w_fd, (json.dumps(ev2) + "\n" + json.dumps(ev_done) + "\n").encode("utf-8"))

                    threading.Thread(target=_feed, daemon=True).start()
                    return len(data)

                def flush(self):
                    pass

                def close(self):
                    pass

            session.proc = types.SimpleNamespace(
                poll=lambda: None,
                stdin=_StreamingStdin(),
                stdout=out_r,
                terminate=lambda: None,
                wait=lambda timeout=None: 0,
                kill=lambda: None,
            )

            class _Model:
                def transcribe(self, audio, **kwargs):
                    return [_FakeSegment("Halo Nail, jelaskan dua hal.")], None

            emitted_lines = []

            def fake_emit(payload, request_id=None):
                if request_id is not None:
                    payload = {"id": request_id, **payload}
                emitted_lines.append(payload)
                if payload.get("event") == "audio_chunk" and payload.get("index") == 0:
                    chunk0_emitted.set()

            def fake_speak(text, out_wav, **kwargs):
                out_wav.write_bytes(b"RIFF" + text.encode("utf-8"))
                return {"engine_used": "elevenlabs"}

            with tempfile.TemporaryDirectory() as tmp:
                tmp_dir = pathlib.Path(tmp)
                pcm_path = tmp_dir / "meeting.pcm"
                _write_pcm_speech(pcm_path)
                reply_wav = tmp_dir / "reply.wav"

                with patch.object(pipeline, "_emit_daemon_line", side_effect=fake_emit), \
                     patch.object(pipeline, "speak", side_effect=fake_speak):
                    out = pipeline.run_turn(
                        _Model(),
                        session,
                        pcm_path,
                        reply_wav,
                        request_id=11,
                        stream_audio=True,
                        tts_engine="elevenlabs",
                    )

            self.assertTrue(chunk0_emitted.is_set(), "chunk 0 must be emitted before agy finishes sentence 2")
            audio_events = [m for m in emitted_lines if m.get("event") == "audio_chunk"]
            self.assertEqual([e["index"] for e in audio_events], [0, 1])
            self.assertEqual(audio_events[0]["id"], 11)
            self.assertFalse(audio_events[0]["final"])
            self.assertTrue(audio_events[1]["final"])
            self.assertTrue(audio_events[0]["wav"].endswith("reply.chunk0.wav"))
            self.assertTrue(audio_events[1]["wav"].endswith("reply.chunk1.wav"))
            self.assertEqual(pathlib.Path(audio_events[0]["wav"]).parent, tmp_dir.resolve())
            self.assertTrue(out["streamed"])
            self.assertEqual(out["chunks"], 2)
            self.assertEqual(out["tts_engine_used"], "elevenlabs")
            for k in ("asr_s", "llm_first_s", "llm_s", "tts_first_s", "tts_s", "ttfa_s", "total_s"):
                self.assertIn(k, out)
                self.assertIsInstance(out[k], float)
        finally:
            out_r.close()
            try:
                os.close(w_fd)
            except OSError:
                pass

    def test_parallel_tts_chunks_always_emit_in_deterministic_index_order(self):
        class _Model:
            def transcribe(self, audio, **kwargs):
                return [_FakeSegment("Tes urutan chunk.")], None

        agy = Mock()
        agy.ask.return_value = "Kalimat nol harus keluar pertama. Kalimat satu selesai lebih cepat!"
        emitted = []

        def fake_emit(payload, request_id=None):
            emitted.append(payload)

        def slow_first_speak(text, out_wav, **kwargs):
            if "Kalimat nol" in text:
                time.sleep(0.08)
            out_wav.write_bytes(b"RIFF")
            return {"engine_used": "edge"}

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = pathlib.Path(tmp)
            pcm_path = tmp_dir / "meeting.pcm"
            _write_pcm_speech(pcm_path)
            with patch.object(pipeline, "_emit_daemon_line", side_effect=fake_emit), \
                 patch.object(pipeline, "speak", side_effect=slow_first_speak):
                out = pipeline.run_turn(_Model(), agy, pcm_path, tmp_dir / "reply.wav", stream_audio=True)

        chunks = [e for e in emitted if e.get("event") == "audio_chunk"]
        self.assertEqual([c["index"] for c in chunks], [0, 1])
        self.assertFalse(chunks[0]["final"])
        self.assertTrue(chunks[1]["final"])
        self.assertEqual(out["chunks"], 2)

    def test_defer_reply_answer_with_stream_audio_emits_chunks(self):
        class _Model:
            def transcribe(self, audio, **kwargs):
                return [_FakeSegment("Nail baca layar")], None

        emitted = []
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = pathlib.Path(tmp)
            pcm_path = tmp_dir / "meeting.pcm"
            _write_pcm_speech(pcm_path)
            with patch.object(pipeline, "_emit_daemon_line", side_effect=lambda p, request_id=None: emitted.append(p)), \
                 patch.object(pipeline, "speak", side_effect=lambda t, w, **kw: (w.write_bytes(b"RIFF"), {"engine_used": "edge"})[1]), \
                 patch("sys.stdin", io.StringIO('{"action":"answer","text":"Slide membahas target Q3. Target naik dua puluh persen."}\n')):
                out = pipeline.run_turn(
                    _Model(),
                    Mock(),
                    pcm_path,
                    tmp_dir / "reply.wav",
                    defer_reply=True,
                    stream_audio=True,
                )

        self.assertTrue(out["streamed"])
        self.assertEqual(out["chunks"], 2)
        chunk_events = [e for e in emitted if e.get("event") == "audio_chunk"]
        self.assertEqual(len(chunk_events), 2)
        self.assertTrue(chunk_events[1]["final"])


class MidTurnCancelAndSessionPreservationTests(unittest.TestCase):
    def test_mid_llm_cancel_preserves_agy_session_and_next_turn_drains_stale_result(self):
        r_fd, w_fd = os.pipe()
        out_r = os.fdopen(r_fd, "r", encoding="utf-8", buffering=1)
        terminated = []
        prompts_written = []
        turn_counter = 0

        try:
            session = pipeline.AgySession(model="auto")
            session.first_turn = False
            cancel_ev = threading.Event()
            delta_seen = threading.Event()

            class _CancelableStdin:
                def write(self, data):
                    nonlocal turn_counter
                    turn_counter += 1
                    prompts_written.append(json.loads(data))
                    current_turn = turn_counter

                    def _emit_turn():
                        if current_turn == 1:
                            ev1 = {"event": "step_update", "step_update": {"step_type": "agent_response", "text_delta": "Sebagian jawaban..."}}
                            os.write(w_fd, (json.dumps(ev1) + "\n").encode("utf-8"))
                            delta_seen.set()
                            # Delayed result arrives after cancel!
                            time.sleep(0.08)
                            ev_res = {"event": "result", "result": {"status": "SUCCESS", "response": "Jawaban turn satu yang dibatalkan."}}
                            os.write(w_fd, (json.dumps(ev_res) + "\n").encode("utf-8"))
                        else:
                            ev_res2 = {"event": "result", "result": {"status": "SUCCESS", "response": "Jawaban turn dua yang bersih."}}
                            os.write(w_fd, (json.dumps(ev_res2) + "\n").encode("utf-8"))

                    threading.Thread(target=_emit_turn, daemon=True).start()
                    return len(data)

                def flush(self):
                    pass

                def close(self):
                    pass

            session.proc = types.SimpleNamespace(
                poll=lambda: None,
                stdin=_CancelableStdin(),
                stdout=out_r,
                terminate=lambda: terminated.append("terminate"),
                wait=lambda timeout=None: 0,
                kill=lambda: terminated.append("kill"),
            )

            class _Model:
                def transcribe(self, audio, **kwargs):
                    return [_FakeSegment("Pertanyaan satu")], None

            def _trigger_cancel():
                delta_seen.wait(timeout=1.0)
                cancel_ev.set()

            threading.Thread(target=_trigger_cancel, daemon=True).start()

            with tempfile.TemporaryDirectory() as tmp:
                tmp_dir = pathlib.Path(tmp)
                pcm_path = tmp_dir / "meeting.pcm"
                _write_pcm_speech(pcm_path)
                with patch.object(pipeline, "speak", side_effect=AssertionError("cancelled turn must not speak")):
                    cancelled_out = pipeline.run_turn(
                        _Model(),
                        session,
                        pcm_path,
                        tmp_dir / "reply1.wav",
                        stream_audio=True,
                        cancel_event=cancel_ev,
                    )

                self.assertTrue(cancelled_out["skipped"])
                self.assertTrue(cancelled_out["cancelled"])
                self.assertEqual(terminated, [])
                self.assertIsNotNone(session.proc)
                self.assertTrue(session._pending_turn)

                # Wait slightly less than 0.08s or immediately ask turn 2; _drain_pending_turn consumes turn 1's result first.
                with patch.object(pipeline, "speak", return_value={"engine_used": "edge"}):
                    next_out = pipeline.run_turn(
                        _Model(),
                        session,
                        pcm_path,
                        tmp_dir / "reply2.wav",
                        stream_audio=False,
                    )

            self.assertEqual(next_out["reply"], "Jawaban turn dua yang bersih.")
            self.assertEqual(terminated, [])
            self.assertFalse(session._pending_turn)
            self.assertEqual(len(prompts_written), 2)
        finally:
            out_r.close()
            try:
                os.close(w_fd)
            except OSError:
                pass

    def test_daemon_cancel_message_aborts_mid_turn_and_keeps_daemon_alive(self):
        in_r, in_w = os.pipe()
        stdin_reader = os.fdopen(in_r, "r", encoding="utf-8", buffering=1)
        stdin_writer = os.fdopen(in_w, "w", encoding="utf-8", buffering=1)

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = pathlib.Path(tmp)
            pcm1 = tmp_dir / "q1.pcm"
            pcm2 = tmp_dir / "q2.pcm"
            _write_pcm_speech(pcm1)
            _write_pcm_speech(pcm2)

            class _Model:
                def transcribe(self, audio, **kwargs):
                    return [_FakeSegment("Halo Nail")], None

            agy = Mock()
            agy.warmup = Mock()
            ask_calls = 0

            def _fake_ask_stream(text, notes_context="", timeout_s=45.0, on_delta=None, cancel_event=None):
                nonlocal ask_calls
                ask_calls += 1
                if ask_calls == 1:
                    deadline = time.monotonic() + 2.0
                    while time.monotonic() < deadline:
                        if cancel_event is not None and cancel_event.is_set():
                            raise pipeline.TurnCancelledError("cancelled")
                        time.sleep(0.01)
                    return "Should not finish"
                return "Turn dua sukses."

            agy.ask_stream = _fake_ask_stream

            args = argparse.Namespace(
                tts_voice="id-ID-GadisNeural",
                tts_rate=185,
                tts_engine="edge",
                elevenlabs_voice_id="",
                elevenlabs_model=pipeline.ELEVENLABS_DEFAULT_MODEL,
            )

            out_buf = io.StringIO()
            wake_seen = threading.Event()

            def _capture_emit(payload, request_id=None):
                if request_id is not None:
                    payload = {"id": request_id, **payload}
                out_buf.write(json.dumps(payload) + "\n")
                if payload.get("event") == "wake" and payload.get("id") == 1:
                    wake_seen.set()

            def _drive_daemon():
                stdin_writer.write(json.dumps({"id": 1, "from_wav": str(pcm1), "reply_wav": str(tmp_dir / "r1.wav"), "input_format": "pcm16k", "stream_audio": True}) + "\n")
                stdin_writer.flush()
                wake_seen.wait(timeout=2.0)
                time.sleep(0.02)
                stdin_writer.write(json.dumps({"id": 1, "action": "cancel"}) + "\n")
                stdin_writer.write(json.dumps({"id": 2, "from_wav": str(pcm2), "reply_wav": str(tmp_dir / "r2.wav"), "input_format": "pcm16k"}) + "\n")
                stdin_writer.flush()
                stdin_writer.close()

            driver = threading.Thread(target=_drive_daemon, daemon=True)
            driver.start()
            try:
                with patch.object(pipeline, "_emit_daemon_line", side_effect=_capture_emit), \
                     patch.object(pipeline, "speak", return_value={"engine_used": "edge"}), \
                     patch.object(pipeline.sys, "stdin", stdin_reader):
                    rc = pipeline._run_agy_daemon(_Model(), agy, args)
            finally:
                stdin_reader.close()

        self.assertEqual(rc, 0)
        lines = [json.loads(line) for line in out_buf.getvalue().strip().splitlines()]
        turn1_final = [m for m in lines if m.get("id") == 1 and "skipped" in m]
        turn2_final = [m for m in lines if m.get("id") == 2 and "reply" in m]
        self.assertEqual(len(turn1_final), 1)
        self.assertTrue(turn1_final[0]["cancelled"])
        self.assertEqual(len(turn2_final), 1)
        self.assertEqual(turn2_final[0]["reply"], "Turn dua sukses.")


class EdgeTtsPipedSynthesisTests(unittest.TestCase):
    def test_speak_edge_tts_pipes_mp3_to_ffmpeg_without_temp_file(self):
        import asyncio
        import edge_tts

        class _FakeCommunicate:
            def __init__(self, text, voice, rate):
                self.text = text
                self.voice = voice
                self.rate = rate

            async def stream(self):
                yield {"type": "audio", "data": b"ID3chunk1"}
                yield {"type": "WordBoundary", "data": b""}
                yield {"type": "audio", "data": b"chunk2"}

        written_stdin = bytearray()

        class _FakeStdin:
            def write(self, data):
                written_stdin.extend(data)

            def close(self):
                pass

        with tempfile.TemporaryDirectory() as tmp:
            out_wav = pathlib.Path(tmp) / "out.wav"

            def _fake_popen(cmd, stdin=None, stdout=None, stderr=None):
                out_wav.write_bytes(b"RIFF_WAV")
                return types.SimpleNamespace(
                    stdin=_FakeStdin(),
                    stderr=io.BytesIO(b""),
                    wait=lambda timeout=None: 0,
                    poll=lambda: 0,
                    kill=lambda: None,
                )

            with patch.object(edge_tts, "Communicate", _FakeCommunicate), \
                 patch.object(pipeline.subprocess, "Popen", side_effect=_fake_popen):
                pipeline.speak_edge_tts("Halo", out_wav, voice="id-ID-GadisNeural", rate=185)

            self.assertEqual(bytes(written_stdin), b"ID3chunk1chunk2")
            self.assertFalse(out_wav.with_suffix(".edge.mp3").exists())


if __name__ == "__main__":
    unittest.main()
