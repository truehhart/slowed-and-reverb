import AVFoundation
import Foundation

/// Graph: player -> varispeed -> dry+[highpass -> reverb -> wetMixer] -> mainMixer.
@MainActor
final class AVFoundationAudioEngine: AudioEngineProtocol {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let varispeed = AVAudioUnitVarispeed()
  private let eq = AVAudioUnitEQ(numberOfBands: 1)
  private let reverb = AVAudioUnitReverb()
  private let wetMixer = AVAudioMixerNode()
  private let levelMeterState = LevelMeterState()
  /// Format the player->varispeed->(dry/wet) chain is currently
  /// wired for. yt-dlp m4a streams are often 48kHz; AVAudioPlayerNode does
  /// not resample, so the chain is rebuilt to match each file on play().
  private var chainFormat: AVAudioFormat?
  private var mainMixerDryBus: AVAudioNodeBus?
  private nonisolated(unsafe) var configurationObserver: NSObjectProtocol?

  // Position tracking: derive currentTime from
  // a start offset plus elapsed wall clock scaled by `speed`, instead of
  // trusting AVAudioPlayerNode's own render timeline (which the varispeed
  // and downstream effects would make hard to reason about here).
  private var currentFile: AVAudioFile?
  private var startOffset: TimeInterval = 0
  private var startedAt: CFTimeInterval = 0
  /// A live scheduled segment is driving playback right now (false while paused).
  private var hasSource = false
  private var paused = false
  private var generation: UInt64 = 0

  private(set) var duration: TimeInterval = 0

  var speed: Double = 0.85 {
    willSet {
      guard hasSource else { return }  // only an actively-playing source needs rebasing
      startOffset = currentTime  // uses the still-old `speed`
      startedAt = CACurrentMediaTime()
    }
    didSet { applySpeed() }
  }

  var reverbMix: Double = 0.6 {
    didSet { wetMixer.outputVolume = Float(reverbMix) }
  }

  var reverbSpace: ReverbSpace = .hall {
    didSet { applyReverbPreset() }
  }

  var reverbCutoff: Double = 80 {
    didSet { eq.bands[0].frequency = Float(reverbCutoff) }
  }

  var volume: Double = 1 {
    didSet { applyMasterGain() }
  }

  var isMuted = false {
    didSet { applyMasterGain() }
  }

  var onEnded: (() -> Void)?

