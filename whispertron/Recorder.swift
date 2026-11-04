@preconcurrency import AVFAudio
import AVFoundation
import CoreAudio
import os

func requestMicrophonePermission() async -> Bool {
  await withCheckedContinuation { continuation in
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      continuation.resume(returning: granted)
    }
  }
}

struct Captured {
  var samples: [Float] = []
  var sampleRate: Double = 16000
  var level: Float = 0
  var startedAt = Date()
}

struct AudioStats {
  var rms: Float = 0
  var peak: Float = 0
  var quietFraction: Float = 0

  init(samples: [Float], sampleRate: Double) {
    guard !samples.isEmpty else { return }
    let chunk = max(Int(sampleRate / 10), 1)
    var energy: Float = 0
    var quiet = 0
    var chunks = 0
    for start in stride(from: 0, to: samples.count, by: chunk) {
      let slice = samples[start..<min(start + chunk, samples.count)]
      let chunkEnergy = slice.reduce(0) { $0 + $1 * $1 }
      energy += chunkEnergy
      chunks += 1
      if sqrt(chunkEnergy / Float(slice.count)) < 0.01 { quiet += 1 }
    }
    rms = sqrt(energy / Float(samples.count))
    peak = samples.reduce(0) { max($0, abs($1)) }
    quietFraction = Float(quiet) / Float(chunks)
  }

  var description: String {
    String(format: "rms=%.4f peak=%.3f quiet=%d%%", Double(rms), Double(peak), Int(quietFraction * 100))
  }
}

actor Recorder {
  private var audioEngine = AVAudioEngine()
  private var isRecording = false
  private var isStopping = false
  private var needsNewEngine = false
  private var configurationObserver: NSObjectProtocol?
  private nonisolated let captured = OSAllocatedUnfairLock(initialState: Captured())
  private let logger = Logger(subsystem: "com.glyphack.whispertron", category: "Recorder")

  enum RecorderError: Error {
    case audioEngineError(String)
  }

  init() async throws {
    guard await requestMicrophonePermission() else {
      throw RecorderError.audioEngineError("Microphone permission denied")
    }
    logger.info("Input format: \(self.audioEngine.inputNode.inputFormat(forBus: 0).sampleRate) Hz")
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil
    ) { [weak self] _ in
      Task { await self?.handleConfigurationChange() }
    }
  }

  deinit {
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
  }

  nonisolated var audioLevel: Float { captured.withLock { $0.level } }

  func startRecording() async throws {
    while isStopping {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    guard !isRecording else { return }
    let inputNode = audioEngine.inputNode
    inputNode.removeTap(onBus: 0)
    captured.withLock { $0 = Captured() }
    let captured = self.captured
    inputNode.installTap(onBus: 0, bufferSize: 4800, format: nil) { buffer, _ in
      guard let channel = buffer.floatChannelData?[0] else { return }
      let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
      let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(max(chunk.count, 1)))
      captured.withLock {
        $0.samples.append(contentsOf: chunk)
        $0.sampleRate = buffer.format.sampleRate
        $0.level = min(rms * 10, 1)
      }
    }
    audioEngine.prepare()
    try audioEngine.start()
    isRecording = true
    let format = inputNode.inputFormat(forBus: 0)
    DiagnosticLog.shared.write(
      "recording started device=\"\(Recorder.defaultInputDeviceName())\" format=\(Int(format.sampleRate))Hz \(format.channelCount)ch")
  }

  @discardableResult
  func stopRecording() async -> [Float] {
    guard isRecording, !isStopping else { return [] }
    isStopping = true
    let stoppedAt = Date()
    try? await Task.sleep(nanoseconds: 200_000_000)
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    isRecording = false
    if needsNewEngine { replaceEngine() }
    let recording = captured.withLock { state in
      defer { state = Captured() }
      return state
    }
    isStopping = false
    let samples = Recorder.resample(recording.samples, from: recording.sampleRate)
    let stats = AudioStats(samples: samples, sampleRate: 16000)
    let audioSeconds = String(format: "%.2f", Double(samples.count) / 16000)
    let wallSeconds = String(format: "%.2f", stoppedAt.timeIntervalSince(recording.startedAt))
    DiagnosticLog.shared.write(
      "recording stopped rate=\(Int(recording.sampleRate))Hz raw=\(recording.samples.count) resampled=\(samples.count) audio=\(audioSeconds)s wall=\(wallSeconds)s \(stats.description)")
    return samples
  }

  nonisolated func snapshot(seconds: Double) -> [Float] {
    let (tail, rate) = captured.withLock { (Array($0.samples.suffix(Int($0.sampleRate * seconds))), $0.sampleRate) }
    return Recorder.resample(tail, from: rate)
  }

  private func handleConfigurationChange() {
    logger.info("Audio configuration changed")
    DiagnosticLog.shared.write(
      "audio configuration changed recording=\(isRecording) device=\"\(Recorder.defaultInputDeviceName())\"")
    guard !isRecording else {
      needsNewEngine = true
      return
    }
    replaceEngine()
  }

  private func replaceEngine() {
    needsNewEngine = false
    audioEngine = AVAudioEngine()
    logger.info("New input format: \(self.audioEngine.inputNode.inputFormat(forBus: 0).sampleRate) Hz")
  }

  static func defaultInputDeviceName() -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var deviceID = AudioDeviceID(0)
    var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &deviceSize, &deviceID) == noErr else {
      return "unknown"
    }
    address.mSelector = kAudioObjectPropertyName
    var name: Unmanaged<CFString>?
    var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &nameSize, &name) == noErr, let name else {
      return "unknown"
    }
    return name.takeRetainedValue() as String
  }

  static func resample(_ samples: [Float], from rate: Double) -> [Float] {
    guard rate != 16000, !samples.isEmpty else { return samples }
    let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    guard let converter = AVAudioConverter(from: inFormat, to: outFormat),
      let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
      let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(Double(samples.count) * 16000 / rate) + 1)
    else { return [] }
    input.frameLength = input.frameCapacity
    samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    var fed = false
    converter.convert(to: output, error: nil) { _, status in
      if fed {
        status.pointee = .endOfStream
        return nil
      }
      fed = true
      status.pointee = .haveData
      return input
    }
    return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
  }
}
