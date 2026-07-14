import AVFoundation
import Testing

@testable import SlowedAndReverb

@Suite struct LevelMeterStateTests {
  @Test func emphasizesTransientAboveSettledTone() throws {
    let state = LevelMeterState()
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
    buffer.frameLength = 1024
    let samples = try #require(buffer.floatChannelData?[0])

    for phase in 0..<30 {
      for frame in 0..<1024 {
        samples[frame] = 0.25 * sin(Float(phase * 1024 + frame) * 2 * .pi * 1_000 / 48_000)
      }
      state.process(buffer: buffer)
    }
    let settled = state.snapshot().0

    for frame in 0..<1024 { samples[frame] = 0 }
    for frame in 0..<48 { samples[frame] = frame.isMultiple(of: 2) ? 1 : -1 }
    state.process(buffer: buffer)
    let transient = state.snapshot().0

    #expect(transient > settled + 0.2)
  }

  @Test func sustainedBassTracksSignalLevel() throws {
    let state = LevelMeterState()
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
    buffer.frameLength = 1024
    let samples = try #require(buffer.floatChannelData?[0])

    for phase in 0..<60 {
      for frame in 0..<1024 {
        samples[frame] = 0.95 * sin(Float(phase * 1024 + frame) * 2 * .pi * 60 / 48_000)
      }
      state.process(buffer: buffer)
    }

    let loud = state.snapshot().0

    for phase in 60..<90 {
      for frame in 0..<1024 {
        samples[frame] = 0.35 * sin(Float(phase * 1024 + frame) * 2 * .pi * 60 / 48_000)
      }
      state.process(buffer: buffer)
    }
    let quieter = state.snapshot().0

    #expect(loud < 0.85)
    #expect(quieter < loud - 0.1)
  }

  @Test func transientBreaksAboveEstablishedBassWall() throws {
    let state = LevelMeterState()
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
    buffer.frameLength = 1024
    let samples = try #require(buffer.floatChannelData?[0])

    for phase in 0..<60 {
      for frame in 0..<1024 {
        samples[frame] = 0.7 * sin(Float(phase * 1024 + frame) * 2 * .pi * 60 / 48_000)
      }
      state.process(buffer: buffer)
    }
    let bassWall = state.snapshot().0

    for frame in 0..<1024 {
      samples[frame] = 0.7 * sin(Float(60 * 1024 + frame) * 2 * .pi * 60 / 48_000)
    }
    for frame in 0..<48 { samples[frame] = frame.isMultiple(of: 2) ? 0.9 : -0.9 }
    state.process(buffer: buffer)

    #expect(state.snapshot().0 > bassWall + 0.05)
  }
}
