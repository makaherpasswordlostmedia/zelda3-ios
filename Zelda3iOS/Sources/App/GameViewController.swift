import UIKit
import Darwin

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

    /// Appends a line to Documents/checkpoint.log directly from Swift, with
    /// no dependency on any C code having run yet. This exists to catch a
    /// crash between viewDidAppear firing and ios_bridge_run_game actually
    /// being entered — a window the C-side checkpoints (main.c,
    /// ios_bridge.m) can't cover since they only run once we're already
    /// inside C code.
    ///
    /// Uses raw POSIX open/write/close (via Darwin), not FileHandle.
    /// FileHandle's write(_:) is an Objective-C-style API that raises an
    /// uncaught NSException on failure (e.g. certain sandbox/permission
    /// edge cases) rather than throwing a catchable Swift Error — `try?`
    /// only catches Swift Error, so a FileHandle failure here could itself
    /// crash the process with no log, which would be self-defeating for a
    /// checkpoint logger. Raw POSIX calls have plain integer/errno error
    /// reporting with no exception machinery involved at all, matching
    /// exactly how the C-side IosCheckpoint()/EarlyCheckpoint() do this.
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

    override func viewDidLoad() {
        super.viewDidLoad()
        Self.earlyCheckpoint("GameViewController: viewDidLoad")
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
        Self.earlyCheckpoint("GameViewController: viewDidAppear")
        guard !didLaunch else { return }
        didLaunch = true
        registerWindowReadyCallback()
        registerFatalErrorCallback()
        Self.earlyCheckpoint("GameViewController: callbacks registered, calling launchEngine")
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
            //
            // This used to busy-poll with RunLoop.current.run(until:) in a
            // loop, on the theory that the C side called this callback via
            // dispatch_sync, so the engine's background thread would block
            // until attach finished, and pumping the run loop here would
            // safely let other pending main-thread work (like the rest of
            // SDL_CreateWindow's continuation) complete in the meantime.
            //
            // That combination was unsafe in practice: a RunLoop.current
            // .run() called from *inside* a block GCD is currently
            // executing on the main thread doesn't reliably pump the same
            // sources that other queued main-thread work depends on — and
            // that other work could itself be blocked waiting for the very
            // dispatch_sync this call was nested inside of. The two threads
            // could end up circularly waiting on each other, which iOS's
            // launch watchdog resolves by SIGKILLing the process outright —
            // before any crash handler, checkpoint write, or alert ever
            // gets a chance to run. That produced exactly the "controls
            // flash for an instant, then the app just vanishes, nothing in
            // any log" symptom.
            //
            // Fix: the C side now calls this via dispatch_async and waits
            // on a semaphore instead of holding the main queue hostage (see
            // ios_bridge_notify_window_created in ios_bridge.m), so it's
            // safe to schedule an ordinary async retry here instead of
            // nesting a run-loop poll inside someone else's GCD block.
            retryAttachControlsOverlay(to: sdlWindow, attemptsRemaining: 100)
            return
        }

        attachOverlay(to: rootView)
    }

    /// Retries attaching the controls overlay once SDL's root view exists,
    /// using a plain async re-dispatch (not a nested RunLoop poll — see the
    /// comment in attachControlsOverlay above for why that was unsafe).
    /// Each attempt is scheduled 10ms apart, giving up after ~1s (100
    /// attempts) if SDL's root view never shows up, same bound as before.
    private func retryAttachControlsOverlay(to sdlWindow: UIWindow, attemptsRemaining: Int) {
        guard controlsOverlay == nil else { return } // already attached
        guard let rootView = sdlWindow.rootViewController?.view ?? sdlWindow.subviews.first else {
            guard attemptsRemaining > 0 else {
                // Gave up — proceed without the overlay rather than retry
                // forever. The game will still run; touch controls just
                // won't appear.
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.retryAttachControlsOverlay(to: sdlWindow, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }
        attachOverlay(to: rootView)
    }

    private func attachOverlay(to rootView: UIView) {
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
        // The engine's asset-extraction pipeline (Python, in assets/) is a
        // build-time / desktop tool, not something we run on-device today.
        // See README_BUILD.md "Step 4 — asset extraction gap": bundle a
        // precomputed zelda3_assets.bps in Resources/ and copy it into
        // Documents before this call; the engine's existing LoadAssets()
        // path in main.c will patch the user's own ROM into
        // zelda3_assets.dat on first run.
        Self.earlyCheckpoint("GameViewController: launchEngine, before background dispatch")
        DispatchQueue.global(qos: .userInitiated).async {
            Self.earlyCheckpoint("GameViewController: on background thread, before ios_bridge_run_game")
            // SDL_main (src/main.c) does `argc--, argv++` right at the
            // start — the standard "skip argv[0] (program name)" idiom. It
            // expects argv[0] to be the program name and any real
            // arguments to start at argv[1]. Passing argc=1 with only one
            // element made argc become 0 after that decrement, which then
            // failed main.c's `if (argc >= 1) LoadRom(argv[0])` guard — the
            // ROM was silently never loaded. Pass a dummy second argument
            // so argc=2, and argv+1 still points at a valid (empty) string
            // after the shift.
            let argv0 = strdup("zelda3")
            let argv1 = strdup("")
            var argvArray: [UnsafeMutablePointer<CChar>?] = [argv0, argv1, nil]
            _ = argvArray.withUnsafeMutableBufferPointer { buffer -> Int32 in
                ios_bridge_run_game(2, buffer.baseAddress)
            }
            free(argv0)
            free(argv1)
        }
    }
}
