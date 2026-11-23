import argparse
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
import urllib.error
from unittest.mock import Mock, patch

import numpy as np


path = pathlib.Path(__file__).resolve().parents[1] / "NAIL/Resources/agy-voice.py"
spec = importlib.util.spec_from_file_location("agy_voice", path)
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


class _FakeHTTPResponse:
    def __init__(self, payload: bytes) -> None:
        self._payload = payload

    def read(self) -> bytes:
        return self._payload

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


def _make_http_error(code: int, body: bytes = b"") -> urllib.error.HTTPError:
    return urllib.error.HTTPError(
        url="https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL",
        code=code,
        msg=f"HTTP {code}",
        hdrs=None,
        fp=io.BytesIO(body),
    )


class ElevenLabsSpeedMappingTests(unittest.TestCase):
    def test_rate_wpm_to_elevenlabs_speed_bounds_and_rounding(self):
        self.assertEqual(pipeline.rate_wpm_to_elevenlabs_speed(185), 1.0)
        self.assertEqual(pipeline.rate_wpm_to_elevenlabs_speed(100), 0.7)
        self.assertEqual(pipeline.rate_wpm_to_elevenlabs_speed(129), 0.7)
        self.assertEqual(pipeline.rate_wpm_to_elevenlabs_speed(300), 1.2)
        self.assertEqual(pipeline.rate_wpm_to_elevenlabs_speed(200), 1.08)


class ElevenLabsKeyResolutionTests(unittest.TestCase):
    def test_reads_env_var_before_keychain(self):
        with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "  sk_env_key  "}, clear=False), \
             patch.object(pipeline.subprocess, "run") as run_mock:
            self.assertEqual(pipeline.get_elevenlabs_api_key(), "sk_env_key")
            run_mock.assert_not_called()

    def test_falls_back_to_security_keychain_when_env_unset(self):
        env = dict(os.environ)
        env.pop("ELEVENLABS_API_KEY", None)
        proc = Mock(stdout="sk_keychain_key\n")
        with patch.dict(os.environ, env, clear=True), \
             patch.object(pipeline.subprocess, "run", return_value=proc) as run_mock:
            self.assertEqual(pipeline.get_elevenlabs_api_key(), "sk_keychain_key")
            run_mock.assert_called_once()
            self.assertEqual(
                run_mock.call_args.args[0],
                ["security", "find-generic-password", "-s", "nail.elevenlabs", "-w"],
            )


class ElevenLabsRequestAndConversionTests(unittest.TestCase):
    def test_request_url_headers_payload_ffmpeg_and_cleanup(self):
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["url"] = req.full_url
            captured["method"] = req.get_method()
            captured["headers"] = {k.lower(): v for k, v in req.header_items()}
            captured["body"] = json.loads(req.data.decode("utf-8"))
            captured["timeout"] = timeout
            return _FakeHTTPResponse(b"FAKE_MP3_BYTES")

        with tempfile.TemporaryDirectory() as tmp:
            out_wav = pathlib.Path(tmp) / "reply.wav"
            tmp_mp3 = out_wav.with_suffix(".eleven.mp3")

            def fake_ffmpeg(cmd, check=False):
                self.assertTrue(tmp_mp3.exists())
                self.assertEqual(tmp_mp3.read_bytes(), b"FAKE_MP3_BYTES")
                self.assertIn("-ar", cmd)
                self.assertIn("16000", cmd)
                self.assertIn("pcm_s16le", cmd)
                self.assertEqual(cmd[-1], str(out_wav))
                out_wav.write_bytes(b"FAKE_WAV")
                return Mock(returncode=0)

            with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "sk_test_secret"}, clear=False), \
                 patch.object(pipeline.urllib.request, "urlopen", side_effect=fake_urlopen), \
                 patch.object(pipeline.subprocess, "run", side_effect=fake_ffmpeg):
                meta = pipeline.speak(
                    "**Halo** teman-teman!",
                    out_wav,
                    voice="id-ID-GadisNeural",
                    rate=200,
                    tts_engine="elevenlabs",
                    elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
                    elevenlabs_model="eleven_multilingual_v2",
                )

            self.assertEqual(meta, {"engine_used": "elevenlabs"})
            self.assertFalse(tmp_mp3.exists())
            self.assertTrue(out_wav.exists())

        self.assertEqual(
            captured["url"],
            "https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL?output_format=mp3_44100_128",
        )
        self.assertEqual(captured["method"], "POST")
        self.assertEqual(captured["headers"]["xi-api-key"], "sk_test_secret")
        self.assertEqual(captured["headers"]["content-type"], "application/json")
        self.assertEqual(captured["headers"]["accept"], "audio/mpeg")
        self.assertEqual(
            captured["body"],
            {
                "text": "Halo teman-teman!",
                "model_id": "eleven_multilingual_v2",
                "language_code": "id",
                "voice_settings": {
                    "stability": 0.5,
                    "similarity_boost": 0.75,
                    "speed": 1.08,
                },
            },
        )

    def test_temp_mp3_cleaned_up_on_ffmpeg_failure_and_falls_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_wav = pathlib.Path(tmp) / "reply.wav"
            tmp_mp3 = out_wav.with_suffix(".eleven.mp3")
            with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "sk_test_secret"}, clear=False), \
                 patch.object(pipeline.urllib.request, "urlopen", return_value=_FakeHTTPResponse(b"MP3")), \
                 patch.object(pipeline.subprocess, "run", side_effect=subprocess.CalledProcessError(1, ["ffmpeg"])), \
                 patch.object(pipeline, "speak_edge_tts") as edge_mock, \
                 patch("sys.stderr", new_callable=io.StringIO) as stderr:
                meta = pipeline.speak(
                    "Tes ffmpeg gagal",
                    out_wav,
                    voice="Damayanti",
                    tts_engine="elevenlabs",
                    elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
                )

            self.assertFalse(tmp_mp3.exists())
            self.assertEqual(meta["engine_used"], "edge")
            self.assertIn("fallback_reason", meta)
            self.assertNotIn("sk_test_secret", stderr.getvalue())
            self.assertNotIn("sk_test_secret", meta["fallback_reason"])
            edge_mock.assert_called_once()
            self.assertEqual(edge_mock.call_args.kwargs["voice"], "id-ID-GadisNeural")


