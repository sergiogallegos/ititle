import AppKit
import ApplicationServices
import ITileCore

/// Constructed and used exclusively on the worker thread, including teardown.
/// The test adapter can block reads without touching real applications or AX permission.
protocol ProbeBackend: AnyObject {
    func inspect(epoch: UInt64, cancelled: () -> Bool) -> String
    func tearDown()
    func invalidateIdentity()
}

/// Only the mailbox and run-loop wakeup handles cross threads. AX objects live in run().
public final class WindowProbe: @unchecked Sendable {
    public let token: AppToken
    private let lock = NSLock()
    private var pending: (epoch: UInt64, completion: @Sendable (String) -> Void)?
    private var busy = false
    private var stopped = false
    private var loop: CFRunLoop?
    private var source: CFRunLoopSource?

    private let makeBackend: @Sendable () -> any ProbeBackend

    public convenience init(token: AppToken, diagnosticNotification: (@Sendable (Double) -> Void)? = nil) {
        self.init(token: token, makeBackend: { ProbeState(token: token, diagnosticNotification: diagnosticNotification) })
    }

    init(token: AppToken, makeBackend: @escaping @Sendable () -> any ProbeBackend) {
        self.token = token
        self.makeBackend = makeBackend
        Thread.detachNewThread { [self] in run() }
    }

    /// One admitted request, no unbounded callback/task queue.
    public func inspect(environmentEpoch: UInt64, completion: @escaping @Sendable (String) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, !busy else { return false }
        busy = true; pending = (environmentEpoch, completion)
        wake()
        return true
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true; pending = nil
        wake()
    }

    private func wake() {
        if let source { CFRunLoopSourceSignal(source) }
        if let loop { CFRunLoopWakeUp(loop) }
    }

    private var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func run() {
        var context = CFRunLoopSourceContext()
        context.perform = { _ in }
        let wakeSource = CFRunLoopSourceCreate(nil, 0, &context)!
        let workerLoop = CFRunLoopGetCurrent()!
        CFRunLoopAddSource(workerLoop, wakeSource, .defaultMode)
        lock.lock()
        loop = workerLoop; source = wakeSource
        lock.unlock()
        let state = makeBackend()
        while !cancelled {
            lock.lock()
            let work = pending; pending = nil
            lock.unlock()
            if let work {
                // Process destruction notifications before correlating the next explicit snapshot.
                // A continuous notification stream must not starve inspection or stop.
                var drained = false
                for _ in 0..<64 {
                    if cancelled || CFRunLoopRunInMode(.defaultMode, 0, true) != .handledSource {
                        drained = true
                        break
                    }
                }
                if cancelled { break }
                if !drained { state.invalidateIdentity() }
                let report = autoreleasepool { state.inspect(epoch: work.epoch, cancelled: { self.cancelled }) }
                lock.lock()
                let deliver = !stopped
                busy = false
                lock.unlock()
                if deliver { work.completion(report) }
            } else {
                CFRunLoopRunInMode(.defaultMode, 3600, true)
            }
        }
        state.tearDown()
        CFRunLoopRemoveSource(workerLoop, wakeSource, .defaultMode)
        lock.lock(); loop = nil; source = nil; lock.unlock()
    }
}

/// Created, accessed, and destroyed solely on the owning dedicated Thread.
private final class ProbeState: ProbeBackend {
    let token: AppToken
    var registry: ProbeRegistry
    var elements: [(id: Int, element: AXUIElement)] = []
    var nextIdentity = 0
    var observer: AXObserver?
    var destructionObserved = false
    var observerError: AXError = .success
    var diagnosticElements: [AXUIElement] = []
    var expiringIdentities: Set<Int> = []
    var environmentEpoch: UInt64?
    let app: AXUIElement
    // P3 opt-in only: arrival time of a fixture notification; no title value is read.
    let diagnosticNotification: (@Sendable (Double) -> Void)?

    init(token: AppToken, diagnosticNotification: (@Sendable (Double) -> Void)?) {
        self.diagnosticNotification = diagnosticNotification
        self.token = token
        registry = ProbeRegistry(app: token)
        app = AXUIElementCreateApplication(token.pid)
        let error = AXObserverCreate(token.pid, { _, _, notification, context in
            guard let context else { return }
            let state = Unmanaged<ProbeState>.fromOpaque(context).takeUnretainedValue()
            if notification as String == kAXUIElementDestroyedNotification {
                state.destructionObserved = true
            } else if notification as String == kAXTitleChangedNotification {
                state.diagnosticNotification?(ProcessInfo.processInfo.systemUptime)
            }
        }, &observer)
        if error == .success, let observer {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        } else { observerError = error; observer = nil }
    }

