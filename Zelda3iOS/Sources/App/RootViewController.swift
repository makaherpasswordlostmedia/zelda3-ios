import UIKit

/// Decides, at launch and whenever we return to the foreground after a
/// picker flow, whether to show the "pick a ROM" screen or hand off to the
/// SDL2 game engine.
final class RootViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let swiftCrashLog = CrashLogger.consumePendingCrashLog()
        let checkpointLog = Self.consumePendingCheckpointLog()

        if swiftCrashLog != nil || checkpointLog != nil {
            var combined = ""
            if let checkpointLog {
                combined += "=== C engine checkpoints (last run) ===\n\(checkpointLog)\n\n"
            }
            if let swiftCrashLog {
                combined += "=== Swift crash/exception log ===\n\(swiftCrashLog)"
            }
            showCrashLog(combined)
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
        // We've seen install methods (e.g. TrollStore) where the on-disk
        // Documents folder was hard to locate from outside the process, so
        // the C side (IosCheckpoint(), main.c) now writes to several
        // candidate locations. Check all of them here and combine whatever
        // is found, so we don't miss the log just because it landed
        // somewhere other than FileManager's .documentDirectory.
        var candidates: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            candidates.append(docs.appendingPathComponent("checkpoint.log"))
        }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        candidates.append(home.appendingPathComponent("Documents/checkpoint.log"))
        candidates.append(home.appendingPathComponent("tmp/checkpoint.log"))
        // Also try a plain relative lookup from the process's actual cwd,
        // in case it differs from all of the above.
        candidates.append(URL(fileURLWithPath: "checkpoint.log"))

        var combined = ""
        var foundAny = false
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8),
                  !text.isEmpty else { continue }
            foundAny = true
            combined += "--- \(url.path) ---\n\(text)\n"
            try? FileManager.default.removeItem(at: url)
        }

        guard foundAny else {
            // Nothing found anywhere. Deliberately NOT scanning directory
            // contents here (contentsOfDirectory over an unusual sandbox
            // filesystem, e.g. under TrollStore, turned out to be able to
            // hang rather than just being slow — indistinguishable on
            // screen from a crash, since it blocks the main thread before
            // showAppropriateScreen() ever runs). Just report the fixed
            // set of paths we already tried, nothing more.
            return "No checkpoint.log found. Tried:\n" +
                candidates.map { $0.path }.joined(separator: "\n")
        }
        if combined.count > 4000 {
            combined = String(combined.prefix(4000)) + "\n... (truncated)"
        }
        return combined
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
        if ios_bridge_has_rom_or_assets() != 0 {
            presentGame()
        } else {
            presentRomPicker(animated: animated)
        }
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
        guard !(children.first is GameViewController) else { return }
        let gameVC = GameViewController()
        addChildScreen(gameVC, animated: true)
    }

    private func addChildScreen(_ child: UIViewController, animated: Bool) {
        for existing in children {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }
}
