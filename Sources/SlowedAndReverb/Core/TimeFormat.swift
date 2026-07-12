import Foundation

/// Pure time formatting for the seek row and tape counter (ports the web
/// UI's `fmt` / `fmtCounter`, clamping negatives and non-finite to zero).
nonisolated enum TimeFormat {
  /// mm:ss
  static func clock(_ t: TimeInterval) -> String {
    let t = t.isFinite && t > 0 ? t : 0
    let m = Int(t) / 60
    let s = Int(t) % 60
    return String(format: "%d:%02d", m, s)
  }

  /// hh:mm:ss tape counter
  static func counter(_ t: TimeInterval) -> String {
    let t = t.isFinite && t > 0 ? t : 0
    let h = Int(t) / 3600
    let m = Int(t) % 3600 / 60
    let s = Int(t) % 60
    return String(format: "%02d:%02d:%02d", h, m, s)
  }

  /// "1.2 GB" style byte size, matching the web gauge's `fmtSize`.
  static func byteSize(_ bytes: UInt64) -> (value: String, unit: String) {
    let units = ["B", "KB", "MB", "GB"]
    var v = Double(bytes)
    var i = 0
    while v >= 1024, i < units.count - 1 {
      v /= 1024
      i += 1
    }
    return (i == 0 ? String(Int(v.rounded())) : String(format: "%.1f", v), units[i])
  }
}
