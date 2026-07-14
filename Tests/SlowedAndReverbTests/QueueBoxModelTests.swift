import Testing

@testable import SlowedAndReverb

@Suite struct QueueBoxModelTests {
  @Test func ignoresInputRejectedByPasteToAdd() async {
    let ytdlp = FakeYtDlpClient()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: FakeAudioEngine())
    let queueBox = QueueBoxModel()
    let status = StatusLine()
    queueBox.urlText = "not a URL"

    await queueBox.submit(player: player, status: status)

    #expect(ytdlp.resolveCalls.isEmpty)
    #expect(queueBox.urlText == "not a URL")
    #expect(status.message == nil)
  }

  @Test func acceptsAndTrimsInputAcceptedByPasteToAdd() async {
    let ytdlp = FakeYtDlpClient()
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: FakeAudioEngine())
    let queueBox = QueueBoxModel()
    let status = StatusLine()
    queueBox.urlText = "  https://example.com/playlist  \n"

    await queueBox.submit(player: player, status: status)

    #expect(ytdlp.resolveCalls == ["https://example.com/playlist"])
    #expect(queueBox.urlText.isEmpty)
  }
}
