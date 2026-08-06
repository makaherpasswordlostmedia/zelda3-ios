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

    private let dPad = DPadCross()

    /// Cross-shaped D-pad made of four separate arrow buttons (Up/Down/
    /// Left/Right) instead of a single circular hit-area with angle-based
    /// direction detection. Each arrow is a normal GameButton, so presses
    /// are unambiguous — you're either touching the up arrow or you're
    /// not, no angle math involved. Diagonals still work: this container
    /// itself doesn't do any touch handling, it just lays out four
    /// buttons; each button tracks its own touch independently, and since
    /// isMultipleTouchEnabled is true on the whole overlay, holding two
    /// adjacent arrows at once (e.g. up + right) presses both underlying
    /// SNES directions simultaneously, same as a real D-pad diagonal.
    private final class DPadCross: UIView {
        let up = GameButton(title: "▲", iosButton: .up)
        let down = GameButton(title: "▼", iosButton: .down)
        let left = GameButton(title: "◀", iosButton: .left)
        let right = GameButton(title: "▶", iosButton: .right)

        override init(frame: CGRect) {
            super.init(frame: frame)
            for btn in [up, down, left, right] {
                addSubview(btn)
                btn.translatesAutoresizingMaskIntoConstraints = false
                btn.layer.cornerRadius = 8
            }
            let btnSize: CGFloat = 52
            NSLayoutConstraint.activate([
                up.widthAnchor.constraint(equalToConstant: btnSize),
                up.heightAnchor.constraint(equalToConstant: btnSize),
                up.centerXAnchor.constraint(equalTo: centerXAnchor),
                up.topAnchor.constraint(equalTo: topAnchor),

                down.widthAnchor.constraint(equalToConstant: btnSize),
                down.heightAnchor.constraint(equalToConstant: btnSize),
                down.centerXAnchor.constraint(equalTo: centerXAnchor),
                down.bottomAnchor.constraint(equalTo: bottomAnchor),

                left.widthAnchor.constraint(equalToConstant: btnSize),
                left.heightAnchor.constraint(equalToConstant: btnSize),
                left.leadingAnchor.constraint(equalTo: leadingAnchor),
                left.centerYAnchor.constraint(equalTo: centerYAnchor),

                right.widthAnchor.constraint(equalToConstant: btnSize),
                right.heightAnchor.constraint(equalToConstant: btnSize),
                right.trailingAnchor.constraint(equalTo: trailingAnchor),
                right.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("not supported") }

        var allButtons: [GameButton] { [up, down, left, right] }
    }
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

        let regularButtons = [a, b, x, y, l, r, start, select]
        for btn in regularButtons {
            addSubview(btn)
            btn.translatesAutoresizingMaskIntoConstraints = false
        }
        // D-pad arrows are already subviews of dPad (added in DPadCross's
        // own init) — do NOT addSubview them here too, since UIView's
        // addSubview reparents a view that already has a superview,
        // which would rip them out of dPad and break the constraints
        // pinning them to dPad's own edges/center. Just fold them into
        // the shared `buttons` list so the touch-handling logic below
        // treats them the same as every other button.
        buttons = regularButtons + dPad.allButtons

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
            if let btn = button(at: touch.location(in: self)) {
                btn.setPressed(true)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // If a finger slides off a button, release it. We don't press a new
        // button on drag-over — keeps behavior predictable, like a real pad.
        for touch in touches {
            let loc = touch.location(in: self)
            let stillOn = button(at: loc)
            for btn in buttons where btn.isPressed && btn !== stillOn {
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
            button(at: touch.location(in: self))?.setPressed(false)
        }
    }

    /// Finds which button (if any) contains the given point, expressed in
    /// this view's own coordinate space. Uses convert(_:to:) per button
    /// rather than comparing against btn.frame directly, since not every
    /// button is a direct subview of this view anymore — the D-pad arrows
    /// are nested one level deeper inside DPadCross, so their .frame is in
    /// DPadCross's coordinate space, not this view's.
    private func button(at point: CGPoint) -> GameButton? {
        buttons.first { btn in
            guard let superview = btn.superview else { return false }
            let localPoint = superview.convert(point, from: self)
            return btn.frame.contains(localPoint)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The D-pad is now four plain GameButton arrows (up/down/left/
        // right), included directly in `buttons` below alongside
        // A/B/X/Y/L/R/Start/Select. touchesBegan/Moved/Ended already
        // handle that whole list uniformly (see `button(at:)` above), so —
        // unlike the old circular D-pad, which needed its own
        // touch-tracking subview and therefore had to be routed to
        // specially here — no special-casing is needed anymore. This view
        // just claims every touch within its own bounds and dispatches to
        // the right button itself.
        return bounds.contains(point) ? self : nil
    }
}
