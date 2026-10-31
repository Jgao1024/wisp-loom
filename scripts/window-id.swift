// Finds an on-screen window by owner name (and optional title) and prints "id\twidth\theight\ttitle".
// Used by scripts/shot.sh; screenshots need the window number, not just the app.
import CoreGraphics
import Foundation

var owner = "Wisp"
var title = ""
var minWidth = 200.0

var args = Array(CommandLine.arguments.dropFirst())
while let flag = args.first {
    args.removeFirst()
    switch flag {
    case "--owner": owner = args.first ?? owner
    case "--title": title = args.first ?? title
    case "--min-width": minWidth = Double(args.first ?? "") ?? minWidth
    default: continue
    }
    if !args.isEmpty { args.removeFirst() }
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []

for window in windows {
    guard window[kCGWindowLayer as String] as? Int == 0 else { continue }
    let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
    guard ownerName.localizedCaseInsensitiveContains(owner) else { continue }
    let windowName = window[kCGWindowName as String] as? String ?? ""
    guard title.isEmpty || windowName.localizedCaseInsensitiveContains(title) else { continue }
    guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
        let width = bounds["Width"], let height = bounds["Height"], width >= minWidth
    else { continue }
    let number = window[kCGWindowNumber as String] as? Int ?? 0
    print("\(number)\t\(Int(width))\t\(Int(height))\t\(windowName)")
    exit(0)
}
exit(1)
