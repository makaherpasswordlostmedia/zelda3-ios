import UIKit

/// Hosts the running game. Responsibilities:
///  1. Register a callback (via ios_bridge_set_window_ready_callback) so we
///     find out the moment SDL creates its real UIWindow.
///  2. Hand off to SDL_main via ios_bridge_run_game (on a background
///     thread — SDL's iOS run loop blocks until the game quits).
///  3. Once notified that SDL's window exists, attach TouchControlsView as
///     a subview of *that* window's root view, so it reliably renders on
///     top of the SDL content regardless of window levels or z-ordering.
final class GameViewController: UIViewController {

    private let statusLabel = UILabel()
    private var didLaunch = false
    private var controlsOverlay: TouchControlsView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        statusLabel.text = "Loading…"
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didLaunch else { return }
        didLaunch = true
        registerWindowReadyCallback()
        registerFatalErrorCallback()
        launchEngine()
    }

    // MARK: - Fatal error reporting

    /// Without this, a fatal error inside the engine (e.g. a missing
    /// zelda3_assets.bps, or a ROM that doesn't match the expected version)
    /// calls Die() -> exit(1) on the background thread launchEngine() runs
    /// on, which can leave the app looking stuck on "Loading…" forever
    /// instead of showing anything useful. This surfaces the real message.
    private func registerFatalErrorCallback() {
        let unmanagedSelf = Unmanaged.passRetained(self).toOpaque()
        ios_bridge_set_fatal_error_callback({ messagePtr, context in
            // Called on the main thread (see ios_bridge.m) — safe to touch
            // UIKit directly here.
            guard let context else { return }
            let vc = Unmanaged<GameViewController>.fromOpaque(context).takeUnretainedValue()
            let message = messagePtr.map { String(cString: $0) } ?? "Unknown error"
            vc.showFatalError(message)
        }, unmanagedSelf)
    }

    private func showFatalError(_ message: String) {
        statusLabel.text = "Error"
        let alert = UIAlertController(
            title: "Couldn't start the game",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - SDL window hookup

    /// Passes a retained self-reference through the C callback's `context`
    /// pointer, so the free C-style callback below can get back to `self`
    /// without needing a global/static Swift variable.
    private func registerWindowReadyCallback() {
        let unmanagedSelf = Unmanaged.passRetained(self).toOpaque()
        ios_bridge_set_window_ready_callback({ uiWindowRef, context in
            // Called on the main thread (see ios_bridge.m) — safe to touch
            // UIKit directly here.
            guard let context, let uiWindowRef else { return }
            let vc = Unmanaged<GameViewController>.fromOpaque(context).takeUnretainedValue()
            let window = Unmanaged<UIWindow>.fromOpaque(uiWindowRef).takeRetainedValue()
            vc.attachControlsOverlay(to: window)
        }, unmanagedSelf)
    }

    private func attachControlsOverlay(to sdlWindow: UIWindow) {
        guard controlsOverlay == nil else { return } // already attached

        guard let rootView = sdlWindow.rootViewController?.view ?? sdlWindow.subviews.first else {
            // SDL's window exists but hasn't got a root view yet — retry
            // shortly. Can happen if we're notified a hair before SDL
            // finishes setting up its own root view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.attachControlsOverlay(to: sdlWindow)
            }
            return
        }

        statusLabel.removeFromSuperview()

        let overlay = TouchControlsView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        rootView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: rootView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
        ])
        // Belt-and-suspenders: if some other SDL-owned subview gets added
        // to rootView after this and would otherwise occlude us, keep the
        // overlay topmost in the subview stack.
        rootView.bringSubviewToFront(overlay)

        controlsOverlay = overlay
    }

    // MARK: - Engine launch

    private func launchEngine() {
        // DIAGNOSTIC (temporary): print progress markers directly onto
        // statusLabel, visible without a cable/Xcode console, so we can see
        // exactly how far execution gets before it appears to hang.
        statusLabel.text = "Loading… [1: launchEngine called]"

        // DIAGNOSTIC: SDL2's iOS video backend creates/owns a UIWindow via
        // UIKit APIs inside SDL_Init/SDL_CreateWindow, which (like all UIKit
        // API) must run on the main thread. Running SDL_main on a
        // background queue — as this used to do — can leave SDL stuck
        // indefinitely inside SDL_Init/SDL_CreateWindow with no error and
        // no crash, which looks exactly like an infinite "Loading…" screen.
        // This synchronous, main-thread call is a deliberate but temporary
        // fix to confirm that diagnosis: the engine's `while(running)` game
        // loop (src/main.c) will block the main thread/UIKit run loop for
        // as long as the game runs, which is not viable long-term (no touch
        // events, no view updates, watchdog-terminated by the OS) — but if
        // this makes the game actually start, it confirms the thread was
        // the problem, and the real fix is restructuring main.c's loop
        // around a CADisplayLink/timer-driven single-frame-step function
        // instead of calling SDL_main's blocking loop directly.
        let argv0 = strdup("zelda3")
        var argvArray: [UnsafeMutablePointer<CChar>?] = [argv0, nil]
        statusLabel.text = "Loading… [2: about to call ios_bridge_run_game]"
        _ = argvArray.withUnsafeMutableBufferPointer { buffer -> Int32 in
            ios_bridge_run_game(1, buffer.baseAddress)
        }
        free(argv0)
        // If we ever get here, ios_bridge_run_game (SDL_main) returned —
        // meaning the game loop actually exited rather than hanging.
        statusLabel.text = "Loading… [3: ios_bridge_run_game returned!]"
    }
}
