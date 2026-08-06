import UIKit
import Darwin

/// Decides, at launch and whenever we return to the foreground after a
/// picker flow, whether to show the "pick a ROM" screen or hand off to the
/// SDL2 game engine.
final class RootViewController: UIViewController {

    /// Raw POSIX checkpoint write, duplicated here (rather than sharing code
    /// with GameViewController) so this — the very first UIKit code that
    /// runs after AppDelegate — can log before doing anything else at all,
    /// including before it reads and deletes any previous checkpoint.log.
    /// Uses open/write/close directly (not FileHandle) because FileHandle's
    /// write(_:) can raise an uncaught NSException on failure, which `try?`
    /// can't catch — see the matching comment in GameViewController.swift.
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
        // IMPORTANT: consume (read + delete) the *previous* run's
        // checkpoint.log before writing anything to it ourselves. If we
        // wrote our own "viewDidLoad start" checkpoint first, it would be
        // sitting in the same file consumePendingCheckpointLog() reads
        // right below, mixing this run's just-started trail in with
        // whatever the last (crashed) run left behind and making the alert
        // confusing to read.
        let swiftCrashLog = CrashLogger.consumePendingCrashLog()
        let checkpointLog = Self.consumePendingCheckpointLog()

        // Now it's safe to start this run's own trail.
        Self.earlyCheckpoint("RootViewController: viewDidLoad start")
        view.backgroundColor = .black
        Self.earlyCheckpoint("RootViewController: after consuming previous logs, backgroundColor set. swiftCrashLog=\(swiftCrashLog != nil) checkpointLog=\(checkpointLog != nil)")

        if swiftCrashLog != nil || checkpointLog != nil {
            var combined = ""
            if let checkpointLog {
                combined += "=== C engine checkpoints (last run) ===\n\(checkpointLog)\n\n"
            }
            if let swiftCrashLog {
                combined += "=== Swift crash/exception log ===\n\(swiftCrashLog)"
            }
            // IMPORTANT: don't call present(_:animated:) synchronously from
            // viewDidLoad. At this point in the launch sequence (called
            // from AppDelegate during window.makeKeyAndVisible(), before
            // didFinishLaunchingWithOptions has returned) UIKit hasn't
            // necessarily finished wiring this view controller into the
            // window hierarchy well enough to actually present a modal —
            // present() can silently no-op instead of either showing the
            // alert or erroring. The result: view.backgroundColor = .black
            // (set above) is the last thing that visibly happens, the
            // alert never appears, showAppropriateScreen() never runs, and
            // the app just sits on a black screen indefinitely — not a
            // crash, so nothing further ever gets appended to
            // checkpoint.log either. Deferring to the next run loop tick
            // (DispatchQueue.main.async) ensures the window/view hierarchy
            // is fully settled before we try to present anything.
            DispatchQueue.main.async { [weak self] in
                self?.showCrashLog(combined)
            }
            return
        }

        showAppropriateScreen(animated: false)
    }

    /// Reads Documents/checkpoint.log, written by the C engine
    /// (IosCheckpoint() in Sources/CEngine/src/main.c) as a raw,
    /// unbuffered, write-ahead trail of every major init/render step. If
    /// the app is killed by something no in-process handler can catch
    /// (e.g. a hard SIGKILL from a GPU/compositor/watchdog violation),
    /// this is often the *only* record of how far execution actually got.
    /// Deletes the file after reading so it doesn't get confused with a
    /// future run's checkpoints.
    private static func consumePendingCheckpointLog() -> String? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = docs.appendingPathComponent("checkpoint.log")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        try? FileManager.default.removeItem(at: url)
        return text
    }

    private func showCrashLog(_ text: String) {
        let alert = UIAlertController(
            title: "Last launch crashed",
            message: text,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Copy", style: .default) { _ in
            UIPasteboard.general.string = text
        })
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            self?.showAppropriateScreen(animated: false)
        })
        present(alert, animated: true)
    }

    private func showAppropriateScreen(animated: Bool) {
        Self.earlyCheckpoint("RootViewController: showAppropriateScreen entry")
        let hasRomOrAssets = ios_bridge_has_rom_or_assets() != 0
        Self.earlyCheckpoint("RootViewController: ios_bridge_has_rom_or_assets returned \(hasRomOrAssets)")
        if hasRomOrAssets {
            presentGame()
        } else {
            presentRomPicker(animated: animated)
        }
        Self.earlyCheckpoint("RootViewController: showAppropriateScreen returned")
    }

    private func presentRomPicker(animated: Bool) {
        // Avoid stacking pickers if one is already up.
        guard !(children.first is RomPickerViewController) else { return }
        let picker = RomPickerViewController()
        picker.onRomImported = { [weak self] in
            self?.presentGame()
        }
        addChildScreen(picker, animated: animated)
    }

    private func presentGame() {
        Self.earlyCheckpoint("RootViewController: presentGame entry")
        guard !(children.first is GameViewController) else {
            Self.earlyCheckpoint("RootViewController: presentGame - GameViewController already present, skipping")
            return
        }
        Self.earlyCheckpoint("RootViewController: presentGame - about to init GameViewController")
        let gameVC = GameViewController()
        Self.earlyCheckpoint("RootViewController: presentGame - GameViewController init done, about to addChildScreen")
        addChildScreen(gameVC, animated: true)
        Self.earlyCheckpoint("RootViewController: presentGame - addChildScreen returned")
    }

    private func addChildScreen(_ child: UIViewController, animated: Bool) {
        Self.earlyCheckpoint("RootViewController: addChildScreen entry, \(children.count) existing children")
        for existing in children {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }
        Self.earlyCheckpoint("RootViewController: addChildScreen - existing children removed, calling addChild")
        addChild(child)
        Self.earlyCheckpoint("RootViewController: addChildScreen - addChild done, about to access child.view (triggers loadView)")
        child.view.frame = view.bounds
        Self.earlyCheckpoint("RootViewController: addChildScreen - child.view accessed OK, frame set")
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        Self.earlyCheckpoint("RootViewController: addChildScreen - addSubview done, calling didMove")
        child.didMove(toParent: self)
        Self.earlyCheckpoint("RootViewController: addChildScreen - didMove done, returning")
    }
}
