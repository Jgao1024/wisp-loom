import Foundation
import Testing

@testable import AppRuntime

struct BackendChannelTests {
    private func channel(_ box: Sandbox, idle: TimeInterval = 0, script: String = fakeBackend) throws -> BackendChannel
    {
        BackendChannel(
            config: try box.config(script: script, idle: idle), shell: { _, _ in .success(Data("1".utf8)) },
            log: { _ in })
    }

    private func call(_ channel: BackendChannel, _ id: Int, _ method: String, _ params: String = "{}") -> Inbox<
        CallReply
    > {
        let inbox = Inbox<CallReply>()
        channel.call(id: id, method: method, params: Data(params.utf8), reply: inbox.add)
        return inbox
    }

    /// Re-encoded payloads have no stable key order, so compare with sorted keys.
    private func normalized(_ data: Data) -> String {
        let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        let sorted = object.flatMap {
            try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed])
        }
        return String(decoding: sorted ?? data, as: UTF8.self)
    }

    private func text(_ reply: CallReply) -> String {
        switch reply {
        case .event(let data), .result(let data): normalized(data)
        case .failure(let code, _): "error:" + code
        }
    }

    @Test func startsOnFirstCallAndStreamsEventsThenResult() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let backend = try channel(box)
        defer { backend.shutdown() }
        #expect(backend.processID == nil)
        let replies = await call(backend, 1, "echo", #"{"x":1}"#).wait(count: 3)
        #expect(
            replies.map(text) == [
                #"{"delta":"a","type":"text_delta"}"#, #"{"delta":"b","type":"text_delta"}"#, #"{"x":1}"#,
            ])
        #expect(backend.processID != nil)
    }

    @Test func concurrentRequestsAreAnsweredIndependently() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let backend = try channel(box)
        defer { backend.shutdown() }
        let slow = call(backend, 1, "wait", #"{"seconds":0.4}"#)
        let fast = call(backend, 2, "echo", "7")
        #expect(await fast.wait(count: 3).map(text).last == "7")
        #expect(slow.all.isEmpty)
        #expect(await slow.wait(count: 1).map(text) == [#""done""#])
    }

    @Test func cancelReachesTheBackend() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let backend = try channel(box)
        defer { backend.shutdown() }
        let inbox = call(backend, 1, "slow")
        try await Task.sleep(for: .milliseconds(200))
        backend.cancel(id: 1)
        #expect(await inbox.wait(count: 1).map(text) == ["error:cancelled"])
    }

    @Test func idleBackendExitsAfterGrace() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let backend = try channel(box, idle: 0.2)
        _ = await call(backend, 1, "echo").wait(count: 3)
        let pid = try #require(backend.processID)
        #expect(await waitUntil { kill(pid, 0) != 0 })
        #expect(backend.processID == nil)
    }

    @Test func stuckBackendGetsSIGTERM() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        // Ignores stdin EOF by sleeping forever.
        let backend = try channel(box, idle: 0.1, script: "import time\nwhile True: time.sleep(1)\n")
        _ = call(backend, 1, "echo")
        try await Task.sleep(for: .milliseconds(300))
        let pid = try #require(backend.processID)
        backend.shutdown()
        #expect(await waitUntil { kill(pid, 0) != 0 })
    }

    @Test func crashFailsPendingAndNextCallRestarts() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let backend = try channel(box)
        defer { backend.shutdown() }
        let crashed = call(backend, 1, "crash")
        #expect(await crashed.wait(count: 1).map(text) == ["error:backend_crashed"])
        let again = call(backend, 2, "echo", "5")
        #expect(await again.wait(count: 3).map(text).last == "5")
    }

    @Test func threeStartupCrashesSuspendTheBackend() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let backend = try channel(box, script: "import os\nos._exit(1)\n")
        for id in 1...BackendChannel.maxStartFailures {
            #expect(await call(backend, id, "echo").wait(count: 1).map(text) == ["error:backend_crashed"])
            _ = await waitUntil { backend.processID == nil }
        }
        #expect(backend.isSuspended)
        #expect(await call(backend, 99, "echo").wait(count: 1).map(text) == ["error:backend_suspended"])
    }

    @Test func environmentIsPassed() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let backend = try channel(box)
        defer { backend.shutdown() }
        let reply = try #require(await call(backend, 1, "env").wait(count: 1).first)
        let json = try #require(JSONSerialization.jsonObject(with: Data(text(reply).utf8)) as? [String: String])
        #expect(json["WISP_APP_ID"] == "test.app")
        #expect(json["WISP_LANG"] == "en")
        #expect(json["WISP_DATA_DIR"] == box.data.path)
    }

    @Test func restartAfterRequestsWaitsForInFlightWork() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let backend = try channel(box)
        defer { backend.shutdown() }
        let work = call(backend, 1, "wait", #"{"seconds":0.3}"#)
        try await Task.sleep(for: .milliseconds(100))
        let first = try #require(backend.processID)
        backend.restartAfterRequests()
        #expect(await work.wait(count: 1).map(text) == [#""done""#])
        #expect(await waitUntil { backend.processID == nil })
        _ = await call(backend, 2, "echo").wait(count: 3)
        #expect(try #require(backend.processID) != first)
    }
}