  init() {
    buildGraph()
    do {
      try engine.start()
    } catch {
      Log.audio.error("engine start failed: \(error, privacy: .public)")
    }

    // The block form (vs. addObserver(_:selector:...)) lets us force this
    // closure non-isolated below: AVAudioEngine posts this notification
    // from an arbitrary thread, and an implicitly-MainActor closure here
    // previously crashed the realtime render thread on invocation.
    let handler: @Sendable (Notification) -> Void = { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in self.recoverFromConfigurationChange() }
    }
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: nil,
      using: handler
    )
  }

  deinit {
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
  }

  private func buildGraph() {
    [playerNode, varispeed, eq, reverb, wetMixer].forEach(engine.attach)

    eq.bands[0].filterType = .highPass
    eq.bands[0].frequency = Float(reverbCutoff)
    eq.bands[0].bypass = false

    wetMixer.outputVolume = Float(reverbMix)
    applyReverbPreset()
    applyMasterGain()
    applySpeed()

    // Nominal placeholder so the graph is fully wired before the first
    // play(); connectChain(format:) rebuilds this for the actual file.
    connectChain(format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!)

    let state = levelMeterState
    // Forced @Sendable/non-isolated: AVAudioEngine calls tap blocks on the
    // realtime render thread, not MainActor (see the note in init above).
    let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
      state.process(buffer: buffer)
    }
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil, block: tapBlock)
  }

  /// (Re)wire player->varispeed->(dry/wet)->mainMixer for
  /// `format`. A fixed dry-path input bus on mainMixer is reused across
  /// rebuilds so repeated track changes don't leak input buses.
  private func connectChain(format: AVAudioFormat) {
    guard chainFormat != format else { return }
    let dryBus = mainMixerDryBus ?? engine.mainMixerNode.nextAvailableInputBus
    mainMixerDryBus = dryBus

    engine.disconnectNodeOutput(playerNode)
    engine.disconnectNodeOutput(varispeed)
    engine.disconnectNodeOutput(eq)
    engine.disconnectNodeOutput(reverb)
    engine.disconnectNodeOutput(wetMixer)

    engine.connect(playerNode, to: varispeed, format: format)
    engine.connect(
      varispeed,
      to: [
        AVAudioConnectionPoint(node: engine.mainMixerNode, bus: dryBus),
        AVAudioConnectionPoint(node: eq, bus: 0),
      ],
      fromBus: 0,
      format: format
    )
    engine.connect(eq, to: reverb, format: format)
    engine.connect(reverb, to: wetMixer, format: format)
    engine.connect(wetMixer, to: engine.mainMixerNode, format: format)
    chainFormat = format
  }

  /// macOS has no AVAudioSession; a device/route change stops the engine
  /// instead. An engine restart drops any scheduled segment, so resume by
  /// rescheduling from the current position instead of a bare `play()`,
  /// which would otherwise stall silently while the clock keeps advancing.
  private func recoverFromConfigurationChange() {
    guard hasSource, !paused else { return }
    do {
      try engine.start()
    } catch {
      Log.audio.error("engine restart after route change failed: \(error, privacy: .public)")
      return
    }
    startSource(offset: currentTime)
  }

  private func applySpeed() {
    varispeed.rate = Float(speed)
  }

  private func applyReverbPreset() {
    let preset: AVAudioUnitReverbPreset
    switch reverbSpace {
    case .room: preset = .mediumRoom
    case .hall: preset = .largeHall
    case .plate: preset = .plate
    }
    reverb.loadFactoryPreset(preset)
    reverb.wetDryMix = 100
  }

  private func applyMasterGain() {
    engine.mainMixerNode.outputVolume = (isMuted || paused) ? 0 : Float(volume)
  }

  var currentTime: TimeInterval {
    guard currentFile != nil else { return 0 }
    if paused { return startOffset }
    let elapsed = (CACurrentMediaTime() - startedAt) * speed
    return max(0, min(startOffset + elapsed, duration))
  }

  func play(fileURL: URL, startAt: TimeInterval) throws {
    let file = try AVAudioFile(forReading: fileURL)
    let newDuration = Double(file.length) / file.fileFormat.sampleRate
    stopSource()
    connectChain(format: file.processingFormat)
    currentFile = file
    duration = newDuration
    startSource(offset: max(0, min(startAt, newDuration)))
    ensureEngineRunning()
  }

  func stop() {
    stopSource()
    currentFile = nil
    duration = 0
  }

  @discardableResult
  func togglePause() -> Bool {
    if !paused, hasSource {
      startOffset = currentTime
      paused = true
      applyMasterGain()
      stopSource()
      return true
    }
    guard paused else { return false }
    startSource(offset: startOffset)
    ensureEngineRunning()
    return false
  }

  @discardableResult
  func restart() -> Bool {
    guard currentFile != nil else { return false }
    stopSource()
    paused = false
    startSource(offset: 0)
    ensureEngineRunning()
    return true
  }

  func seek(to time: TimeInterval) {
    guard hasSource || paused, currentFile != nil else { return }
    let target = max(0, min(time, duration))
    if paused {
      startOffset = target
      return
    }
    stopSource()
    startSource(offset: target)
  }

  func levels() -> (l: Float, r: Float) {
    let (targetL, targetR) = levelMeterState.snapshot()
    envL = ballistics(current: envL, target: targetL)
    envR = ballistics(current: envR, target: targetR)
    return (envL, envR)
  }

  // MARK: - source lifecycle

  private func startSource(offset: TimeInterval) {
    guard let file = currentFile else { return }
    let sampleRate = file.fileFormat.sampleRate
    let startFrame = AVAudioFramePosition(offset * sampleRate)
    let remaining = AVAudioFrameCount(max(0, file.length - startFrame))
    paused = false
    hasSource = true
    startOffset = offset
    startedAt = CACurrentMediaTime()
    applyMasterGain()
    generation &+= 1
    let myGeneration = generation
    guard remaining > 0 else {
      // Nothing left to play from this offset: treat as an immediate end,
      // same generation-guard path as a natural end mid-playback.
      Task { @MainActor [weak self] in self?.fireEndedIfCurrent(expected: myGeneration) }
      return
    }
    // Forced @Sendable/non-isolated: AVAudioPlayerNode fires completion
    // handlers from the realtime render thread (see the note in init).
    let completion: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in self.fireEndedIfCurrent(expected: myGeneration) }
    }
    playerNode.scheduleSegment(
      file,
      startingFrame: startFrame,
      frameCount: remaining,
      at: nil,
      completionCallbackType: .dataPlayedBack,
      completionHandler: completion
    )
    playerNode.play()
  }

  /// Stop without firing onEnded: bump generation first so the outgoing
  /// segment's completion handler (fired by playerNode.stop()) is ignored,
  /// mirroring the TS `source === src` guard. Leaves `paused` untouched;
  /// callers that are entering/leaving pause set it themselves.
  private func stopSource() {
    generation &+= 1
    if hasSource {
      playerNode.stop()
    }
    hasSource = false
  }

  private func fireEndedIfCurrent(expected: UInt64) {
    guard expected == generation else { return }
    hasSource = false
    onEnded?()
  }

  private func ensureEngineRunning() {
    guard !engine.isRunning else { return }
    do {
      try engine.start()
    } catch {
      Log.audio.error("engine start failed: \(error, privacy: .public)")
    }
  }

  // MARK: - VU envelope (polled ~60fps by the UI via levels())

  private var envL: Float = 0
  private var envR: Float = 0

  private func ballistics(current: Float, target: Float) -> Float {
    let k: Float = target > current ? 0.5 : 0.1
    return current + (target - current) * k
  }
}
