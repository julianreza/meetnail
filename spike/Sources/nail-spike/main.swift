import Foundation
import CoreAudio
import AVFoundation

// Fase 0 spike: prove what the audio layer can see and capture.
//   nail-spike devices             list output/input devices and defaults
//   nail-spike tap [seconds]       create a global process tap, print RMS level

func addr(
    _ sel: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
}

func devices() -> [AudioObjectID] {
    var a = addr(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    let sys = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func stringProperty(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
    var a = addr(sel)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let err = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0)
    }
    guard err == noErr, let value else { return nil }
    return value as String
}

func channelCount(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
    var a = addr(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func defaultDevice(_ sel: AudioObjectPropertySelector) -> AudioObjectID? {
    var a = addr(sel)
    var id = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let sys = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &id) == noErr else { return nil }
    return id
}

func listDevices() {
    let sys = AudioObjectID(kAudioObjectSystemObject)
    var t = addr(kAudioHardwarePropertyDefaultOutputDevice)
    var defaultOut = AudioObjectID(0)
    var s = UInt32(MemoryLayout<AudioObjectID>.size)
    _ = AudioObjectGetPropertyData(sys, &t, 0, nil, &s, &defaultOut)
    t = addr(kAudioHardwarePropertyDefaultInputDevice)
    var defaultIn = AudioObjectID(0)
    s = UInt32(MemoryLayout<AudioObjectID>.size)
    _ = AudioObjectGetPropertyData(sys, &t, 0, nil, &s, &defaultIn)

    for id in devices() {
        let name = stringProperty(id, kAudioObjectPropertyName) ?? "?"
        let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "?"
        let out = channelCount(id, kAudioObjectPropertyScopeOutput)
        let inp = channelCount(id, kAudioObjectPropertyScopeInput)
        let marks = [
            id == defaultOut ? "default-out" : nil,
            id == defaultIn ? "default-in" : nil,
        ].compactMap { $0 }.joined(separator: ",")
        print("id=\(id) out=\(out) in=\(inp) \(marks.isEmpty ? "" : "[\(marks)] ")\(name)")
        print("    uid: \(uid)")
    }
}

@available(macOS 14.2, *)
final class Level {
    private let lock = NSLock()
    private var rms: Double = 0
    func set(_ v: Double) { lock.lock(); rms = v; lock.unlock() }
    func get() -> Double { lock.lock(); defer { lock.unlock() }; return rms }
}

final class CallbackStats {
    var count = 0
    var buffers = -1
    var channels = -1
    var bytes = -1
}

func processObjectID(pid: Int) -> AudioObjectID? {
    var a = addr(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var pidValue = pid_t(pid)
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let err = withUnsafeMutablePointer(to: &pidValue) { p in
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &a,
            UInt32(MemoryLayout<pid_t>.size), p, &size, &id
        )
    }
    guard err == noErr, id != kAudioObjectUnknown else { return nil }
    return id
}

@available(macOS 14.2, *)
func runTap(seconds: Double, pids: [Int]) -> Int32 {
    var objects: [AudioObjectID] = []
    for pid in pids {
        guard let obj = processObjectID(pid: pid) else {
            print("tap: no audio process object for pid \(pid)")
            return 1
        }
        objects.append(obj)
    }
    print("tap: pids \(pids) -> objects \(objects)")

    let desc = objects.isEmpty
        ? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        : CATapDescription(stereoMixdownOfProcesses: objects)
    desc.isPrivate = true
    desc.name = "NAIL Fase 0 tap"

    var tapID = AudioObjectID(kAudioObjectUnknown)
    var err = AudioHardwareCreateProcessTap(desc, &tapID)
    guard err == noErr else {
        print("tap: AudioHardwareCreateProcessTap failed: \(err)")
        return 1
    }
    defer { AudioHardwareDestroyProcessTap(tapID) }

    var uidAddr = addr(kAudioTapPropertyUID)
    var uidSize = UInt32(MemoryLayout<CFString?>.size)
    var tapUID: CFString?
    err = withUnsafeMutablePointer(to: &tapUID) {
        AudioObjectGetPropertyData(tapID, &uidAddr, 0, nil, &uidSize, $0)
    }
    guard err == noErr, let tapUID else {
        print("tap: could not read tap UID: \(err)")
        return 1
    }
    print("tap created: id=\(tapID) uid=\(tapUID)")

    let aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey: "NAIL Fase 0 aggregate",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey: 1,
        kAudioAggregateDeviceTapAutoStartKey: 1,
        kAudioAggregateDeviceIsStackedKey: 0,
    ]
    var aggID = AudioObjectID(kAudioObjectUnknown)
    err = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggID)
    guard err == noErr else {
        print("tap: AudioHardwareCreateAggregateDevice failed: \(err)")
        return 1
    }
    defer { AudioHardwareDestroyAggregateDevice(aggID) }

    var tapListAddr = addr(kAudioAggregateDevicePropertyTapList)
    err = withUnsafePointer(to: tapUID) { uidPtr in
        var list: CFArray = [uidPtr.pointee] as CFArray
        return withUnsafeMutablePointer(to: &list) { listPtr in
            AudioObjectSetPropertyData(
                aggID, &tapListAddr, 0, nil,
                UInt32(MemoryLayout<CFArray>.size), listPtr
            )
        }
    }
    guard err == noErr else {
        print("tap: setting tap list failed: \(err)")
        return 1
    }

    let level = Level()
    var procID: AudioDeviceIOProcID?
    let stats = CallbackStats()
    err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, inInput, _, _, _ in
        stats.count += 1
        var sum = 0.0
        var count = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput)) {
            if stats.buffers < 0 {
                stats.buffers = Int(inInput.pointee.mNumberBuffers)
                stats.channels = Int(buffer.mNumberChannels)
                stats.bytes = Int(buffer.mDataByteSize)
            }
            guard let data = buffer.mData else { continue }
            let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard samples > 0 else { continue }
            let ptr = data.assumingMemoryBound(to: Float.self)
            for i in 0..<samples {
                let v = Double(ptr[i])
                sum += v * v
                count += 1
            }
        }
        if count > 0 { level.set((sum / Double(count)).squareRoot()) }
    }
    guard err == noErr, let procID else {
        print("tap: AudioDeviceCreateIOProcIDWithBlock failed: \(err)")
        return 1
    }
    defer { AudioDeviceDestroyIOProcID(aggID, procID) }

    err = AudioDeviceStart(aggID, procID)
    guard err == noErr else {
        print("tap: AudioDeviceStart failed: \(err)")
        return 1
    }

    let started = Date()
    print("capturing \(Int(seconds))s (pids: \(pids.isEmpty ? "global" : pids.map(String.init).joined(separator: ","))) — play audio now")
    let deadline = started.addingTimeInterval(seconds)
    var peak = 0.0
    while Date() < deadline {
        Thread.sleep(forTimeInterval: 0.25)
        let v = level.get()
        peak = max(peak, v)
        print(String(format: "  t=%4.1fs rms %.5f %@", Date().timeIntervalSince(started), v, String(repeating: "#", count: Int(min(v * 200, 40)))))
    }
    AudioDeviceStop(aggID, procID)
    print("callbacks: \(stats.count), buffers: \(stats.buffers), channels: \(stats.channels), bytes: \(stats.bytes)")
    print(String(format: "peak rms: %.5f %@", peak, peak > 0.001 ? "(audio captured)" : "(silence — check routing or permission)"))
    return peak > 0.001 ? 0 : 2
}

