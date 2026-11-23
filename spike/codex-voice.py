# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["aiortc==1.14.0"]
# ///
"""Synthetic Indonesian voice round trip; no microphone, meeting, or API key."""
import asyncio
import json
import os
import subprocess
import tempfile
from fractions import Fraction
from pathlib import Path

from aiortc import AudioStreamTrack, RTCPeerConnection, RTCSessionDescription
from av import AudioFrame

RATE = 48000
FRAME = 960
QUESTION = 'Jawab singkat dalam Bahasa Indonesia. Berapa dua tambah dua?'


class Clip(AudioStreamTrack):
    def __init__(self, pcm):
        super().__init__()
        self.pcm = pcm
        self.pts = 0

    async def recv(self):
        await asyncio.sleep(FRAME / RATE)
        offset = max(0, (self.pts - RATE) * 2)
        data = self.pcm[offset:offset + FRAME * 2] if self.pts >= RATE else b''
        frame = AudioFrame(format='s16', layout='mono', samples=FRAME)
        frame.planes[0].update(data.ljust(FRAME * 2, b'\0'))
        frame.sample_rate, frame.pts, frame.time_base = RATE, self.pts, Fraction(1, RATE)
        self.pts += FRAME
        return frame


async def probe(cwd, pcm):
    env = os.environ.copy()
    for key in ('OPENAI_API_KEY', 'CODEX_API_KEY'):
        env.pop(key, None)
    pc = RTCPeerConnection()
    pc.addTrack(Clip(pcm))
    frames = 0
    received = 0
    clip = pc.getSenders()[0].track
    tracks = []

    @pc.on('track')
    def on_track(track):
        async def consume():
            nonlocal frames, received
            while True:
                frame = await track.recv()
                received += 1
                # Count only audible frames, not padding or silence.
                if abs(frame.to_ndarray().astype('int32')).max() > 300:
                    frames += 1
        tracks.append(asyncio.create_task(consume()))

    @pc.on('connectionstatechange')
    def on_connection():
        print('WebRTC:', pc.connectionState, flush=True)

    @pc.on('iceconnectionstatechange')
    def on_ice():
        print('ICE:', pc.iceConnectionState, flush=True)

    proc = await asyncio.create_subprocess_exec(
        'codex', 'app-server', '-c', 'approval_policy="never"', '-c', 'sandbox_mode="read-only"',
        cwd=cwd, env=env, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    request = 0
    async def send(method, params, notification=False):
        nonlocal request
        request += 1
        message = dict(jsonrpc='2.0', method=method, params=params)
        if not notification:
            message['id'] = request
        proc.stdin.write((json.dumps(message) + '\n').encode())
        await proc.stdin.drain()
        return request

    async def read():
        line = await proc.stdout.readline()
        if not line:
            raise RuntimeError('Codex app-server stopped')
        return json.loads(line)

    async def call(method, params):
        id = await send(method, params)
        async with asyncio.timeout(15):
            while (msg := await read()).get('id') != id:
                pass
        if 'error' in msg:
            raise RuntimeError(f'{method}: {msg["error"].get("message")}')
        return msg['result']

    try:
        await call('initialize', {'clientInfo': {'name': 'nail_spike', 'version': '0.1.0'},
                                  'capabilities': {'experimentalApi': True}})
        await send('initialized', {}, notification=True)
        auth = await call('getAuthStatus', {'includeToken': False})
        if auth.get('authMethod') != 'chatgpt':
            raise RuntimeError('ChatGPT sign-in required; no API billing fallback')
        print('Auth: chatgpt', flush=True)
        thread = await call('thread/start', {'ephemeral': True, 'cwd': cwd,
                                              'sandbox': 'read-only', 'approvalPolicy': 'never'})
        tid = thread['thread']['id']
        await pc.setLocalDescription(await pc.createOffer())
        await send('thread/realtime/start', {
            'threadId': tid, 'version': 'v3', 'outputModality': 'audio', 'model': 'gpt-live-1-codex',
            'voice': 'cove', 'includeStartupContext': False, 'clientManagedHandoffs': True,
            'transport': {'type': 'webrtc', 'sdp': pc.localDescription.sdp},
        })
        print('Voice start requested', flush=True)
        heard = answered = False
        try:
            async with asyncio.timeout(35):
                while not (heard and answered and frames > 0):
                    try:
                        msg = await asyncio.wait_for(read(), timeout=1)
                    except TimeoutError:
                        continue
                    method, params = msg.get('method') or '', msg.get('params') or {}
                    if 'error' in msg or method == 'thread/realtime/error':
                        raise RuntimeError(msg.get('error', {}).get('message') or params.get('message'))
                    if method == 'thread/realtime/sdp':
                        await pc.setRemoteDescription(RTCSessionDescription(params['sdp'], 'answer'))
                        print('SDP answer received', flush=True)
                    elif method.startswith('thread/realtime/') and not method.endswith('transcript/delta'):
                        print('Event:', method, flush=True)
                    if method == 'thread/realtime/transcript/done':
                        role, text = params.get('role'), params.get('text', '').casefold()
                        print(f'{role}: {text}', flush=True)
                        heard |= role == 'user' and ('tambah' in text or '2+2' in text.replace(' ', ''))
                        answered |= role == 'assistant' and ('empat' in text or '4' in text)
        except TimeoutError as exc:
            stats = await pc.getStats()
            sent = sum(s.packetsSent for s in stats.values() if s.type == 'outbound-rtp')
            print(f'Voice timeout: ICE={pc.iceConnectionState}, sent_packets={sent}, '
                  f'clip_seconds={clip.pts/RATE:.1f}, received={received}, audible={frames}, '
                  f'heard={heard}, answered={answered}', flush=True)
            raise RuntimeError('Voice round trip incomplete') from exc
        print(f'PASS: Indonesian reply, {frames} audible WebRTC frames', flush=True)
        await send('thread/realtime/stop', {'threadId': tid})
    finally:
        for track in tracks:
            track.cancel()
        try:
            await asyncio.wait_for(pc.close(), 3)
        finally:
            if proc.returncode is None:
                proc.kill()
            await asyncio.wait_for(proc.wait(), 3)


with tempfile.TemporaryDirectory(prefix='nail-voice-') as directory:
    clip = Path(directory) / 'question.aiff'
    subprocess.run(['say', '-v', 'Damayanti', '-o', str(clip), QUESTION], check=True)
    samples = subprocess.check_output(['ffmpeg', '-nostdin', '-v', 'error', '-i', str(clip),
                                       '-ac', '1', '-ar', str(RATE), '-f', 's16le', '-'])
    asyncio.run(probe(directory, samples))
