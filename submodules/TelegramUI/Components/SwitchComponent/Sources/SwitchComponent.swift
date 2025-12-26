import Foundation
import UIKit
import Display
import AsyncDisplayKit
import ComponentFlow
import TelegramPresentationData

// MARK: - Liquid Glass Configuration for Switch

private struct SwitchGlassConfig {
    static let pressedScale: CGFloat = 0.92
    static let pressDownDuration: TimeInterval = 0.12
    static let bounceScale: CGFloat = 1.10
    static let springDamping: CGFloat = 0.65
    static let springVelocity: CGFloat = 0.5
    static let releaseDuration: TimeInterval = 0.4
    static let thumbCornerRadius: CGFloat = 14.0
}

// MARK: - Liquid Glass Switch View

/// Custom switch with Liquid Glass effects applied ONLY to the moving thumb
/// Per contest: "Only the moving element itself should apply blur"
private final class LiquidGlassSwitchView: UIControl {
    
    // State
    var isOn: Bool = false {
        didSet {
            if isOn != oldValue {
                updateThumbPosition(animated: true)
                animateTogglePulse()
                triggerHaptic(style: .light)
            }
        }
    }
    
    // Colors
    var onTintColor: UIColor = UIColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1.0) {
        didSet { updateColors() }
    }
    var offTintColor: UIColor = UIColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1.0) {
        didSet { updateColors() }
    }
    
    // Layout constants
    private let trackWidth: CGFloat = 51.0
    private let trackHeight: CGFloat = 31.0
    private let thumbSize: CGFloat = 27.0
    private let thumbInset: CGFloat = 2.0
    
    // Track layer (NO blur - just background)
    private let trackLayer = CALayer()
    
    // Thumb container (moving element with blur)
    private let thumbContainer = UIView()
    
    // LIQUID GLASS COMPONENTS - THUMB ONLY
    private var glassBlurView: UIVisualEffectView!
    private var thumbBackgroundView: UIView!
    private var glassSpecularLayer: CAGradientLayer!
    private var glassBorderLayer: CAShapeLayer!
    private var glassPressHighlightLayer: CALayer!
    
    // Haptics
    private var lightImpact: UIImpactFeedbackGenerator?
    private var mediumImpact: UIImpactFeedbackGenerator?
    
    // Gesture state
    private var isPressed = false
    private var initialTouchPoint: CGPoint?
    private var initialThumbX: CGFloat = 0
    
    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: trackWidth, height: trackHeight)))
        setupLayers()
        setupGestures()
        setupHaptics()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: trackWidth, height: trackHeight)
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(width: trackWidth, height: trackHeight)
    }
    
    // MARK: - Setup
    
    private func setupLayers() {
        // 1. Track layer (background - NO blur per contest rules)
        trackLayer.backgroundColor = offTintColor.cgColor
        trackLayer.cornerRadius = trackHeight / 2
        trackLayer.frame = CGRect(x: 0, y: 0, width: trackWidth, height: trackHeight)
        layer.addSublayer(trackLayer)
        
        // 2. Thumb container
        let thumbFrame = CGRect(x: thumbInset, y: thumbInset, width: thumbSize, height: thumbSize)
        thumbContainer.frame = thumbFrame
        thumbContainer.isUserInteractionEnabled = false
        addSubview(thumbContainer)
        
        // 3. BLUR VIEW - Only on thumb (moving element)
        // Contest requirement: "Only the moving element itself should apply blur"
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        glassBlurView = UIVisualEffectView(effect: blurEffect)
        glassBlurView.frame = thumbContainer.bounds
        glassBlurView.layer.cornerRadius = thumbSize / 2
        glassBlurView.clipsToBounds = true
        glassBlurView.isUserInteractionEnabled = false
        thumbContainer.addSubview(glassBlurView)
        
        // 4. Thumb background (white circle)
        thumbBackgroundView = UIView(frame: thumbContainer.bounds)
        thumbBackgroundView.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        thumbBackgroundView.layer.cornerRadius = thumbSize / 2
        thumbBackgroundView.layer.shadowColor = UIColor.black.cgColor
        thumbBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 2)
        thumbBackgroundView.layer.shadowRadius = 4
        thumbBackgroundView.layer.shadowOpacity = 0.15
        thumbContainer.addSubview(thumbBackgroundView)
        
        // 5. Specular highlight (glass shine)
        glassSpecularLayer = CAGradientLayer()
        glassSpecularLayer.colors = [
            UIColor.white.withAlphaComponent(0.45).cgColor,
            UIColor.white.withAlphaComponent(0.15).cgColor,
            UIColor.clear.cgColor
        ]
        glassSpecularLayer.locations = [0.0, 0.35, 1.0]
        glassSpecularLayer.startPoint = CGPoint(x: 0.5, y: 0)
        glassSpecularLayer.endPoint = CGPoint(x: 0.5, y: 1)
        glassSpecularLayer.frame = thumbContainer.bounds
        glassSpecularLayer.cornerRadius = thumbSize / 2
        glassSpecularLayer.opacity = 0.25
        thumbContainer.layer.addSublayer(glassSpecularLayer)
        
        // 6. Border glow
        glassBorderLayer = CAShapeLayer()
        glassBorderLayer.fillColor = UIColor.clear.cgColor
        glassBorderLayer.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
        glassBorderLayer.lineWidth = 0.5
        glassBorderLayer.path = UIBezierPath(
            roundedRect: thumbContainer.bounds.insetBy(dx: 0.25, dy: 0.25),
            cornerRadius: thumbSize / 2
        ).cgPath
        glassBorderLayer.frame = thumbContainer.bounds
        thumbContainer.layer.addSublayer(glassBorderLayer)
        
        // 7. Press highlight layer
        glassPressHighlightLayer = CALayer()
        glassPressHighlightLayer.backgroundColor = UIColor.white.withAlphaComponent(0.3).cgColor
        glassPressHighlightLayer.cornerRadius = thumbSize / 2
        glassPressHighlightLayer.frame = thumbContainer.bounds
        glassPressHighlightLayer.opacity = 0
        thumbContainer.layer.addSublayer(glassPressHighlightLayer)
    }
    
    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }
    
    private func setupHaptics() {
        lightImpact = UIImpactFeedbackGenerator(style: .light)
        mediumImpact = UIImpactFeedbackGenerator(style: .medium)
        lightImpact?.prepare()
    }
    
    // MARK: - Layout
    
    private func updateThumbPosition(animated: Bool) {
        let thumbX: CGFloat = isOn
            ? trackWidth - thumbSize - thumbInset
            : thumbInset
        let targetFrame = CGRect(x: thumbX, y: thumbInset, width: thumbSize, height: thumbSize)
        let targetTrackColor = isOn ? onTintColor.cgColor : offTintColor.cgColor
        
        if animated {
            // Spring animation (0.65 damping per contest spec)
            UIView.animate(
                withDuration: SwitchGlassConfig.releaseDuration,
                delay: 0,
                usingSpringWithDamping: SwitchGlassConfig.springDamping,
                initialSpringVelocity: SwitchGlassConfig.springVelocity,
                options: [.allowUserInteraction],
                animations: {
                    self.thumbContainer.frame = targetFrame
                }
            )
            
            // Track color animation
            let colorAnim = CABasicAnimation(keyPath: "backgroundColor")
            colorAnim.toValue = targetTrackColor
            colorAnim.duration = 0.25
            colorAnim.fillMode = .forwards
            colorAnim.isRemovedOnCompletion = false
            trackLayer.add(colorAnim, forKey: "trackColor")
            trackLayer.backgroundColor = targetTrackColor
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            thumbContainer.frame = targetFrame
            trackLayer.backgroundColor = targetTrackColor
            CATransaction.commit()
        }
    }
    
    private func updateColors() {
        trackLayer.backgroundColor = isOn ? onTintColor.cgColor : offTintColor.cgColor
    }
    
    // MARK: - Gestures
    
    @objc private func handleTap() {
        animatePressDown()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + SwitchGlassConfig.pressDownDuration) { [weak self] in
            guard let self = self else { return }
            self.animateRelease()
            self.isOn.toggle()
            self.sendActions(for: .valueChanged)
        }
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            initialTouchPoint = gesture.location(in: self)
            initialThumbX = thumbContainer.frame.origin.x
            animatePressDown()
            
        case .changed:
            let translation = gesture.translation(in: self)
            let velocity = gesture.velocity(in: self)
            
            // Update thumb position
            var newX = initialThumbX + translation.x
            newX = max(thumbInset, min(trackWidth - thumbSize - thumbInset, newX))
            thumbContainer.frame.origin.x = newX
            
            // Update track color based on position
            let progress = (newX - thumbInset) / (trackWidth - thumbSize - 2 * thumbInset)
            trackLayer.backgroundColor = blendColors(offTintColor, onTintColor, progress: progress).cgColor
            
            // Apply morphing stretch based on velocity
            applyMorphingStretch(velocity: velocity)
            
        case .ended, .cancelled:
            animateRelease()
            
            // Determine final state
            let center = trackWidth / 2
            let thumbCenter = thumbContainer.center.x
            let shouldBeOn = thumbCenter > center
            
            if shouldBeOn != isOn {
                isOn = shouldBeOn
                sendActions(for: .valueChanged)
            } else {
                updateThumbPosition(animated: true)
            }
            
            initialTouchPoint = nil
            
        default:
            break
        }
    }
    
    // MARK: - Liquid Glass Animations
    
    /// Press down: 92% scale in 0.12s
    private func animatePressDown() {
        guard !isPressed else { return }
        isPressed = true
        
        triggerHaptic(style: .light)
        
        UIView.animate(
            withDuration: SwitchGlassConfig.pressDownDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.thumbContainer.transform = CGAffineTransform(
                    scaleX: SwitchGlassConfig.pressedScale,
                    y: SwitchGlassConfig.pressedScale
                )
            }
        )
        
        // Show press highlight
        let highlightAnim = CABasicAnimation(keyPath: "opacity")
        highlightAnim.fromValue = 0
        highlightAnim.toValue = 1
        highlightAnim.duration = SwitchGlassConfig.pressDownDuration
        highlightAnim.fillMode = .forwards
        highlightAnim.isRemovedOnCompletion = false
        glassPressHighlightLayer.add(highlightAnim, forKey: "press")
        
        // Enhance specular
        let specularAnim = CABasicAnimation(keyPath: "opacity")
        specularAnim.toValue = 0.45
        specularAnim.duration = SwitchGlassConfig.pressDownDuration
        specularAnim.fillMode = .forwards
        specularAnim.isRemovedOnCompletion = false
        glassSpecularLayer.add(specularAnim, forKey: "pressSpecular")
    }
    
    /// Release with spring bounce (0.65 damping)
    private func animateRelease() {
        guard isPressed else { return }
        isPressed = false
        
        UIView.animate(
            withDuration: SwitchGlassConfig.releaseDuration,
            delay: 0,
            usingSpringWithDamping: SwitchGlassConfig.springDamping,
            initialSpringVelocity: SwitchGlassConfig.springVelocity,
            options: [.allowUserInteraction],
            animations: {
                self.thumbContainer.transform = .identity
            }
        )
        
        // Hide press highlight
        let hideAnim = CABasicAnimation(keyPath: "opacity")
        hideAnim.toValue = 0
        hideAnim.duration = 0.25
        hideAnim.fillMode = .forwards
        hideAnim.isRemovedOnCompletion = false
        glassPressHighlightLayer.add(hideAnim, forKey: "release")
        
        // Reset specular
        let specularAnim = CABasicAnimation(keyPath: "opacity")
        specularAnim.toValue = 0.25
        specularAnim.duration = 0.25
        specularAnim.fillMode = .forwards
        specularAnim.isRemovedOnCompletion = false
        glassSpecularLayer.add(specularAnim, forKey: "releaseSpecular")
    }
    
    /// Toggle pulse animation (morphing effect)
    private func animateTogglePulse() {
        // Pulse specular during state change
        let pulseAnim = CAKeyframeAnimation(keyPath: "opacity")
        pulseAnim.values = [0.25, 0.5, 0.25]
        pulseAnim.keyTimes = [0, 0.4, 1]
        pulseAnim.duration = 0.3
        glassSpecularLayer.add(pulseAnim, forKey: "togglePulse")
    }
    
    /// Morphing stretch based on drag velocity
    private func applyMorphingStretch(velocity: CGPoint) {
        let stretchFactor: CGFloat = 0.0004
        let maxStretch: CGFloat = 0.12
        
        let stretchX = min(abs(velocity.x) * stretchFactor, maxStretch)
        let stretchY = stretchX * 0.5
        
        let scaleX = SwitchGlassConfig.pressedScale + stretchX
        let scaleY = SwitchGlassConfig.pressedScale - stretchY
        
        UIView.animate(withDuration: 0.08, delay: 0, options: [.curveLinear, .allowUserInteraction]) {
            self.thumbContainer.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        }
    }
    
    // MARK: - Helpers
    
    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light:
            lightImpact?.impactOccurred()
        case .medium:
            mediumImpact?.impactOccurred()
        default:
            break
        }
    }
    
    private func blendColors(_ color1: UIColor, _ color2: UIColor, progress: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        color1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        let p = max(0, min(1, progress))
        return UIColor(
            red: r1 + (r2 - r1) * p,
            green: g1 + (g2 - g1) * p,
            blue: b1 + (b2 - b1) * p,
            alpha: a1 + (a2 - a1) * p
        )
    }
    
    func setOn(_ on: Bool, animated: Bool) {
        if isOn != on {
            isOn = on
            if !animated {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                updateThumbPosition(animated: false)
                CATransaction.commit()
            }
        }
    }
}

