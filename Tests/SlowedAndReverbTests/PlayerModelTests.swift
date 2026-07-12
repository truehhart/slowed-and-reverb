import Foundation
import Testing

@testable import SlowedAndReverb

private func makeTrack(_ id: String, title: String? = nil) -> Track {
  Track(
    id: id,
    title: title ?? "track \(id)",
    webpageURL: URL(string: "https://www.youtube.com/watch?v=\(id)")!,
    thumbnailURL: nil
  )
}

@Suite struct PlayIndexTests {
  @Test func doesNotPlayAnOlderDownloadAfterANewerSelectionWins() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let trackA = makeTrack("aaaaaaaaaaa")
    let trackB = makeTrack("bbbbbbbbbbb")
    ytdlp.resolveHandler = { _ in [trackA, trackB] }

    let deferredA = Deferred<URL>()
    ytdlp.downloadHandler = { _, id in
      if id == "aaaaaaaaaaa" { return try await deferredA.value }
      return URL(fileURLWithPath: "/cache/\(id).m4a")
    }

    let loadTask = Task { await player.load(url: "https://youtube.com/playlist?list=demo") }
    await waitUntil(ytdlp.downloadCalls.contains { $0.id == "aaaaaaaaaaa" })
    #expect(player.isDownloading)  // a download is in flight

    await player.playIndex(1)
    deferredA.resolve(URL(fileURLWithPath: "/cache/aaaaaaaaaaa.m4a"))
    await loadTask.value
    await waitUntil(!player.isDownloading)

    #expect(!player.isDownloading)  // both downloads settled
    #expect(engine.playedURLs == [URL(fileURLWithPath: "/cache/bbbbbbbbbbb.m4a")])
    #expect(player.index == 1)
  }

  @Test func retriesAReusedSupersededPreloadTask() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let trackA = makeTrack("aaaaaaaaaaa")
    let trackB = makeTrack("bbbbbbbbbbb")
    let preloadGate = Deferred<URL>()
    var bDownloadCount = 0
    ytdlp.resolveHandler = { _ in [trackA, trackB] }
    ytdlp.downloadHandler = { _, id in
      if id == trackB.id {
        bDownloadCount += 1
        if bDownloadCount == 1 {
          _ = try await preloadGate.value
          throw YtDlpError.superseded
        }
      }
      return URL(fileURLWithPath: "/cache/\(id).m4a")
    }

    await player.load(url: "https://youtube.com/playlist?list=demo")
    await waitUntil(ytdlp.downloadCalls.contains { $0.id == trackB.id })

    let playTask = Task { await player.playIndex(1) }
    preloadGate.resolve(URL(fileURLWithPath: "/cache/unused.m4a"))
    await playTask.value

    #expect(bDownloadCount == 2)
    #expect(player.index == 1)
    #expect(player.status == .playing)
    #expect(player.lastError == nil)
    #expect(engine.playedURLs.last == URL(fileURLWithPath: "/cache/bbbbbbbbbbb.m4a"))
  }

  @Test func wrapsAtTheEndWhenQueueRepeatIsEnabled() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let trackA = makeTrack("aaaaaaaaaaa")
    let trackB = makeTrack("bbbbbbbbbbb")
    ytdlp.resolveHandler = { _ in [trackA, trackB] }

    await player.load(url: "https://youtube.com/playlist?list=demo")
    await player.skipNext()
    #expect(player.index == 1)

    player.toggleRepeat()  // off -> queue
    #expect(player.repeatMode == .queue)
    await player.next()  // manual next, not from-ended, but index+1 >= count so wraps via repeat

    #expect(player.index == 0)
    #expect(engine.playedURLs.last == URL(fileURLWithPath: "/cache/aaaaaaaaaaa.m4a"))
  }

  @Test func prefetchesTheNextTwoTracksAndStopsAtTheLookaheadWindow() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let tracks = ["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc", "ddddddddddd"].map { makeTrack($0) }
    ytdlp.resolveHandler = { _ in tracks }

    await player.load(url: "https://youtube.com/playlist?list=demo")
    await waitUntil(ytdlp.downloadCalls.contains { $0.id == "ccccccccccc" })

    let ids = Set(ytdlp.downloadCalls.map(\.id))
    #expect(ids.contains("aaaaaaaaaaa"))
    #expect(ids.contains("bbbbbbbbbbb"))
    #expect(ids.contains("ccccccccccc"))
    #expect(!ids.contains("ddddddddddd"))
  }

  @Test func skipsFailedTracksAndDeclaresTheQueueDeadOnceEveryTrackFails() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let tracks = ["aaaaaaaaaaa", "bbbbbbbbbbb"].map { makeTrack($0) }
    ytdlp.resolveHandler = { _ in tracks }
    ytdlp.downloadHandler = { _, _ in throw YtDlpError.failed("age-gated") }

    await player.load(url: "https://youtube.com/playlist?list=demo")

    #expect(player.status == .failed)
    #expect(player.lastError != nil)
  }
}

