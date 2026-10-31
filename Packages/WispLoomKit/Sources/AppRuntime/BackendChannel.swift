import Foundation
import ShellCore

public struct BackendConfig: Sendable {
    public var appID: AppID
    /// `["backend/agent"]` runs a file relative to `directory`; a bare name like `python3` is looked up in PATH.
    public var command: [String]
    public var directory: URL
    public var dataDirectory: URL
    public var language: String
    /// Seconds without requests before stdin is closed; 0 keeps the backend running.
    public var idle: TimeInterval
    /// Time between closing stdin and SIGTERM.
    public var termGrace: TimeInterval

    public init(
        appID: AppID, command: [String], directory: URL, dataDirectory: URL, language: String, idle: TimeInterval,
        termGrace: TimeInterval = 2
    ) {
        self.appID = appID
        self.command = command
        self.directory = directory
        self.dataDirectory = dataDirectory
        self.language = language
        self.idle = idle
        self.termGrace = termGrace
    }
}

/// The app's backend subprocess: starts on the first call, speaks JSON Lines over stdin/stdout,
/// exits when idle, and restarts after a crash. See docs/02-app-protocol.md §3.
///
/// `@unchecked Sendable`: all mutable state is touched only on `queue`; reader threads hand data over with `queue.async`.
public final class BackendChannel: @unchecked Sendable {
    public static let maxStartFailures = 3

    /// A process plus its read buffer. Replaced on every launch, so late output of an old one is ignorable.
    private final class Launch: @unchecked Sendable {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        var buffer = Data()
        var answered = false
    }