    func tearDown() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        diagnosticElements.removeAll()
        elements.removeAll()
    }

    func invalidateIdentity() { destructionObserved = true }

    func clearIdentity() {
        if let observer {
            for entry in elements {
                AXObserverRemoveNotification(observer, entry.element, kAXUIElementDestroyedNotification as CFString)
            }
        }
        elements.removeAll(); registry.invalidate(); expiringIdentities.removeAll()
    }

    func inspect(epoch: UInt64, cancelled: () -> Bool) -> String {
        if environmentEpoch != epoch { clearIdentity(); environmentEpoch = epoch }
        let start = ProcessInfo.processInfo.systemUptime
        guard AXIsProcessTrusted() else {
            clearIdentity()
            return "Accessibility permission required. No windows inspected."
        }
        if destructionObserved || observer == nil { clearIdentity() }
        // An unsupported element must not invalidate observable siblings. Keep the
        // serial allocator monotonic so an expiring identity never recovers its token.
        registry.invalidate(expiringIdentities)
        expiringIdentities.removeAll()
        destructionObserved = false
        guard AXUIElementSetMessagingTimeout(app, 0.2) == .success else {
            clearIdentity(); return "Unable to configure application AX timeout; inspection skipped."
        }
        var raw: CFTypeRef?
        let ipcStart = ProcessInfo.processInfo.systemUptime
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
        let ipcSeconds = ProcessInfo.processInfo.systemUptime - ipcStart
        let ipcLine = String(format: "AXWindows IPC: %.6f s; AX result: %d; start=%.6f; end=%.6f", ipcSeconds, error.rawValue, ipcStart, ipcStart + ipcSeconds)
        guard error == .success, let values = raw as? [AXUIElement] else {
            clearIdentity(); return "Window enumeration unavailable: AX error \(error.rawValue). Identity invalidated.\n\(ipcLine)"
        }
        guard values.count <= 64 else {
            clearIdentity(); return "Window limit (64) exceeded; snapshot excluded."
        }
        // Duplicate equal handles are ambiguous, so exclude the entire snapshot.
        for i in values.indices {
            if values.prefix(i).contains(where: { CFEqual($0, values[i]) }) {
                clearIdentity(); return "Duplicate equal AX handles; ambiguous snapshot excluded."
            }
        }
        let previous = elements
        elements = values.map { element in
            if let old = previous.first(where: { CFEqual($0.element, element) }) { return (old.id, element) }
            nextIdentity += 1
            return (nextIdentity, element)
        }
        if let observer {
            for old in previous where !elements.contains(where: { $0.id == old.id }) {
                AXObserverRemoveNotification(observer, old.element, kAXUIElementDestroyedNotification as CFString)
            }
        }
        let tokens = registry.reconcile(elements.map(\.id))
        var lines = ["Read-only snapshot: app-\(token.generation)", ipcLine,
                     "Visibility/eligibility: unproven; no enrollment or window mutation.",
                     "AX timeout: 0.2 s per actual handle (experimental); scan budget: 5 s."]
        for (index, entry) in elements.enumerated() {
            guard !cancelled(), ProcessInfo.processInfo.systemUptime - start < 5 else {
                clearIdentity()
                lines.append("Cancelled or scan budget reached; partial snapshot, identity invalidated.")
                break
            }
            let window = entry.element
            guard AXUIElementSetMessagingTimeout(window, 0.2) == .success else {
                expiringIdentities.insert(entry.id)
                lines.append("\(tokens[index]): timeout setup failed; excluded; token expires.")
                continue
            }
            let observation: String
            if let observer {
                let result = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString,
                                                       Unmanaged.passUnretained(self).toOpaque())
                if result == .success || result == .notificationAlreadyRegistered {
                    observation = "registered; continuity experimental"
                } else {
                    expiringIdentities.insert(entry.id)
                    observation = "unavailable(AX \(result.rawValue)); token expires before next snapshot"
                }
            } else {
                expiringIdentities.insert(entry.id)
                observation = "observer unavailable(AX \(observerError.rawValue)); token expires before next snapshot"
            }
            if let observer, diagnosticNotification != nil {
                if diagnosticElements.contains(where: { CFEqual($0, window) }) {
                    lines.append("  P3 notification-registration: retained")
                } else if diagnosticElements.count < 64 {
                    let result = AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString,
                                                           Unmanaged.passUnretained(self).toOpaque())
                    if result == .success || result == .notificationAlreadyRegistered {
                        diagnosticElements.append(window)
                    }
                    lines.append("  P3 notification-registration: AX \(result.rawValue)")
                } else {
                    lines.append("  P3 notification-registration: diagnostic handle limit reached")
                }
            }
            let role = describe(string(window, kAXRoleAttribute))
            let subrole = describe(string(window, kAXSubroleAttribute))
            let minimized = describe(boolean(window, kAXMinimizedAttribute))
            let fullscreen = describe(boolean(window, "AXFullScreen"))
            lines.append("\(tokens[index]): role=\(role), subrole=\(subrole)")
            lines.append("  destruction-notification=\(observation)")
            lines.append("  minimized=\(minimized), fullscreen=\(fullscreen)")
            lines.append("  modal=\(describe(boolean(window, kAXModalAttribute)))")
            lines.append("  \(directSheets(window, deadline: start + 5, cancelled: cancelled))")
            lines.append("  position=\(position(window)); size=\(size(window))")
            lines.append("  position-settable=\(describe(settable(window, kAXPositionAttribute))); size-settable=\(describe(settable(window, kAXSizeAttribute)))")
        }
        lines.append("Identity continuity: per-element notification status above; destruction or environment changes invalidate all tokens.")
        lines.append("On-screen CG bounds for this PID (evidence only; no AX identity mapping):")
        if let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let matches = info.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == token.pid }
            for item in matches.prefix(64) {
                if let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                   let rect = CGRect(dictionaryRepresentation: bounds) {
                    lines.append("  layer=\((item[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1), bounds=\(rect)")
                } else { lines.append("  bounds unavailable") }
            }
            lines.append("  entries=\(matches.count); fully occluded/other desktops remain unproven.")
        } else { lines.append("  metadata unavailable") }
        lines.append(String(format: "Snapshot duration: %.3f s", ProcessInfo.processInfo.systemUptime - start))
        return lines.joined(separator: "\n")
    }
}