class ElevenLabsFallbackTests(unittest.TestCase):
    def test_backwards_compatible_speak_without_new_kwargs(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_wav = pathlib.Path(tmp) / "reply.wav"
            with patch.object(pipeline, "speak_edge_tts") as edge_mock:
                meta = pipeline.speak("Halo", out_wav)
        self.assertEqual(meta, {"engine_used": "edge"})
        edge_mock.assert_called_once_with("Halo", out_wav, voice="id-ID-GadisNeural", rate=185)

    def test_fallback_to_edge_on_http_401_402_429_and_key_never_logged(self):
        for code in (401, 402, 429):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as tmp:
                out_wav = pathlib.Path(tmp) / "reply.wav"
                secret = "sk_super_secret_token_999"
                err = _make_http_error(code, f'{{"detail":"bad key {secret}"}}'.encode("utf-8"))
                with patch.dict(os.environ, {"ELEVENLABS_API_KEY": secret}, clear=False), \
                     patch.object(pipeline.urllib.request, "urlopen", side_effect=err), \
                     patch.object(pipeline, "speak_edge_tts") as edge_mock, \
                     patch("sys.stderr", new_callable=io.StringIO) as stderr:
                    meta = pipeline.speak(
                        "Halo",
                        out_wav,
                        voice="id-ID-ArdiNeural",
                        rate=190,
                        tts_engine="elevenlabs",
                        elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
                    )

                self.assertEqual(meta["engine_used"], "edge")
                self.assertIn(f"HTTP {code}", meta["fallback_reason"])
                self.assertNotIn(secret, stderr.getvalue())
                self.assertNotIn(secret, meta["fallback_reason"])
                edge_mock.assert_called_once_with("Halo", out_wav, voice="id-ID-ArdiNeural", rate=190)

    def test_fallback_to_edge_on_network_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_wav = pathlib.Path(tmp) / "reply.wav"
            with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "sk_secret"}, clear=False), \
                 patch.object(pipeline.urllib.request, "urlopen", side_effect=urllib.error.URLError("offline")), \
                 patch.object(pipeline, "speak_edge_tts") as edge_mock, \
                 patch("sys.stderr", new_callable=io.StringIO):
                meta = pipeline.speak(
                    "Halo",
                    out_wav,
                    voice="Damayanti",
                    tts_engine="elevenlabs",
                    elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
                )
        self.assertEqual(meta["engine_used"], "edge")
        self.assertIn("network error", meta["fallback_reason"].lower())
        edge_mock.assert_called_once_with("Halo", out_wav, voice="id-ID-GadisNeural", rate=185)

    def test_fallback_to_edge_on_missing_api_key_or_missing_voice_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_wav = pathlib.Path(tmp) / "reply.wav"
            with patch.object(pipeline, "get_elevenlabs_api_key", return_value=""), \
                 patch.object(pipeline.urllib.request, "urlopen") as urlopen_mock, \
                 patch.object(pipeline, "speak_edge_tts") as edge_mock, \
                 patch("sys.stderr", new_callable=io.StringIO):
                meta_key = pipeline.speak(
                    "Halo",
                    out_wav,
                    tts_engine="elevenlabs",
                    elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
                )
            self.assertEqual(meta_key["engine_used"], "edge")
            self.assertIn("missing ElevenLabs API key", meta_key["fallback_reason"])
            urlopen_mock.assert_not_called()
            edge_mock.assert_called_once()

            with patch.object(pipeline, "speak_edge_tts") as edge_mock_voice, \
                 patch.object(pipeline.urllib.request, "urlopen") as urlopen_mock, \
                 patch("sys.stderr", new_callable=io.StringIO):
                meta_voice = pipeline.speak(
                    "Halo",
                    out_wav,
                    tts_engine="elevenlabs",
                    elevenlabs_voice_id="",
                )
            self.assertEqual(meta_voice["engine_used"], "edge")
            self.assertIn("missing ElevenLabs voice ID", meta_voice["fallback_reason"])
            urlopen_mock.assert_not_called()
            edge_mock_voice.assert_called_once()

    def test_double_fallback_to_macos_say_damayanti(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_wav = pathlib.Path(tmp) / "reply.wav"
            with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "sk_secret"}, clear=False), \
                 patch.object(pipeline.urllib.request, "urlopen", side_effect=_make_http_error(402)), \
                 patch.object(pipeline, "speak_edge_tts", side_effect=RuntimeError("edge offline")), \
                 patch.object(pipeline, "speak_macos_say") as say_mock, \
                 patch("sys.stderr", new_callable=io.StringIO):
                meta = pipeline.speak(
                    "Halo",
                    out_wav,
                    voice="id-ID-GadisNeural",
                    rate=175,
                    tts_engine="elevenlabs",
                    elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
                )

        self.assertEqual(meta["engine_used"], "macos_say")
        self.assertIn("402", meta["fallback_reason"])
        self.assertIn("edge offline", meta["fallback_reason"])
        say_mock.assert_called_once_with("Halo", out_wav, voice="Damayanti", rate=175)