final class Meter {
    private let lock = NSLock()
    private var rms: Double = 0
    func update(_ v: Double) { lock.lock(); rms = v; lock.unlock() }
    var value: Double { lock.lock(); defer { lock.unlock() }; return rms }
}

func startMic(_ meter: Meter, voiceProcessing: Bool = false) throws -> AVAudioEngine {
    let engine = AVAudioEngine()
    let input = engine.inputNode
    if voiceProcessing {
        try input.setVoiceProcessingEnabled(true)
    }
    let format = input.inputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum = 0.0
        for i in 0..<frames {
            let v = Double(channel[i])
            sum += v * v
        }
        meter.update((sum / Double(frames)).squareRoot())
    }
    engine.prepare()
    try engine.start()
    return engine
}

func deviceID(named name: String) -> AudioObjectID? {
    devices().first { stringProperty($0, kAudioObjectPropertyName) == name }
}

func setDefaultOutput(_ id: AudioObjectID) -> Bool {
    var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
    var value = id
    return AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
        UInt32(MemoryLayout<AudioObjectID>.size), &value
    ) == noErr
}

func meterLoop(_ meter: Meter, seconds: Double, label: String) {
    let start = Date()
    let end = start.addingTimeInterval(seconds)
    while Date() < end {
        Thread.sleep(forTimeInterval: 0.25)
        let v = meter.value
        print(String(format: "  %@ t=%4.1fs rms %.5f %@", label, Date().timeIntervalSince(start), v,
                     String(repeating: "#", count: Int(min(v * 400, 40)))))
    }
}