    private let config: BackendConfig
    private let shell: @Sendable (String, Data) -> Result<Data, CallFailure>
    private let log: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "wisp.backend")
    private var launch: Launch?
    private var pending: [Int: @Sendable (CallReply) -> Void] = [:]
    private var idleTimer: DispatchWorkItem?
    private var startFailures = 0
    private var restartWhenIdle = false

    /// `shell` answers the backend's own `shell.*` requests.
    public init(
        config: BackendConfig, shell: @escaping @Sendable (String, Data) -> Result<Data, CallFailure>,
        log: @escaping @Sendable (String) -> Void
    ) {
        _ = Self.ignoreSIGPIPE
        self.config = config
        self.shell = shell
        self.log = log
    }

    /// A write to a dead backend must come back as EPIPE, not kill the shell.
    private static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    public var processID: Int32? { queue.sync { launch?.process.processIdentifier } }
    public var isSuspended: Bool { queue.sync { startFailures >= Self.maxStartFailures } }

    /// `id` is chosen by the caller and must be unique among open requests.
    public func call(id: Int, method: String, params: Data, reply: @escaping @Sendable (CallReply) -> Void) {
        queue.async { [self] in
            guard startFailures < Self.maxStartFailures else {
                return reply(
                    .failure(code: "backend_suspended", message: "backend failed to start \(startFailures) times"))
            }
            guard let launch = running() else {
                return reply(.failure(code: "backend_crashed", message: "backend could not be started"))
            }
            idleTimer?.cancel()
            pending[id] = reply
            var line = Data(#"{"id":\#(id),"method":"#.utf8)
            line.append((try? JSONEncoder().encode(method)) ?? Data(#""""#.utf8))
            line.append(Data(#","params":"#.utf8))
            line.append(params)
            line.append(Data("}\n".utf8))
            write(line, to: launch)
        }
    }

    public func cancel(id: Int) {
        queue.async { [self] in
            guard pending[id] != nil, let launch else { return }
            write(Data(#"{"method":"cancel","params":{"id":\#(id)}}"#.utf8 + [0x0A]), to: launch)
        }
    }

    /// Hot reload: restart on the next call. Waits for in-flight requests so nothing is cut off.
    public func restartAfterRequests() {
        queue.async { [self] in
            startFailures = 0
            if pending.isEmpty { stop() } else { restartWhenIdle = true }
        }
    }

    public func shutdown() { queue.async { [self] in stop() } }

    // MARK: - Process lifecycle (all on `queue`)

    private func running() -> Launch? {
        if let launch { return launch }
        let launch = Launch()
        do {
            try prepare(launch)
            try launch.process.run()
        } catch {
            log("[\(config.appID.rawValue)] backend failed to start: \(error)")
            startFailures += 1
            return nil
        }
        self.launch = launch
        let appID = config.appID.rawValue
        Thread.detachNewThread { [self] in
            Self.read(launch.stdout.fileHandleForReading) { data in queue.async { self.consume(data, from: launch) } }
            launch.process.waitUntilExit()
            queue.async { self.exited(launch) }
        }
        Thread.detachNewThread { [log] in
            var text = Data()
            Self.read(launch.stderr.fileHandleForReading) { data in
                text.append(data)
                while let newline = text.firstIndex(of: 0x0A) {
                    log("[\(appID)] \(String(decoding: text[..<newline], as: UTF8.self))")
                    text.removeSubrange(...newline)
                }
            }
        }
        return launch
    }

    private func prepare(_ launch: Launch) throws {
        try FileManager.default.createDirectory(at: config.dataDirectory, withIntermediateDirectories: true)
        let process = launch.process
        let program = config.command[0]
        if program.contains("/") {
            process.executableURL = URL(fileURLWithPath: program, relativeTo: config.directory).absoluteURL
            process.arguments = Array(config.command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = config.command
        }
        process.currentDirectoryURL = config.directory
        process.environment = ProcessInfo.processInfo.environment.merging([
            "WISP_APP_ID": config.appID.rawValue,
            "WISP_DATA_DIR": config.dataDirectory.path,
            "WISP_LANG": config.language,
        ]) { $1 }
        process.standardInput = launch.stdin
        process.standardOutput = launch.stdout
        process.standardError = launch.stderr
    }

    /// Blocking read loop for a reader thread; returns at EOF. `availableData` returns as soon as any bytes
    /// arrive, whereas `read(upToCount:)` waits for the full count.
    private static func read(_ handle: FileHandle, _ deliver: (Data) -> Void) {
        while case let data = handle.availableData, !data.isEmpty { deliver(data) }
    }

    private func exited(_ launch: Launch) {
        guard launch === self.launch else { return }
        self.launch = nil
        idleTimer?.cancel()
        // A start that never produced a message counts against the 3-strike limit.
        startFailures = launch.answered ? 0 : startFailures + 1
        let status = launch.process.terminationStatus
        log("[\(config.appID.rawValue)] backend exited unexpectedly (status \(status))")
        let failed = pending
        pending = [:]
        for reply in failed.values {
            reply(.failure(code: "backend_crashed", message: "backend exited (status \(status))"))
        }
    }

    /// Close stdin so the backend exits by itself; SIGTERM if it is still alive after the grace period.
    private func stop() {
        guard let launch else { return }
        self.launch = nil
        idleTimer?.cancel()
        try? launch.stdin.fileHandleForWriting.close()
        queue.asyncAfter(deadline: .now() + config.termGrace) {
            if launch.process.isRunning { launch.process.terminate() }
        }
    }

    private func requestFinished() {
        guard pending.isEmpty else { return }
        if restartWhenIdle {
            restartWhenIdle = false
            return stop()
        }
        guard config.idle > 0 else { return }
        let timer = DispatchWorkItem { [self] in if pending.isEmpty { stop() } }
        idleTimer?.cancel()
        idleTimer = timer
        queue.asyncAfter(deadline: .now() + config.idle, execute: timer)
    }

    // MARK: - Messages

    private struct Incoming: Decodable {
        struct Failure: Decodable {
            let code: String
            let message: String
        }
        let id: JSONValue?
        let method: String?
        let params: JSONValue?
        let event: JSONValue?
        let error: Failure?
        let hasResult: Bool
        let result: JSONValue?

        private enum Keys: String, CodingKey { case id, method, params, event, error, result }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decodeIfPresent(JSONValue.self, forKey: .id)
            method = try c.decodeIfPresent(String.self, forKey: .method)
            params = try c.decodeIfPresent(JSONValue.self, forKey: .params)
            event = try c.decodeIfPresent(JSONValue.self, forKey: .event)
            error = try c.decodeIfPresent(Failure.self, forKey: .error)
            hasResult = c.contains(.result)
            result = try c.decodeIfPresent(JSONValue.self, forKey: .result)
        }
    }

    private func consume(_ data: Data, from launch: Launch) {
        guard launch === self.launch else { return }
        launch.buffer.append(data)
        while let newline = launch.buffer.firstIndex(of: 0x0A) {
            let line = Data(launch.buffer[..<newline])
            launch.buffer.removeSubrange(...newline)
            if !line.isEmpty { handle(line, from: launch) }
        }
    }

    private func handle(_ line: Data, from launch: Launch) {
        guard let message = try? JSONDecoder().decode(Incoming.self, from: line) else {
            return log("[\(config.appID.rawValue)] unreadable backend line")
        }
        launch.answered = true
        switch message.id {
        case .string(let shellID)?:
            guard let method = message.method else { return }
            let params = (try? JSONEncoder().encode(message.params ?? .null)) ?? Data("null".utf8)
            answer(shellID, shell(method, params), to: launch)
        case .number(let number)?:
            let id = Int(number)
            guard let reply = pending[id] else { return }
            if let event = message.event {
                reply(.event(encode(event)))
            } else if let error = message.error {
                pending[id] = nil
                reply(.failure(code: error.code, message: error.message))
                requestFinished()
            } else if message.hasResult {
                pending[id] = nil
                reply(.result(encode(message.result ?? .null)))
                requestFinished()
            }
        default:
            break
        }
    }

    private func answer(_ id: String, _ outcome: Result<Data, CallFailure>, to launch: Launch) {
        var line = Data(#"{"id":"#.utf8)
        line.append((try? JSONEncoder().encode(id)) ?? Data(#""""#.utf8))
        switch outcome {
        case .success(let result):
            line.append(Data(#","result":"#.utf8))
            line.append(result)
        case .failure(let failure):
            line.append(Data(#","error":"#.utf8))
            line.append((try? JSONEncoder().encode(["code": failure.code, "message": failure.message])) ?? Data())
        }
        line.append(Data("}\n".utf8))
        write(line, to: launch)
    }

    private func write(_ data: Data, to launch: Launch) {
        // A broken pipe means the process is gone; `exited` will fail the pending requests.
        try? launch.stdin.fileHandleForWriting.write(contentsOf: data)
    }

    private func encode(_ value: JSONValue) -> Data { (try? JSONEncoder().encode(value)) ?? Data("null".utf8) }
}