class StickyDaemonQuotaFallbackTests(unittest.TestCase):
    def test_daemon_sets_sticky_fallback_on_quota_exceeded_body_and_skips_elevenlabs_next_turn(self):
        with tempfile.TemporaryDirectory() as tmp:
            wav1 = pathlib.Path(tmp) / "reply1.wav"
            wav2 = pathlib.Path(tmp) / "reply2.wav"
            in1 = pathlib.Path(tmp) / "in1.wav"
            in2 = pathlib.Path(tmp) / "in2.wav"
            in1.write_bytes(b"RIFF")
            in2.write_bytes(b"RIFF")

            daemon_stdin = "\n".join([
                json.dumps({"action": "speak", "text": "Halo satu", "reply_wav": str(wav1)}),
                json.dumps({"from_wav": str(in2), "reply_wav": str(wav2)}),
            ]) + "\n"

            args = argparse.Namespace(
                tts_voice="id-ID-GadisNeural",
                tts_rate=185,
                tts_engine="elevenlabs",
                elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
                elevenlabs_model="eleven_flash_v2_5",
            )
            agy = Mock()
            agy.ask.return_value = "Jawaban dua"
            err_400_quota = _make_http_error(400, b'{"detail":{"status":"quota_exceeded","message":"Credit limit reached"}}')

            with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "sk_secret"}, clear=False), \
                 patch.object(pipeline, "decode_pcm16k", return_value=np.ones(100)), \
                 patch.object(pipeline, "transcribe", return_value="Halo Nail"), \
                 patch.object(pipeline.urllib.request, "urlopen", side_effect=err_400_quota) as urlopen_mock, \
                 patch.object(pipeline, "speak_edge_tts") as edge_mock, \
                 patch("sys.stdin", io.StringIO(daemon_stdin)), \
                 patch("sys.stdout", new_callable=io.StringIO) as stdout, \
                 patch("sys.stderr", new_callable=io.StringIO):
                rc = pipeline._run_agy_daemon(Mock(), agy, args)

        self.assertEqual(rc, 0)
        lines = [json.loads(line) for line in stdout.getvalue().strip().splitlines()]
        self.assertEqual(len(lines), 4)  # ready, speak out, wake event, turn out
        self.assertTrue(lines[0]["ready"])
        self.assertEqual(lines[1]["spoken"], True)
        self.assertEqual(lines[1]["tts_engine_used"], "edge")
        self.assertIn("quota_exceeded", lines[1]["tts_fallback_reason"])
        self.assertEqual(lines[2]["event"], "wake")
        self.assertEqual(lines[3]["tts_engine_used"], "edge")
        self.assertIn("quota_exceeded", lines[3]["tts_fallback_reason"])
        # ElevenLabs was called only once on turn 1; turn 2 went directly to Edge TTS.
        urlopen_mock.assert_called_once()
        self.assertEqual(edge_mock.call_count, 2)

    def test_transient_500_does_not_trigger_sticky_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            wav1 = pathlib.Path(tmp) / "reply1.wav"
            wav2 = pathlib.Path(tmp) / "reply2.wav"
            daemon_stdin = "\n".join([
                json.dumps({"action": "speak", "text": "Satu", "reply_wav": str(wav1)}),
                json.dumps({"action": "speak", "text": "Dua", "reply_wav": str(wav2)}),
            ]) + "\n"
            args = argparse.Namespace(
                tts_voice="id-ID-GadisNeural",
                tts_rate=185,
                tts_engine="elevenlabs",
                elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
                elevenlabs_model="eleven_flash_v2_5",
            )

            def fake_ffmpeg(cmd, check=False):
                pathlib.Path(cmd[-1]).write_bytes(b"WAV")
                return Mock(returncode=0)

            with patch.dict(os.environ, {"ELEVENLABS_API_KEY": "sk_secret"}, clear=False), \
                 patch.object(pipeline.urllib.request, "urlopen", side_effect=[_make_http_error(500, b"server error"), _FakeHTTPResponse(b"MP3")]) as urlopen_mock, \
                 patch.object(pipeline, "speak_edge_tts") as edge_mock, \
                 patch.object(pipeline.subprocess, "run", side_effect=fake_ffmpeg), \
                 patch("sys.stdin", io.StringIO(daemon_stdin)), \
                 patch("sys.stdout", new_callable=io.StringIO) as stdout, \
                 patch("sys.stderr", new_callable=io.StringIO):
                rc = pipeline._run_agy_daemon(Mock(), Mock(), args)

        self.assertEqual(rc, 0)
        lines = [json.loads(line) for line in stdout.getvalue().strip().splitlines()]
        self.assertEqual(lines[1]["tts_engine_used"], "edge")
        self.assertEqual(lines[2]["tts_engine_used"], "elevenlabs")
        self.assertNotIn("tts_fallback_reason", lines[2])
        self.assertEqual(urlopen_mock.call_count, 2)
        edge_mock.assert_called_once()


