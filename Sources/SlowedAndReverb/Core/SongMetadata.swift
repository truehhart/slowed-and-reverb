import CoreData

@objc(SongMetadata)
nonisolated final class SongMetadata: NSManagedObject {
  @NSManaged var id: String
  @NSManaged var title: String
  @NSManaged var artist: String?
  @NSManaged var webpageURL: String
  @NSManaged var thumbnailURL: String?
  @NSManaged var duration: NSNumber?
  @NSManaged var sourceURL: String?
  @NSManaged var addedAt: Date

  func update(from track: Track, sourceURL: URL?, addedAt: Date = Date()) {
    id = track.id
    title = track.title
    artist = track.artist
    webpageURL = track.webpageURL.absoluteString
    thumbnailURL = track.thumbnailURL?.absoluteString
    duration = track.duration.map(NSNumber.init(value:))
    self.sourceURL = sourceURL?.absoluteString
    self.addedAt = addedAt
  }

  static func makeEntity() -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = "SongMetadata"
    entity.managedObjectClassName = NSStringFromClass(SongMetadata.self)
    entity.properties = [
      attribute("id", type: .stringAttributeType, optional: false),
      attribute("title", type: .stringAttributeType, optional: false),
      attribute("artist", type: .stringAttributeType),
      attribute("webpageURL", type: .stringAttributeType, optional: false),
      attribute("thumbnailURL", type: .stringAttributeType),
      attribute("duration", type: .doubleAttributeType),
      attribute("sourceURL", type: .stringAttributeType),
      attribute("addedAt", type: .dateAttributeType, optional: false),
    ]
    entity.uniquenessConstraints = [["id"]]
    return entity
  }

  private static func attribute(
    _ name: String, type: NSAttributeType, optional: Bool = true
  ) -> NSAttributeDescription {
    let attribute = NSAttributeDescription()
    attribute.name = name
    attribute.attributeType = type
    attribute.isOptional = optional
    return attribute
  }
}
