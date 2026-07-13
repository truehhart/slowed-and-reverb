import CoreData

@objc(PlaylistMetadata)
nonisolated final class PlaylistMetadata: NSManagedObject {
  @NSManaged var id: String
  @NSManaged var title: String
  @NSManaged var sourceURL: String
  @NSManaged var addedAt: Date

  static func makeEntity() -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = "PlaylistMetadata"
    entity.managedObjectClassName = NSStringFromClass(PlaylistMetadata.self)
    entity.properties = [
      attribute("id", type: .stringAttributeType, optional: false),
      attribute("title", type: .stringAttributeType, optional: false),
      attribute("sourceURL", type: .stringAttributeType, optional: false),
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
