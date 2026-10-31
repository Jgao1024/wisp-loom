// Posts a click, keystrokes or a drag at screen coordinates (points). Used by scripts/shot.sh to drive a
// window into the state a screenshot should show; screenshots themselves stay in shot.sh.
import AppKit
import CoreGraphics
import Foundation

func post(_ type: CGEventType, at point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(70_000)
}

func click(_ x: Double, _ y: Double) {
    let point = CGPoint(x: x, y: y)
    post(.mouseMoved, at: point)
    post(.leftMouseDown, at: point)
    post(.leftMouseUp, at: point)
}

func doubleClick(_ x: Double, _ y: Double) {
    let point = CGPoint(x: x, y: y)
    post(.mouseMoved, at: point)
    for click in 1...2 {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(click))
            event?.post(tap: .cghidEventTap)
            usleep(40_000)
        }
    }
}

func rightClick(_ x: Double, _ y: Double) {
    let point = CGPoint(x: x, y: y)
    post(.mouseMoved, at: point)
    for type in [CGEventType.rightMouseDown, .rightMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .right)?
            .post(tap: .cghidEventTap)
        usleep(70_000)
    }
}

func drag(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
    let start = CGPoint(x: x1, y: y1)
    post(.mouseMoved, at: start)
    post(.leftMouseDown, at: start)
    let steps = 12
    for step in 1...steps {
        let t = Double(step) / Double(steps)
        post(.leftMouseDragged, at: CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t))
    }
    post(.leftMouseUp, at: CGPoint(x: x2, y: y2))
}

func activate(_ bundleID: String) {
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
        app.activate(options: [.activateAllWindows])
    }
    usleep(200_000)
}

func away(_ rect: CGRect) {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &displays, &count)
    let bounds =
        displays.map(CGDisplayBounds).first { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) }
        ?? CGDisplayBounds(CGMainDisplayID())
    var point = CGPoint(x: rect.maxX + 24, y: rect.minY + 24)
    if point.x > bounds.maxX - 4 { point = CGPoint(x: rect.minX + 24, y: rect.maxY + 24) }
    if point.y > bounds.maxY - 4 { point = CGPoint(x: max(bounds.minX + 4, rect.minX - 24), y: rect.minY + 24) }
    post(.mouseMoved, at: point)
}

func type(_ text: String) {
    let source = CGEventSource(stateID: .hidSystemState)
    for character in text {
        var units = Array(String(character).utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { continue }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        usleep(18_000)
    }
}

let keyCodes: [String: CGKeyCode] = [
    "return": 36, "tab": 48, "escape": 53, "space": 49, "backspace": 51,
    "down": 125, "up": 126, "left": 123, "right": 124,
    "n": 45, "comma": 43,
]

func press(_ name: String) {
    var flags: CGEventFlags = []
    var keyName = name
    if name.hasPrefix("cmd+") { flags = .maskCommand; keyName = String(name.dropFirst(4)) }
    else if name.hasPrefix("shift+") { flags = .maskShift; keyName = String(name.dropFirst(6)) }
    guard let code = keyCodes[keyName] else {
        FileHandle.standardError.write(Data("ui-event: unknown key \(name)\n".utf8))
        exit(2)
    }
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(20_000)
    up?.post(tap: .cghidEventTap)
    usleep(20_000)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: ui-event click x y | rightclick x y | doubleclick x y | type text | key name | drag x1 y1 x2 y2 | away x y w h | activate bundle-id\n".utf8))
    exit(2)
}
switch args[1] {
case "click" where args.count == 4: click(Double(args[2])!, Double(args[3])!)
case "doubleclick" where args.count == 4: doubleClick(Double(args[2])!, Double(args[3])!)
case "rightclick" where args.count == 4: rightClick(Double(args[2])!, Double(args[3])!)
case "type" where args.count == 3: type(args[2])
case "key" where args.count == 3: press(args[2])
case "drag" where args.count == 6:
    drag(Double(args[2])!, Double(args[3])!, Double(args[4])!, Double(args[5])!)
case "away" where args.count == 6:
    away(CGRect(x: Double(args[2])!, y: Double(args[3])!, width: Double(args[4])!, height: Double(args[5])!))
case "activate" where args.count == 3:
    activate(args[2])
default:
    FileHandle.standardError.write(Data("ui-event: bad arguments\n".utf8))
    exit(2)
}
