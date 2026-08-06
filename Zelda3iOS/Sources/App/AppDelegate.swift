import UIKit
import Darwin

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    /// Same raw-POSIX pattern as the other checkpoint loggers in this app —
    /// deliberately not shared code, so this, the very first line of app
    /// code that runs at all, doesn't depend on anything else (Swift
    /// runtime metadata for a shared type, etc.) being ready yet.
    private static func earlyCheckpoint(_ stage: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let path = docs.appendingPathComponent("checkpoint.log").path
        let fd = path.withCString { open($0, O_WRONLY | O_CREAT | O_APPEND, 0o644) }
        guard fd >= 0 else { return }
        let line = stage + "\n"
        _ = line.withCString { write(fd, $0, strlen($0)) }
        close(fd)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        Self.earlyCheckpoint("AppDelegate: didFinishLaunching entry")

        // Install first, before anything else has a chance to crash.
        CrashLogger.install()
        Self.earlyCheckpoint("AppDelegate: CrashLogger installed")

        // Make sure the engine always has a writable, chdir-able Documents
        // directory before anything (including the ROM picker flow) touches
        // the filesystem.
        let cwdOk = ios_bridge_setup_documents_cwd()
        Self.earlyCheckpoint("AppDelegate: ios_bridge_setup_documents_cwd returned \(cwdOk)")

        let window = UIWindow(frame: UIScreen.main.bounds)
        Self.earlyCheckpoint("AppDelegate: UIWindow created, about to set rootViewController")
        window.rootViewController = RootViewController()
        Self.earlyCheckpoint("AppDelegate: rootViewController set, about to makeKeyAndVisible")
        window.makeKeyAndVisible()
        Self.earlyCheckpoint("AppDelegate: makeKeyAndVisible returned")
        self.window = window
        Self.earlyCheckpoint("AppDelegate: didFinishLaunching returning true")
        return true
    }
}