@available(macOS 14.2, *)
func runLeak(seconds: Double, file: String, aec: Bool) -> Int32 {
    guard let speakers = deviceID(named: "MacBook Pro Speakers") else {
        print("leak: built-in speakers not found")
        return 1
    }
    let original = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
    guard setDefaultOutput(speakers) else {
        print("leak: could not switch default output to speakers")
        return 1
    }
    defer { if let original { _ = setDefaultOutput(original) } }

    let meter = Meter()
    let engine: AVAudioEngine
    do { engine = try startMic(meter, voiceProcessing: aec) } catch {
        print("leak: mic unavailable: \(error)")
        return 1
    }
    defer { engine.stop() }
    print("voice processing (AEC): \(aec ? "on" : "off")")

    Thread.sleep(forTimeInterval: 0.5)
    print("baseline (silence):")
    meterLoop(meter, seconds: 1.0, label: "quiet")

    print("playback: \(file) through built-in speakers at system volume")
    let player = Process()
    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    player.arguments = [file]
    try? player.run()

    var peak = 0.0
    let start = Date()
    while player.isRunning && Date().timeIntervalSince(start) < 15 {
        Thread.sleep(forTimeInterval: 0.25)
        let v = meter.value
        peak = max(peak, v)
        print(String(format: "  leak  t=%4.1fs rms %.5f %@", Date().timeIntervalSince(start), v,
                     String(repeating: "#", count: Int(min(v * 400, 40)))))
    }
    print(String(format: "peak mic rms during playback: %.5f", peak))
    print("interpretation: compare with baseline; near-baseline = no leak, clearly above = channel contaminated")
    engine.stop()
    return 0
}

