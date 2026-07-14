import AppKit

final class LibraryArtworkCache {
  static let shared = LibraryArtworkCache()

  private let images = NSCache<NSString, NSImage>()
  private var loads: [String: Task<NSImage?, Never>] = [:]

  private init() {
    images.countLimit = 200
    images.totalCostLimit = 128 * 1024 * 1024
  }

  func image(for trackID: String) -> NSImage? {
    images.object(forKey: trackID as NSString)
  }

  func load(_ track: Track, using player: PlayerModel) async -> NSImage? {
    if let image = image(for: track.id) { return image }
    if let load = loads[track.id] { return await load.value }

    let load = Task<NSImage?, Never> {
      guard let url = await player.artworkURL(for: track) else { return nil }
      guard
        let data = try? await Task.detached(
          priority: .utility, operation: { try Data(contentsOf: url) }
        ).value,
        let image = NSImage(data: data)
      else { return nil }
      insert(image, for: track.id, fallbackCost: data.count)
      return image
    }
    loads[track.id] = load
    let image = await load.value
    loads[track.id] = nil
    return image
  }

  private func insert(_ image: NSImage, for trackID: String, fallbackCost: Int) {
    let cost = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? fallbackCost
    images.setObject(image, forKey: trackID as NSString, cost: cost)
  }
}
