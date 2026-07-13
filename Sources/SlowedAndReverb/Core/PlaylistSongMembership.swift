import CoreData

@objc(PlaylistSongMembership)
nonisolated final class PlaylistSongMembership: NSManagedObject {
  @NSManaged var playlistID: String
  @NSManaged var songID: String
  @NSManaged var position: Int64

  static func makeEntity() -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = "PlaylistSongMembership"
    entity.managedObjectClassName = NSStringFromClass(PlaylistSongMembership.self)
    entity.properties = [
      attribute("playlistID", type: .stringAttributeType, optional: false),
      attribute("songID", type: .stringAttributeType, optional: false),
      attribute("position", type: .integer64AttributeType, optional: false),
    ]
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