func uint32Property(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32? {
    var a = addr(sel)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

func listProcesses() {
    var a = addr(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    let sys = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr else {
        print("processes: unavailable")
        return
    }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return }
    for id in ids {
        let pid = uint32Property(id, kAudioProcessPropertyPID) ?? 0
        let out = uint32Property(id, kAudioProcessPropertyIsRunningOutput) ?? 0
        let run = uint32Property(id, kAudioProcessPropertyIsRunning) ?? 0
        let bundle = stringProperty(id, kAudioProcessPropertyBundleID) ?? "?"
        print("obj=\(id) pid=\(pid) running=\(run) output=\(out) \(bundle)")
    }
}

func writeWAV(samples: [Int16], sampleRate: Int) -> Data {
    var data = Data()
    func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    data.append("RIFF".data(using: .ascii)!)
    append(UInt32(36) + bytes)
    data.append("WAVEfmt ".data(using: .ascii)!)
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(sampleRate))
    append(UInt32(sampleRate * 2))
    append(UInt16(2))
    append(UInt16(16))
    data.append("data".data(using: .ascii)!)
    append(bytes)
    samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
    return data
}

@available(macOS 14.2, *)
func runRecord(seconds: Double, pids: [Int], output: String) -> Int32 {
    var objects: [AudioObjectID] = []
    for pid in pids {
        guard let obj = processObjectID(pid: pid) else {
            print("record: no audio process object for pid \(pid)")
            return 1
        }
        objects.append(obj)
    }
    let desc = objects.isEmpty
        ? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        : CATapDescription(stereoMixdownOfProcesses: objects)
    desc.isPrivate = true
    desc.name = "NAIL record"

    var tapID = AudioObjectID(kAudioObjectUnknown)
    guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else {
        print("record: tap creation failed")
        return 1
    }
    defer { AudioHardwareDestroyProcessTap(tapID) }

    var uidAddr = addr(kAudioTapPropertyUID)
    var uidSize = UInt32(MemoryLayout<CFString?>.size)
    var tapUID: CFString?
    guard withUnsafeMutablePointer(to: &tapUID, { AudioObjectGetPropertyData(tapID, &uidAddr, 0, nil, &uidSize, $0) }) == noErr,
          let tapUID else {
        print("record: tap UID unavailable")
        return 1
    }
    let aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey: "NAIL record aggregate",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey: 1,
        kAudioAggregateDeviceTapAutoStartKey: 1,
        kAudioAggregateDeviceIsStackedKey: 0,
    ]
    var aggID = AudioObjectID(kAudioObjectUnknown)
    guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggID) == noErr else {
        print("record: aggregate creation failed")
        return 1
    }
    defer { AudioHardwareDestroyAggregateDevice(aggID) }

    var tapListAddr = addr(kAudioAggregateDevicePropertyTapList)
    var list: CFArray = [tapUID] as CFArray
    guard withUnsafeMutablePointer(to: &list, { AudioObjectSetPropertyData(aggID, &tapListAddr, 0, nil, UInt32(MemoryLayout<CFArray>.size), $0) }) == noErr else {
        print("record: tap list failed")
        return 1
    }

    final class Sink {
        var samples: [Int16] = []
        var peak: Double = 0
        let lock = NSLock()
    }
    let sink = Sink()
    var procID: AudioDeviceIOProcID?
    let err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, input, _, _, _ in
        var sums: [Double] = []
        var mono: [Int16] = []
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let ptr = data.assumingMemoryBound(to: Float.self)
            for i in stride(from: 0, to: count, by: 2) {
                let v = (Double(ptr[i]) + (i + 1 < count ? Double(ptr[i + 1]) : 0)) / 2
                sums.append(abs(v))
                mono.append(Int16(max(-1, min(1, v)) * 32767))
            }
        }
        guard !mono.isEmpty else { return }
        sink.lock.lock()
        sink.samples.append(contentsOf: mono)
        sink.peak = max(sink.peak, sums.max() ?? 0)
        sink.lock.unlock()
    }
    guard err == noErr, let procID else {
        print("record: IOProc failed (\(err))")
        return 1
    }
    defer { AudioDeviceDestroyIOProcID(aggID, procID) }
    guard AudioDeviceStart(aggID, procID) == noErr else {
        print("record: start failed")
        return 1
    }
    print("recording \(Int(seconds))s to \(output) — play audio now")
    Thread.sleep(forTimeInterval: seconds)
    AudioDeviceStop(aggID, procID)

    sink.lock.lock()
    let captured = sink.samples
    sink.lock.unlock()
    let sampleRate = 48000
    try? writeWAV(samples: captured, sampleRate: sampleRate).write(to: URL(fileURLWithPath: output))
    print("wrote \(captured.count) samples (\(String(format: "%.1f", Double(captured.count) / Double(sampleRate)))s)")
    return captured.isEmpty ? 2 : 0
}