@Suite struct AddTests {
  @Test func onlyStartsPlaybackWhenNothingIsSelectedYet() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let trackA = makeTrack("aaaaaaaaaaa")
    let trackB = makeTrack("bbbbbbbbbbb")
    ytdlp.resolveHandler = { _ in [trackA] }

    let added = await player.add(url: "https://youtu.be/aaaaaaaaaaa")
    #expect(added == 1)
    #expect(player.index == 0)  // nothing was selected, so the append started playback

    ytdlp.resolveHandler = { _ in [trackB] }
    let addedAgain = await player.add(url: "https://youtu.be/bbbbbbbbbbb")
    #expect(addedAgain == 1)
    #expect(player.index == 0)  // already playing; the second add() must not steal playback
    #expect(player.queue.count == 2)
  }
}

@Suite struct URLCacheTests {
  @Test func loadsANonYouTubeURLWithoutResolvingAgain() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let url = "https://soundcloud.com/artist/song"
    let path = URL(fileURLWithPath: "/cache/soundcloud-track.m4a")
    ytdlp.cachedAudioByURL[url] = CachedAudioInfo(
      path: path, id: "soundcloud-track", title: "Cached Song", webpageURL: URL(string: url),
      thumbnailURL: nil, duration: 180)

    await player.load(url: url)

    #expect(ytdlp.resolveCalls.isEmpty)
    #expect(player.currentTrack?.id == "soundcloud-track")
    #expect(player.currentTrack?.title == "Cached Song")
    #expect(engine.playedURLs == [path])
  }

  @Test func addsACachedYouTubeTrackWithoutResolvingAgain() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let id = "-jRKsiAOAA8"
    let url = "https://www.youtube.com/watch?v=\(id)"
    let path = URL(fileURLWithPath: "/cache/\(id).m4a")
    ytdlp.cachedAudioByID[id] = CachedAudioInfo(
      path: path, id: id, title: "Falling Down", webpageURL: URL(string: url),
      thumbnailURL: nil, duration: 198)

    let added = await player.add(url: url)

    #expect(added == 1)
    #expect(ytdlp.resolveCalls.isEmpty)
    #expect(player.currentTrack?.id == id)
    #expect(engine.playedURLs == [path])
  }
}

@Suite struct TogglePauseTests {
  @Test func replaysTheCurrentTrackAfterTheQueueEnded() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    ytdlp.resolveHandler = { _ in [makeTrack("aaaaaaaaaaa")] }

    await player.load(url: "https://youtu.be/aaaaaaaaaaa")
    engine.onEnded?()  // natural end of the last track -> idle
    await waitUntil(player.status == .idle)

    // The engine unloaded the file on stop(), so restart() fails and the
    // player must replay the track from the cache instead of going dead.
    engine.restartSucceeds = false
    await player.togglePause()

    #expect(player.status == .playing)
    #expect(engine.playedURLs.count == 2)
  }
}

