import UIKit
import UniformTypeIdentifiers
import Darwin

/// Screen shown when no ROM/assets have been imported yet. Lets the user
/// pick their own legally-dumped `zelda3.sfc` file from the Files app
/// (iCloud Drive, "On My iPhone", a connected USB drive, etc.) and copies
/// it into the app sandbox so the engine can read it.
final class RomPickerViewController: UIViewController {

    var onRomImported: (() -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let pickButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    /// Same rationale as GameViewController/RootViewController — raw POSIX
    /// write so this doesn't depend on any other part of the app having
    /// run successfully, and can't itself throw an uncaught NSException.
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
        Self.earlyCheckpoint("RomPickerViewController: viewDidLoad - before super")
        super.viewDidLoad()
        Self.earlyCheckpoint("RomPickerViewController: viewDidLoad - super done")
        view.backgroundColor = .systemBackground
        layoutUI()
        Self.earlyCheckpoint("RomPickerViewController: viewDidLoad - layoutUI done, returning")
    }

    private func layoutUI() {
        titleLabel.text = "Zelda 3"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center

        subtitleLabel.text =
            "Select your own legally-dumped ROM file (zelda3.sfc) to continue.\n" +
            "You must own the original cartridge. This app does not provide or download ROMs."
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        pickButton.setTitle("Choose ROM File…", for: .normal)
        pickButton.setImage(UIImage(systemName: "folder"), for: .normal)
        pickButton.tintColor = .white
        pickButton.setTitleColor(.white, for: .normal)
        pickButton.backgroundColor = .systemBlue
        pickButton.layer.cornerRadius = 10
        pickButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        pickButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
        pickButton.addTarget(self, action: #selector(pickButtonTapped), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, subtitleLabel, pickButton, activityIndicator, statusLabel,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        activityIndicator.hidesWhenStopped = true
    }

    @objc private func pickButtonTapped() {
        // .data/.item alone are too generic: Files sometimes shows the file
        // but won't actually complete a tap-to-select on it (the picker
        // stays open, delegate never fires) when the file's extension isn't
        // one of the picker's declared content types. .sfc/.smc have no
        // system-registered UTType, so we synthesize dynamic ones from the
        // filename extension and list them explicitly, alongside the
        // .data/.item fallback for anything else the user might pick.
        var types: [UTType] = [.data, .item]
        if let sfc = UTType(filenameExtension: "sfc") { types.append(sfc) }
        if let smc = UTType(filenameExtension: "smc") { types.append(smc) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func setBusy(_ busy: Bool, message: String = "") {
        pickButton.isEnabled = !busy
        if busy {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        statusLabel.text = message
    }

    private func importRom(at url: URL) {
        setBusy(true, message: "Importing…")

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        // Basic sanity checks before we hand this to the C engine.
        let ext = url.pathExtension.lowercased()
        guard ext == "sfc" || ext == "smc" else {
            setBusy(false, message: "That doesn't look like a SNES ROM (.sfc/.smc). Please pick your zelda3.sfc file.")
            return
        }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        // LTTP ROMs are small; reject anything wildly out of range as a
        // sanity check (catches picking the wrong file by accident).
        guard fileSize > 512 * 1024 && fileSize < 8 * 1024 * 1024 else {
            setBusy(false, message: "File size doesn't look right for a LTTP ROM. Please double-check the file.")
            return
        }

        let path = url.path
        let ok = path.withCString { cPath in
            ios_bridge_import_rom(cPath) != 0
        }

        if ok {
            setBusy(false, message: "ROM imported. Preparing game assets…")
            onRomImported?()
        } else {
            setBusy(false, message: "Couldn't import that file. Please try again.")
        }
    }
}

extension RomPickerViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importRom(at: url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // No-op: user stays on the picker screen and can tap the button again.
    }
}
