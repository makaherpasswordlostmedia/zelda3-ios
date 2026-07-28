import UIKit

/// Transparent overlay of touch controls (D-pad + face buttons + shoulder
/// buttons + start/select) drawn on top of the SDL-rendered game view.
/// Each button calls `ios_bridge_set_button()` directly on touch-down /
/// touch-up — no gesture recognizers needed, since we want simultaneous
/// multi-touch (e.g. holding a direction + a face button).
final class TouchControlsView: UIView {

    private final class GameButton: UIView {
        let iosButton: IosButton
        private let label: UILabel
        private(set) var isPressed = false {
            didSet { updateAppearance() }
        }

        init(title: String, iosButton: IosButton) {
            self.iosButton = iosButton
            self.label = UILabel()
            super.init(frame: .zero)
            label.text = title
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 16, weight: .bold)
            label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
            layer.borderWidth = 1
            updateAppearance()
        }

        required init?(coder: NSCoder) { fatalError("not supported") }

        private func updateAppearance() {
            backgroundColor = UIColor.white.withAlphaComponent(isPressed ? 0.45 : 0.18)
        }

        func setPressed(_ pressed: Bool) {
            guard pressed != isPressed else { return }
            isPressed = pressed
            ios_bridge_set_button(iosButton, pressed ? 1 : 0)
        }
    }

    // D-pad is a single view handling its own multi-directional touch
    // (so diagonals work) rather than four separate button hitboxes.
    private final class DPadView: UIView {
        private var activeDirections: Set<IosButton> = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor.white.withAlphaComponent(0.12)
            layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
            layer.borderWidth = 1
            isMultipleTouchEnabled = false // one finger drives the dpad
        }

        required init?(coder: NSCoder) { fatalError("not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }

        private func directions(for point: CGPoint) -> Set<IosButton> {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let deadzone: CGFloat = 12
            guard abs(dx) > deadzone || abs(dy) > deadzone else { return [] }

            let angle = atan2(dy, dx) // radians, 0 = right, +down
            let octant = Int((angle / (.pi / 4)).rounded()) & 7
            // 0=right,1=down-right,2=down,3=down-left,4=left,5=up-left,6=up,7=up-right
            switch octant {
            case 0: return [.right]
            case 1: return [.right, .down]
            case 2: return [.down]
            case 3: return [.down, .left]
            case 4: return [.left]
            case 5: return [.left, .up]
            case 6: return [.up]
            case 7: return [.up, .right]
            default: return []
            }
        }

        private func applyDirections(_ new: Set<IosButton>) {
            for removed in activeDirections.subtracting(new) {
                ios_bridge_set_button(removed, 0)
            }
            for added in new.subtracting(activeDirections) {
                ios_bridge_set_button(added, 1)
            }
            activeDirections = new
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            applyDirections(directions(for: t.location(in: self)))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            applyDirections(directions(for: t.location(in: self)))
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            applyDirections([])
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            applyDirections([])
        }
    }

    private let dPad = DPadView()
    private var buttons: [GameButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        buildButtons()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func buildButtons() {
        addSubview(dPad)
        dPad.translatesAutoresizingMaskIntoConstraints = false

        let a = GameButton(title: "A", iosButton: .a)
        let b = GameButton(title: "B", iosButton: .b)
        let x = GameButton(title: "X", iosButton: .x)
        let y = GameButton(title: "Y", iosButton: .y)
        let l = GameButton(title: "L", iosButton: .l)
        let r = GameButton(title: "R", iosButton: .r)
        let start = GameButton(title: "Start", iosButton: .start)
        let select = GameButton(title: "Select", iosButton: .select)

        buttons = [a, b, x, y, l, r, start, select]
        for btn in buttons {
            addSubview(btn)
            btn.translatesAutoresizingMaskIntoConstraints = false
        }

        let dPadSize: CGFloat = 140
        let btnSize: CGFloat = 56
        let smallBtnHeight: CGFloat = 36

        NSLayoutConstraint.activate([
            // D-pad: bottom-left
            dPad.widthAnchor.constraint(equalToConstant: dPadSize),
            dPad.heightAnchor.constraint(equalToConstant: dPadSize),
            dPad.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 24),
            dPad.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),

            // Face buttons: bottom-right, diamond layout (Y top, A right, B bottom, X left)
            a.widthAnchor.constraint(equalToConstant: btnSize),
            a.heightAnchor.constraint(equalToConstant: btnSize),
            a.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -24),
            a.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24 - btnSize * 0.6),

            b.widthAnchor.constraint(equalToConstant: btnSize),
            b.heightAnchor.constraint(equalToConstant: btnSize),
            b.trailingAnchor.constraint(equalTo: a.leadingAnchor, constant: -12),
            b.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),

            y.widthAnchor.constraint(equalToConstant: btnSize),
            y.heightAnchor.constraint(equalToConstant: btnSize),
            y.trailingAnchor.constraint(equalTo: a.trailingAnchor),
            y.bottomAnchor.constraint(equalTo: a.topAnchor, constant: -12),

            x.widthAnchor.constraint(equalToConstant: btnSize),
            x.heightAnchor.constraint(equalToConstant: btnSize),
            x.trailingAnchor.constraint(equalTo: b.leadingAnchor, constant: -12),
            x.bottomAnchor.constraint(equalTo: b.topAnchor, constant: -12),

            // Shoulder buttons: top corners
            l.widthAnchor.constraint(equalToConstant: btnSize + 10),
            l.heightAnchor.constraint(equalToConstant: smallBtnHeight),
            l.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            l.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),

            r.widthAnchor.constraint(equalToConstant: btnSize + 10),
            r.heightAnchor.constraint(equalToConstant: smallBtnHeight),
            r.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            r.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),

            // Start/Select: bottom center
            select.widthAnchor.constraint(equalToConstant: 70),
            select.heightAnchor.constraint(equalToConstant: smallBtnHeight),
            select.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -40),
            select.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),

            start.widthAnchor.constraint(equalToConstant: 70),
            start.heightAnchor.constraint(equalToConstant: smallBtnHeight),
            start.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 40),
            start.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        for btn in buttons {
            btn.layer.cornerRadius = 8
        }
    }

    // MARK: - Touch routing for face/shoulder/start/select buttons

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let btn = buttons.first(where: { $0.frame.contains(touch.location(in: self)) }) {
                btn.setPressed(true)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // If a finger slides off a button, release it. We don't press a new
        // button on drag-over — keeps behavior predictable, like a real pad.
        for touch in touches {
            let loc = touch.location(in: self)
            for btn in buttons where btn.isPressed && !btn.frame.contains(loc) {
                btn.setPressed(false)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseButtons(for: touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseButtons(for: touches)
    }

    private func releaseButtons(for touches: Set<UITouch>) {
        for touch in touches {
            let loc = touch.location(in: self)
            if let btn = buttons.first(where: { $0.frame.contains(loc) }) {
                btn.setPressed(false)
            }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Always return self so this view handles all touches directly via
        // touchesBegan/Moved/Ended above, rather than relying on subviews'
        // own hit-testing chain — simpler and more reliable for a pad.
        return bounds.contains(point) ? self : nil
    }
}