@Suite struct PrevTests {
  @Test func restartsTheCurrentTrackWhenPastTheRestartThreshold() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let tracks = ["aaaaaaaaaaa", "bbbbbbbbbbb"].map { makeTrack($0) }
    ytdlp.resolveHandler = { _ in tracks }

    await player.load(url: "https://youtube.com/playlist?list=demo")
    await player.skipNext()
    engine.currentTime = 3

    await player.prev()

    #expect(engine.restartCallCount == 1)
    #expect(player.index == 1)
    #expect(player.status == .playing)
  }

  @Test func goesToThePreviousTrackWhenNearTheStart() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let tracks = ["aaaaaaaaaaa", "bbbbbbbbbbb"].map { makeTrack($0) }
    ytdlp.resolveHandler = { _ in tracks }

    await player.load(url: "https://youtube.com/playlist?list=demo")
    await player.skipNext()
    engine.currentTime = 1  // under PREV_RESTART_SECONDS

    await player.prev()

    #expect(player.index == 0)
  }
}

@Suite struct ClearTests {
  @Test func bumpsTheTokenAndStopsPlayback() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let tracks = ["aaaaaaaaaaa"].map { makeTrack($0) }
    ytdlp.resolveHandler = { _ in tracks }

    await player.load(url: "https://youtu.be/aaaaaaaaaaa")
    #expect(player.status == .playing)

    await player.clear()

    #expect(player.status == .idle)
    #expect(player.queue.isEmpty)
    #expect(player.index == -1)
    #expect(engine.stopCallCount >= 1)
  }

  @Test func cancelsAnInFlightDownloadAndPreventsLatePlayback() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let gate = Deferred<URL>()
    let track = makeTrack("aaaaaaaaaaa")
    ytdlp.resolveHandler = { _ in [track] }
    ytdlp.downloadHandler = { _, _ in try await gate.value }

    let loadTask = Task { await player.load(url: "https://youtu.be/aaaaaaaaaaa") }
    await waitUntil(ytdlp.downloadCalls.count == 1)
    #expect(player.isDownloading)

    await player.clear()
    #expect(!player.isDownloading)
    #expect(player.downloadProgress == nil)
    #expect(ytdlp.cancelCount == 1)

    gate.resolve(URL(fileURLWithPath: "/cache/late.m4a"))
    await loadTask.value
    #expect(engine.playedURLs.isEmpty)
  }
}

@Suite struct RequestTokenTests {
  @Test func ignoresAnOlderLoadThatResolvesAfterANewerLoad() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let firstGate = Deferred<[Track]>()
    let firstTrack = makeTrack("aaaaaaaaaaa")
    let secondTrack = makeTrack("bbbbbbbbbbb")

    ytdlp.asyncResolveHandler = { url in
      if url == "first" { return try await firstGate.value }
      return [secondTrack]
    }

    let firstLoad = Task { await player.load(url: "first") }
    await waitUntil(ytdlp.resolveCalls.count == 1)

    await player.load(url: "second")
    firstGate.resolve([firstTrack])
    await firstLoad.value

    #expect(player.queue.map(\.id) == [secondTrack.id])
    #expect(player.index == 0)
    #expect(engine.playedURLs == [URL(fileURLWithPath: "/cache/\(secondTrack.id).m4a")])
  }
}

@Suite struct RepeatOneTests {
  @Test func replaysTheSameTrackOnNaturalEnd() async {
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: engine)
    let tracks = ["aaaaaaaaaaa", "bbbbbbbbbbb"].map { makeTrack($0) }
    ytdlp.resolveHandler = { _ in tracks }

    await player.load(url: "https://youtube.com/playlist?list=demo")
    player.toggleRepeat()  // off -> queue
    player.toggleRepeat()  // queue -> one
    #expect(player.repeatMode == .one)

    engine.onEnded?()
    await waitUntil(engine.playedURLs.count >= 2)

    #expect(player.index == 0)  // repeat-one replays index 0, not advancing
  }
}
