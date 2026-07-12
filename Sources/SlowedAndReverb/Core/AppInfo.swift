import Foundation

/// App metadata for the settings UI (version string; UpdaterModel owns update status).
enum AppInfo {
  static var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
  }
}
