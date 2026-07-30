import Foundation

/// Minimal on-device crash logger.
///
/// We have no Mac/Xcode/Console.app available to pull crash logs from, and
/// Settings > Privacy > Analytics > Analytics Data hasn't shown anything for
/// the crashes we're chasing (they may be happening early/violently enough —
/// e.g. a raw SIGSEGV/SIGBUS from something like a threading race — that iOS
/// isn't always symbolicating/surfacing a report there, or it's filed under
/// a name/timing we haven't found yet).
///
/// This installs handlers for both:
///  - Objective-C uncaught exceptions (NSSetUncaughtExceptionHandler) — e.g.
///    NSInternalInconsistencyException, like the Auto Layout thread-safety
///    one we already saw once.
///  - Fatal POSIX signals (SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE,
///    SIGTRAP) — covers raw crashes (null deref, bad access, illegal
///    instruction, stack overflow, etc.) that never go through Objective-C
///    exception machinery at all, which is most likely what's actually
///    killing the app given no exception/alert has been showing.
///
/// Both write a plain-text file to Documents/crash_log.txt (readable via the
/// Files app, since Info.plist already has UIFileSharingEnabled +
/// LSSupportsOpeningDocumentsInPlace turned on for ROM import) *before*
/// letting the crash actually terminate the process. RootViewController
/// checks for this file on next launch and, if present, shows its contents
/// in an alert immediately, then deletes it.
enum CrashLogger {

    private static var crashLogURL: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("crash_log.txt")
    }

    /// Call once, as early as possible in application(_:didFinishLaunchingWithOptions:).
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let details = """
            Uncaught NSException
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "(no reason)")
            Call stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            write(details)
        }

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        for sig in signals {
            signal(sig, { signalValue in
                let name = CrashLogger.signalName(signalValue)
                // async-signal-safety is technically a concern here (file
                // I/O, string formatting, and Swift's runtime aren't
                // guaranteed async-signal-safe), but on iOS in practice
                // this best-effort approach is routinely used for exactly
                // this purpose and is far better than the alternative of
                // getting no information at all. We keep the handler as
                // small and fast as we reasonably can.
                var frames = [String]()
                let maxFrames = 64
                var addrs = [UnsafeMutableRawPointer?](repeating: nil, count: maxFrames)
                let count = addrs.withUnsafeMutableBufferPointer { buf -> Int32 in
                    Int32(backtrace(buf.baseAddress, Int32(maxFrames)))
                }
                if let symbols = backtrace_symbols(&addrs, count) {
                    for i in 0..<Int(count) {
                        if let s = symbols[i] {
                            frames.append(String(cString: s))
                        }
                    }
                    free(symbols)
                }
                let details = """
                Fatal signal: \(name) (\(signalValue))
                Call stack:
                \(frames.joined(separator: "\n"))
                """
                CrashLogger.write(details)
                // Restore default handling and re-raise so the process
                // still actually terminates the way it normally would.
                signal(signalValue, SIG_DFL)
                raise(signalValue)
            })
        }
    }

    /// Checks for a crash log left by a previous launch. Returns its
    /// contents (and deletes the file) if present, so the caller can show
    /// it, or nil if the app didn't crash last time.
    static func consumePendingCrashLog() -> String? {
        guard let url = crashLogURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        try? FileManager.default.removeItem(at: url)
        return text
    }

    private static func write(_ text: String) {
        guard let url = crashLogURL else { return }
        let stamped = "Crash at \(Date())\n\(text)\n"
        // Overwrite any previous log; we only need the most recent crash.
        try? stamped.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS: return "SIGBUS"
        case SIGILL: return "SIGILL"
        case SIGFPE: return "SIGFPE"
        case SIGTRAP: return "SIGTRAP"
        default: return "signal \(sig)"
        }
    }
}