class RunTurnAndSpeakTextOutputTests(unittest.TestCase):
    def test_run_turn_includes_tts_engine_used_and_fallback_reason(self):
        agy = Mock()
        agy.ask.return_value = "Siap, aman."
        with tempfile.TemporaryDirectory() as tmp:
            from_wav = pathlib.Path(tmp) / "in.wav"
            reply_wav = pathlib.Path(tmp) / "out.wav"
            with patch.object(pipeline, "decode_pcm16k", return_value=np.ones(100)), \
                 patch.object(pipeline, "transcribe", return_value="Halo Nail"), \
                 patch.object(pipeline, "speak", return_value={"engine_used": "edge", "fallback_reason": "HTTP 429"}):
                result = pipeline.run_turn(
                    Mock(),
                    agy,
                    from_wav,
                    reply_wav,
                    tts_engine="elevenlabs",
                    elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
                )
        self.assertEqual(result["tts_engine_used"], "edge")
        self.assertEqual(result["tts_fallback_reason"], "HTTP 429")

    def test_speak_text_cli_outputs_tts_metadata_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            reply_wav = pathlib.Path(tmp) / "preview.wav"
            argv = [
                "agy-voice.py",
                "--speak-text",
                "Tes suara Nail",
                "--reply-wav",
                str(reply_wav),
                "--tts-engine",
                "elevenlabs",
                "--elevenlabs-voice-id",
                "EXAVITQu4vr4xnSDxMaL",
                "--elevenlabs-model",
                "eleven_flash_v2_5",
            ]
            with patch("sys.argv", argv), \
                 patch.object(pipeline, "speak", return_value={"engine_used": "elevenlabs"}) as speak_mock, \
                 patch("sys.stdout", new_callable=io.StringIO) as stdout:
                rc = pipeline.main()

        self.assertEqual(rc, 0)
        speak_mock.assert_called_once_with(
            "Tes suara Nail",
            reply_wav.resolve(),
            voice="id-ID-GadisNeural",
            rate=185,
            tts_engine="elevenlabs",
            elevenlabs_voice_id="EXAVITQu4vr4xnSDxMaL",
            elevenlabs_model="eleven_flash_v2_5",
        )
        payload = json.loads(stdout.getvalue().strip())
        self.assertEqual(payload, {"spoken": True, "tts_engine_used": "elevenlabs"})


if __name__ == "__main__":
    unittest.main()
