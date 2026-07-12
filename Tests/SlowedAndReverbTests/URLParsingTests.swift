import Testing

@testable import SlowedAndReverb

@Suite struct StartSecondsTests {
  @Test func parsesNumericAndHMSTimecodes() {
    #expect(URLParsing.startSeconds(from: "https://youtu.be/aaaaaaaaaaa?t=90") == 90)
    #expect(URLParsing.startSeconds(from: "https://youtu.be/aaaaaaaaaaa?t=1h2m3s") == 3723)
    #expect(URLParsing.startSeconds(from: "https://youtube.com/watch?v=aaaaaaaaaaa&start=7") == 7)
  }

  @Test func ignoresMalformedURLsAndTimecodes() {
    #expect(URLParsing.startSeconds(from: "not a url") == 0)
    #expect(URLParsing.startSeconds(from: "https://youtu.be/aaaaaaaaaaa?t=soon") == 0)
  }

  @Test func defaultsToZeroWithoutATimecode() {
    #expect(URLParsing.startSeconds(from: "https://youtu.be/aaaaaaaaaaa") == 0)
  }
}

@Suite struct LooksLikeURLTests {
  @Test func acceptsHTTPSchemesAndRejectsStrayText() {
    #expect(URLParsing.looksLikeURL("https://youtu.be/aaaaaaaaaaa"))
    #expect(URLParsing.looksLikeURL("https://soundcloud.com/artist/track"))
    #expect(URLParsing.looksLikeURL("  http://example.com/x  "))
    #expect(!URLParsing.looksLikeURL("just some copied text"))
    #expect(!URLParsing.looksLikeURL("file:///etc/passwd"))
    #expect(!URLParsing.looksLikeURL(""))
  }
}

@Suite struct VideoIDTests {
  @Test func extractsIDsFromKnownYouTubeURLForms() {
    #expect(URLParsing.videoID(from: "https://youtu.be/aaaaaaaaaaa") == "aaaaaaaaaaa")
    #expect(
      URLParsing.videoID(from: "https://www.youtube.com/watch?v=aaaaaaaaaaa") == "aaaaaaaaaaa")
    #expect(
      URLParsing.videoID(from: "https://www.youtube.com/watch?v=-jRKsiAOAA8") == "-jRKsiAOAA8")
    #expect(URLParsing.videoID(from: "https://youtube.com/shorts/aaaaaaaaaaa") == "aaaaaaaaaaa")
    #expect(URLParsing.videoID(from: "https://youtube.com/embed/aaaaaaaaaaa") == "aaaaaaaaaaa")
    #expect(URLParsing.videoID(from: "https://youtube.com/live/aaaaaaaaaaa") == "aaaaaaaaaaa")
  }

  @Test func returnsNilForPlaylistsAndNonYouTubeOrMalformedURLs() {
    #expect(URLParsing.videoID(from: "https://youtube.com/watch?v=aaaaaaaaaaa&list=PL123") == nil)
    #expect(URLParsing.videoID(from: "https://youtube.com/playlist?list=PL123") == nil)
    #expect(URLParsing.videoID(from: "https://soundcloud.com/artist/track") == nil)
    #expect(URLParsing.videoID(from: "not a url") == nil)
    #expect(URLParsing.videoID(from: "https://youtu.be/short") == nil)  // not 11 chars
  }
}