private func read<T: Sendable>(_ window: AXUIElement, _ key: String,
                               convert: (CFTypeRef) -> T?) -> ProbeRead<T> {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(window, key as CFString, &value)
    guard error == .success else { return .unavailable(error.rawValue) }
    guard let value, let converted = convert(value) else { return .invalidType }
    return .value(converted)
}
private func string(_ window: AXUIElement, _ key: String) -> ProbeRead<String> {
    read(window, key) { value in
        // Only fixed role/subrole vocabulary is emitted; custom strings could contain private data.
        guard let text = value as? String else { return nil }
        let allowed = ["AXWindow", "AXStandardWindow", "AXDialog", "AXSystemDialog", "AXSheet", "AXFloatingWindow", "AXUnknown"]
        return allowed.contains(text) ? text : "other-role"
    }
}
private func boolean(_ window: AXUIElement, _ key: String) -> ProbeRead<Bool> {
    read(window, key) { value in
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFEqual(value, kCFBooleanTrue)
    }
}
private func settable(_ window: AXUIElement, _ key: String) -> ProbeRead<Bool> {
    var result: DarwinBoolean = false
    let error = AXUIElementIsAttributeSettable(window, key as CFString, &result)
    return error == .success ? .value(result.boolValue) : .unavailable(error.rawValue)
}
private func describe<T>(_ result: ProbeRead<T>) -> String {
    switch result {
    case .value(let value): return "\(value)"
    case .unavailable(let error): return "unknown(AX \(error))"
    case .invalidType: return "unknown(type)"
    }
}
private func position(_ window: AXUIElement) -> String {
    describe(read(window, kAXPositionAttribute) { value -> String? in
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(ax) == .cgPoint, AXValueGetValue(ax, .cgPoint, &point),
              point.x.isFinite, point.y.isFinite else { return nil }
        return "(\(point.x), \(point.y))"
    })
}
private func size(_ window: AXUIElement) -> String {
    describe(read(window, kAXSizeAttribute) { value -> String? in
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(ax) == .cgSize, AXValueGetValue(ax, .cgSize, &size),
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return "(\(size.width), \(size.height))"
    })
}


/// Only first-order child roles are read. Never descend into a chooser's contents.
private func directSheets(_ window: AXUIElement, deadline: Double, cancelled: () -> Bool) -> String {
    var count: CFIndex = 0
    let countError = AXUIElementGetAttributeValueCount(window, kAXChildrenAttribute as CFString, &count)
    guard countError == .success else {
        return "direct-child-sheets=unknown(AX \(countError.rawValue))"
    }
    guard count >= 0 else { return "direct-child-sheets=unknown(count)" }
    if count == 0 { return DirectSheetSummary(total: 0, roles: []).description }
    guard !cancelled(), ProcessInfo.processInfo.systemUptime < deadline else {
        return "direct-child-sheets=unknown(cancelled or scan budget)"
    }
    var raw: CFArray?
    let error = AXUIElementCopyAttributeValues(window, kAXChildrenAttribute as CFString, 0, min(count, 16), &raw)
    guard error == .success, let children = raw as? [AXUIElement] else {
        return "direct-child-sheets=unknown(AX \(error.rawValue) or type)"
    }
    var roles: [ProbeRead<String>] = []
    for child in children.prefix(16) {
        guard !cancelled(), ProcessInfo.processInfo.systemUptime < deadline else { break }
        let timeout = AXUIElementSetMessagingTimeout(child, 0.2)
        guard timeout == .success else { roles.append(.unavailable(timeout.rawValue)); continue }
        roles.append(string(child, kAXRoleAttribute))
    }
    return DirectSheetSummary(total: count, roles: roles).description
}

/// Pure summary: unknown/truncated child reads must never claim an exhaustive zero.
struct DirectSheetSummary {
    let total: Int
    let roles: [ProbeRead<String>]

    var observedSheets: Int {
        roles.filter { if case .value("AXSheet") = $0 { return true }; return false }.count
    }

    var complete: Bool {
        total >= 0 && roles.count == total && roles.allSatisfy {
            if case .value = $0 { return true }; return false
        }
    }

    var description: String {
        "direct-child-sheets=\(observedSheets) observed; child-role-scan=\(complete ? "complete" : "incomplete"), \(roles.count)/\(total); nested sheets not checked"
    }
}
