import Foundation
import ShellCore
import SwiftUI

/// Sends an event prop's handler id back to the app's JS, with an optional JSON value.
public struct UIEvents: Sendable {
    private let dispatch: @MainActor @Sendable (String, String?) -> Void

    public init(_ dispatch: @escaping @MainActor @Sendable (String, String?) -> Void) { self.dispatch = dispatch }

    @MainActor func send(_ handler: String?, _ value: JSONValue? = nil) {
        guard let handler else { return }
        let json = value.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        dispatch(handler, json)
    }

    static let none = UIEvents { _, _ in }
}

extension EnvironmentValues {
    @Entry var uiEvents = UIEvents.none
}

/// Merges bursts into one call per frame (docs/02-app-protocol.md §2.4).
@MainActor
final class Coalescer {
    private var task: Task<Void, Never>?

    func submit(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(16))
            if !Task.isCancelled { action() }
        }
    }
}

/// A text value owned by the native control: typing shows immediately and the app gets the value a frame
/// later. A value pushed from JS replaces the text only if it is not an echo of something we sent.
struct SyncedText<Content: View>: View {
    let node: UINode
    let prop: String
    let event: String
    @ViewBuilder let content: (Binding<String>) -> Content

    @Environment(\.uiEvents) private var events
    @State private var text = ""
    @State private var inflight: [String] = []
    @State private var coalescer = Coalescer()

    var body: some View {
        content(
            Binding(
                get: { text },
                set: { new in
                    text = new
                    inflight = Array((inflight + [new]).suffix(8))
                    let handler = node.handler(event)
                    coalescer.submit { events.send(handler, .string(new)) }
                })
        )
        .onChange(of: node.string(prop) ?? "", initial: true) { _, incoming in
            if let echo = inflight.firstIndex(of: incoming) {
                inflight.removeFirst(echo + 1)
            } else if incoming != text {
                text = incoming
                inflight = []
            }
        }
    }
}
