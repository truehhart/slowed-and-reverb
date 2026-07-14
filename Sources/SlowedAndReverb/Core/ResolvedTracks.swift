import Foundation

nonisolated struct ResolvedTracks: Sendable {
  let tracks: [Track]
  let metadataUpdates: AsyncStream<Track>

  init(tracks: [Track], metadataUpdates: AsyncStream<Track>) {
    self.tracks = tracks
    self.metadataUpdates = metadataUpdates
  }

  init(tracks: [Track]) {
    self.init(tracks: tracks, metadataUpdates: AsyncStream { $0.finish() })
  }
}
