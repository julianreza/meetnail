const {createServer} = require('node:net');

const maxFrameBytes = 1024 * 1024;

function listenForAvatarFrames(path, onFrame) {
  let client;
  const server = createServer(socket => {
    socket.on('error', () => socket.destroy());
    if (client) {
      socket.destroy();
      return;
    }
    client = socket;
    let buffered = Buffer.alloc(0);
    const read = async () => {
      while (!socket.destroyed && buffered.length >= 8) {
        const size = buffered.readUInt32BE(4);
        if (!size || size > maxFrameBytes) {
          socket.destroy();
          return;
        }
        if (buffered.length < size + 8) break;
        const revision = buffered.readUInt32BE(0);
        const frame = buffered.subarray(8, size + 8);
        buffered = buffered.subarray(size + 8);
        let drawn = false;
        try { drawn = await onFrame(revision, frame); } catch {}
        if (!socket.destroyed) socket.write(Buffer.from([drawn ? 1 : 0]));
      }
      socket.resume();
    };
    socket.on('data', chunk => {
      if (buffered.length + chunk.length > maxFrameBytes + 8) {
        socket.destroy();
        return;
      }
      socket.pause();
      buffered = Buffer.concat([buffered, chunk]);
      void read();
    });
    socket.on('close', () => { if (client === socket) client = null; });
  });
  return new Promise((resolve, reject) => {
    server.on('error', reject);
    server.listen(path, () => resolve({
      close() {
        client?.destroy();
        server.close();
      },
    }));
  });
}

function createMeetAvatarController({prepare, setCamera, stop, emitState}) {
  let current = 0;
  let state = 'off';
  let pending = Promise.resolve();
  let firstFrameTimer;
  let activating = false;
  let closed = false;
  let cameraMaybeOn = false;
  const queue = task => {
    pending = pending.then(task, task);
    return pending;
  };
  const isCurrent = revision => !closed && revision === current;
  const publish = (revision, next) => {
    if (!isCurrent(revision)) return;
    state = next;
    emitState(revision, state);
  };
  const accepts = revision => isCurrent(revision) && (state === 'starting' || state === 'on');
  const turnCameraOff = async () => {
    const off = await Promise.resolve().then(() => setCamera(false)).catch(() => false);
    if (off) cameraMaybeOn = false;
    return off;
  };
  const settleOff = async (revision, failure) => {
    const off = await turnCameraOff();
    await Promise.resolve().then(() => stop(revision)).catch(() => {});
    publish(revision, failure || !off ? 'unavailable' : 'off');
  };
  const fail = revision => {
    if (!accepts(revision)) return Promise.resolve();
    clearTimeout(firstFrameTimer);
    state = 'stopping';
    return queue(() => isCurrent(revision) ? settleOff(revision, true) : undefined);
  };
  return {
    accepts,
    fail,
    request({revision, enabled}) {
      if (closed || !Number.isInteger(revision) || revision <= current || revision > 0xffffffff || typeof enabled !== 'boolean') return Promise.resolve();
      current = revision;
      clearTimeout(firstFrameTimer);
      activating = false;
      state = enabled ? 'off' : 'stopping';
      return queue(async () => {
        if (!isCurrent(revision)) return;
        if (!enabled) {
          publish(revision, 'stopping');
          await settleOff(revision, false);
          return;
        }
        if (cameraMaybeOn && !await turnCameraOff()) {
          await settleOff(revision, true);
          return;
        }
        if (!isCurrent(revision)) return;
        const prepared = await Promise.resolve().then(() => prepare(revision)).catch(() => false);
        if (!isCurrent(revision)) return;
        if (!prepared) {
          await settleOff(revision, true);
          return;
        }
        publish(revision, 'starting');
        firstFrameTimer = setTimeout(() => void fail(revision), 3000);
        firstFrameTimer.unref?.();
      });
    },
    frameReady(revision) {
      if (!isCurrent(revision) || state !== 'starting' || activating) return Promise.resolve();
      activating = true;
      clearTimeout(firstFrameTimer);
      return queue(async () => {
        if (!accepts(revision)) return;
        cameraMaybeOn = true;
        const on = await Promise.resolve().then(() => setCamera(true, revision)).catch(() => false);
        if (!accepts(revision)) return;
        if (on) publish(revision, 'on');
        else await settleOff(revision, true);
      });
    },
    close() {
      closed = true;
      clearTimeout(firstFrameTimer);
      return Promise.resolve().then(() => stop(current)).catch(() => {});
    },
  };
}

function avatarSpeechTransition(event) {
  const name = event.split(' ', 1)[0];
  if (name === 'voice-sending') return 'start';
  if (name === 'left' || /^voice-(result|standby|followup|interrupted|failed|no-audio|no-mic|recording|processing|unavailable|codex-(quota|login|missing|timeout|connection|no-transcript|error))$/.test(name)) return 'stop';
  return null;
}

module.exports = {listenForAvatarFrames, createMeetAvatarController, avatarSpeechTransition};