func runRecordMic(seconds: Double, output: String, untilSilence: Bool = false) -> Int32 {
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.inputFormat(forBus: 0)
    final class MicSink {
        var samples: [Int16] = []
        var peak: Double = 0
        var lastVoice: Date = .distantPast
        var heardVoice = false
        var threshold = 0.02
        var noiseSum = 0.0
        var noiseCount = 0
        var voicedSeconds = 0.0
        var started = Date()
        let lock = NSLock()
    }
    let sink = MicSink()
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var converted = [Int16](repeating: 0, count: frames)
        var energy = 0.0
        for i in 0..<frames {
            let value = Double(channel[i])
            energy += value * value
            converted[i] = Int16(max(-1, min(1, value)) * 32767)
        }
        let rms = (energy / Double(frames)).squareRoot()
        let duration = Double(frames) / format.sampleRate
        sink.lock.lock()
        sink.samples.append(contentsOf: converted)
        sink.peak = max(sink.peak, rms)
        let elapsed = Date().timeIntervalSince(sink.started)
        if elapsed < 0.4 {
            sink.noiseSum += rms
            sink.noiseCount += 1
            sink.threshold = max(0.02, (sink.noiseCount > 0 ? sink.noiseSum / Double(sink.noiseCount) : 0) * 4)
        } else if rms > sink.threshold {
            sink.heardVoice = true
            sink.voicedSeconds += duration
            sink.lastVoice = Date()
        }
        sink.lock.unlock()
    }
    engine.prepare()
    do { try engine.start() } catch {
        print("record --mic: engine failed: \(error)")
        return 1
    }
    print("recording mic \(Int(seconds))s to \(output) — speak now")
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
        guard untilSilence else { continue }
        sink.lock.lock()
        let voicedSeconds = sink.voicedSeconds
        let quietFor = Date().timeIntervalSince(sink.lastVoice)
        sink.lock.unlock()
        if voicedSeconds > 0.4 && quietFor > 0.9 { break }
    }
    engine.stop()
    sink.lock.lock()
    let captured = sink.samples
    sink.lock.unlock()
    try? writeWAV(samples: captured, sampleRate: Int(format.sampleRate)).write(to: URL(fileURLWithPath: output))
    print("wrote \(captured.count) samples at \(Int(format.sampleRate)) Hz")
    return captured.isEmpty ? 2 : 0
}

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "devices"

switch command {
case "devices":
    listDevices()
case "tap":
    if #available(macOS 14.2, *) {
        var seconds = 5.0
        var pids: [Int] = []
        var i = 2
        while i < args.count {
            if args[i] == "--pid", i + 1 < args.count {
                pids = args[i + 1].split(separator: ",").compactMap {
                    Int($0.trimmingCharacters(in: .whitespaces))
                }
                i += 2
            } else {
                seconds = Double(args[i]) ?? seconds
                i += 1
            }
        }
        exit(runTap(seconds: seconds, pids: pids))
    } else {
        print("tap: requires macOS 14.2 or later")
        exit(1)
    }
case "record":
    if #available(macOS 14.2, *) {
        var seconds = 10.0
        var pids: [Int] = []
        var output = "/tmp/nail-record.wav"
        var useMic = false
        var untilSilence = false
        var i = 2
        while i < args.count {
            if args[i] == "--mic" {
                useMic = true
                i += 1
            } else if args[i] == "--until-silence" {
                untilSilence = true
                i += 1
            } else if args[i] == "--pid", i + 1 < args.count {
                pids = args[i + 1].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                i += 2
            } else if args[i] == "--out", i + 1 < args.count {
                output = args[i + 1]
                i += 2
            } else {
                seconds = Double(args[i]) ?? seconds
                i += 1
            }
        }
        if useMic {
            exit(runRecordMic(seconds: seconds, output: output, untilSilence: untilSilence))
        }
        exit(runRecord(seconds: seconds, pids: pids, output: output))
    } else {
        print("record: requires macOS 14.2")
        exit(1)
    }
case "setout":
    guard args.count > 2, let target = deviceID(named: args[2..<args.count].joined(separator: " ")) else {
        print("usage: nail-spike setout <device name>   (see `devices`)")
        exit(64)
    }
    if setDefaultOutput(target) {
        print("default output: \(args[2...].joined(separator: " "))")
    } else {
        print("setout: failed")
        exit(1)
    }
case "processes":
    listProcesses()
case "mic":
    let meters = Meter()
    do {
        let engine = try startMic(meters)
        print("mic capture \(Int(args.count > 2 ? Double(args[2]) ?? 5 : 5))s — speak now")
        meterLoop(meters, seconds: args.count > 2 ? Double(args[2]) ?? 5 : 5, label: "mic")
        engine.stop()
    } catch {
        print("mic: unavailable: \(error)")
        exit(1)
    }
case "leak":
    if #available(macOS 14.2, *) {
        let seconds = args.count > 2 ? Double(args[2]) ?? 6 : 6
        let file = args.count > 3 ? args[3] : "/tmp/nail-b.aiff"
        let aec = args.contains("--aec")
        exit(runLeak(seconds: seconds, file: file, aec: aec))
    } else {
        print("leak: requires macOS 14.2 or later")
        exit(1)
    }
default:
    print("usage: nail-spike [devices|tap [detik] [--pid P]|mic [detik]|leak [detik] [berkas]]")
    exit(64)
}
