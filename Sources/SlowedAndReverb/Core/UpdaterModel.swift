import Foundation
import Observation
import Sparkle

/// Thin wrapper over SPUStandardUpdaterController with silent
/// auto-download+install enabled (parity with the old Tauri app). `statusText`
/// is a best-effort summary; live download percent needs a custom SPUUserDriver.
@MainActor
@Observable
final class UpdaterModel: NSObject, SPUUpdaterDelegate {
  private var controller: SPUStandardUpdaterController?

  private(set) var statusText: String?

  override init() {
    super.init()
    // No bundle identifier means `swift run`/`swift test`, not the packaged
    // .app: Sparkle needs an Info.plist-backed bundle, so stay disabled.
    guard Bundle.main.bundleIdentifier != nil else {
      Log.updater.notice("no app bundle detected; Sparkle disabled")
      return
    }
    let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: self,
      userDriverDelegate: nil
    )
    controller.updater.automaticallyChecksForUpdates = true
    controller.updater.automaticallyDownloadsUpdates = true
    controller.updater.checkForUpdatesInBackground()
    self.controller = controller
  }

  func checkForUpdates() {
    controller?.checkForUpdates(nil)
  }

  // MARK: - SPUUpdaterDelegate

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    statusText = "update available: \(item.displayVersionString)"
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    statusText = "up to date"
  }

  func updater(
    _ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest
  ) {
    statusText = "downloading update \(item.displayVersionString)"
  }

  func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
    statusText = "update downloaded"
  }

  func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
    statusText = "installing update"
  }

  func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
    statusText = "restart to update"
  }

  func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
    statusText = "restarting to update"
  }

  func updater(
    _ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error
  ) {
    statusText = "update download failed: \(error.localizedDescription)"
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    statusText = "update check failed: \(error.localizedDescription)"
  }

}
