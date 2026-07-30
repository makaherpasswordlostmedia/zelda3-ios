import UIKit

/// Decides, at launch and whenever we return to the foreground after a
/// picker flow, whether to show the "pick a ROM" screen or hand off to the
/// SDL2 game engine.
final class RootViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        if let crashLog = CrashLogger.consumePendingCrashLog() {
            showCrashLog(crashLog)
            return
        }

        showAppropriateScreen(animated: false)
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
