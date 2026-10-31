import Foundation
import JavaScriptCore
import ShellCore

/// What the shell offers a running app. Closures run on the JS queue and must not block it.
public struct HostServices: Sendable {
    public var call:
        @Sendable (_ id: Int, _ method: String, _ params: Data, _ reply: @escaping @Sendable (CallReply) -> Void) ->
            Void
    public var cancel: @Sendable (_ id: Int) -> Void
    public var setting: @Sendable (_ key: String) -> String?
    public var setSetting: @Sendable (_ key: String, _ value: String) -> Void
    public var log: @Sendable (_ line: String) -> Void
}

/// One app's `JSContext` and its private serial queue.
///
/// Thread boundary: `JSContext` / `JSValue` are created and used only on `queue`. What leaves is
/// `Sendable`: decoded `UIPatch` values through `patches`, strings through `services`.
/// `@unchecked Sendable` rests on that confinement.
public final class JSHost: @unchecked Sendable {
    public let patches: AsyncStream<UIPatch>

    private let queue: DispatchQueue
    private let services: HostServices
    private let continuation: AsyncStream<UIPatch>.Continuation
    private var context: JSContext?
    private var wisp: JSValue?
    private var calls: [Int: (event: JSValue, done: JSValue)] = [:]
    private var timers: [Int: (fn: JSValue, item: DispatchWorkItem)] = [:]
    private var nextTimerID = 0
    private var nextCallID: Int
    private var lastRev: Int

    /// `startRev` and `firstCallID` carry over from a previous host on hot reload, so the shell's tree
    /// accepts our patches and the backend never sees a reused request id.
    public init(appID: AppID, script: String, startRev: Int, firstCallID: Int, services: HostServices) {
        queue = DispatchQueue(label: "wisp.js." + appID.rawValue)
        self.services = services
        lastRev = startRev
        nextCallID = firstCallID
        (patches, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        queue.async { [self] in load(script) }
    }

    public func dispatch(_ handler: String, value: String?) {
        queue.async { [self] in
            guard let wisp, let context else { return }
            let argument = value.map { JSValue(object: $0, in: context) } ?? JSValue(undefinedIn: context)
            wisp.invokeMethod("dispatch", withArguments: [handler, argument as Any])
        }
    }

    public func lifecycle(_ kind: String) {
        queue.async { [self] in _ = wisp?.invokeMethod("lifecycle", withArguments: [kind]) }
    }

    /// Releases the context. Open backend calls are cancelled; their late replies are ignored.
    /// Returns the next unused call id.
    @discardableResult
    public func shutdown() -> Int {
        queue.sync {
            for id in calls.keys { services.cancel(id) }
            for timer in timers.values { timer.item.cancel() }
            calls = [:]
            timers = [:]
            wisp = nil
            context = nil
            continuation.finish()
            return nextCallID
        }
    }

    public var revision: Int { queue.sync { lastRev } }

    // MARK: - Context setup (on `queue`)

    private func load(_ script: String) {
        let context = JSContext()!
        self.context = context
        context.exceptionHandler = { [services] _, exception in
            services.log("js error: \(exception?.toString() ?? "unknown")")
        }
        let wisp = JSValue(newObjectIn: context)!
        wisp.setValue(lastRev, forProperty: "rev")
        self.wisp = wisp
        context.setObject(wisp, forKeyedSubscript: "__wisp" as NSString)

        let commit: @convention(block) (String) -> Void = { [weak self] json in self?.commit(json) }
        let call: @convention(block) (String, String, JSValue, JSValue) -> JSValue = {
            [weak self] method, params, event, done in
            self?.startCall(method, params, event, done) ?? JSValue(undefinedIn: JSContext.current())
        }
        let setting: @convention(block) (String) -> Any = { [services] key in services.setting(key) ?? NSNull() }
        let setSetting: @convention(block) (String, String) -> Void = { [services] key, value in
            services.setSetting(key, value)
        }
        wisp.setObject(commit, forKeyedSubscript: "commit" as NSString)
        wisp.setObject(call, forKeyedSubscript: "call" as NSString)
        wisp.setObject(setting, forKeyedSubscript: "setting" as NSString)
        wisp.setObject(setSetting, forKeyedSubscript: "setSetting" as NSString)

        installTimers(in: context)
        installConsole(in: context)
        context.evaluateScript(script)
    }

    private func installTimers(in context: JSContext) {
        let set: @convention(block) (JSValue, Double) -> Int = { [weak self] fn, delay in
            self?.setTimeout(fn, delay) ?? 0
        }
        let clear: @convention(block) (JSValue) -> Void = { [weak self] id in
            guard let self, id.isNumber else { return }
            timers.removeValue(forKey: Int(id.toInt32()))?.item.cancel()
        }
        context.setObject(set, forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(clear, forKeyedSubscript: "clearTimeout" as NSString)
    }

    private func installConsole(in context: JSContext) {
        let console = JSValue(newObjectIn: context)!
        let write: @convention(block) () -> Void = { [services] in
            let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
            services.log(arguments.map { $0.toString() ?? "" }.joined(separator: " "))
        }
        for level in ["log", "info", "warn", "error", "debug"] {
            console.setObject(write, forKeyedSubscript: level as NSString)
        }
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    // MARK: - Bridge callbacks (on `queue`, invoked from JS)

    private func commit(_ json: String) {
        guard let patch = try? JSONDecoder().decode(UIPatch.self, from: Data(json.utf8)) else {
            return services.log("dropped malformed patch")
        }
        lastRev = max(lastRev, patch.rev)
        continuation.yield(patch)
    }

    private func setTimeout(_ fn: JSValue, _ delay: Double) -> Int {
        nextTimerID += 1
        let id = nextTimerID
        let item = DispatchWorkItem { [weak self] in
            guard let self, let timer = timers.removeValue(forKey: id) else { return }
            timer.fn.call(withArguments: [])
        }
        timers[id] = (fn, item)
        queue.asyncAfter(deadline: .now() + max(delay, 0) / 1000, execute: item)
        return id
    }

    private func startCall(_ method: String, _ params: String, _ event: JSValue, _ done: JSValue) -> JSValue {
        let id = nextCallID
        nextCallID += 1
        calls[id] = (event, done)
        services.call(id, method, Data(params.utf8)) { [weak self] reply in
            self?.queue.async { self?.deliver(reply, to: id) }
        }
        let cancel: @convention(block) () -> Void = { [weak self] in
            if self?.calls[id] != nil { self?.services.cancel(id) }
        }
        return JSValue(object: cancel, in: JSContext.current())
    }

    private func deliver(_ reply: CallReply, to id: Int) {
        guard let call = calls[id] else { return }
        switch reply {
        case .event(let data):
            call.event.call(withArguments: [String(decoding: data, as: UTF8.self)])
        case .result(let data):
            calls[id] = nil
            call.done.call(withArguments: [String(decoding: data, as: UTF8.self), NSNull()])
        case .failure(let code, let message):
            calls[id] = nil
            let error = (try? JSONEncoder().encode(["code": code, "message": message])) ?? Data()
            call.done.call(withArguments: [NSNull(), String(decoding: error, as: UTF8.self)])
        }
    }
}