// MARK: - SwitchComponent

public final class SwitchComponent: Component {
    public typealias EnvironmentType = Empty
    
    let tintColor: UIColor?
    let value: Bool
    let valueUpdated: (Bool) -> Void
    
    public init(
        tintColor: UIColor? = nil,
        value: Bool,
        valueUpdated: @escaping (Bool) -> Void
    ) {
        self.tintColor = tintColor
        self.value = value
        self.valueUpdated = valueUpdated
    }
    
    public static func ==(lhs: SwitchComponent, rhs: SwitchComponent) -> Bool {
        if lhs.tintColor != rhs.tintColor {
            return false
        }
        if lhs.value != rhs.value {
            return false
        }
        return true
    }
    
    public final class View: UIView {
        // CHANGED: Use LiquidGlassSwitchView instead of UISwitch
        private let switchView: LiquidGlassSwitchView
    
        private var component: SwitchComponent?
        
        override init(frame: CGRect) {
            self.switchView = LiquidGlassSwitchView()
            
            super.init(frame: frame)
            
            self.addSubview(self.switchView)
            
            self.switchView.addTarget(self, action: #selector(self.valueChanged(_:)), for: .valueChanged)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @objc func valueChanged(_ sender: Any) {
            self.component?.valueUpdated(self.switchView.isOn)
        }
        
        func update(component: SwitchComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
            self.component = component
          
            if let tintColor = component.tintColor {
                self.switchView.onTintColor = tintColor
            }
            self.switchView.setOn(component.value, animated: !transition.animation.isImmediate)
            
            let size = self.switchView.sizeThatFits(availableSize)
            self.switchView.frame = CGRect(origin: .zero, size: size)
                        
            return size
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}