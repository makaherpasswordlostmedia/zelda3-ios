import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Install first, before anything else has a chance to crash.
        CrashLogger.install()

        // Make sure the engine always has a writable, chdir-able Documents
        // directory before anything (including the ROM picker flow) touches
        // the filesystem.
        _ = ios_bridge_setup_documents_cwd()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
