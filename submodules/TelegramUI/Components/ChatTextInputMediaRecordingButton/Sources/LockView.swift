// ============================================================
// MODIFICATIONS FOR LockView.swift
// Add Liquid Glass effects to the lock panel
// ============================================================

// SECTION 1: Replace the entire LockView.swift file with this updated version
// ------------------------------------------------------------

import UIKit
import LegacyComponents
import AppBundle
import Lottie
import TelegramPresentationData

// MARK: - Liquid Glass Lock Configuration

private struct LockGlassConfig {
    static let pressedScale: CGFloat = 0.92
    static let pressDownDuration: TimeInterval = 0.12
    static let bounceScale: CGFloat = 1.10
    static let springDamping: CGFloat = 0.65
    static let springVelocity: CGFloat = 0.5
    static let releaseDuration: TimeInterval = 0.4
    static let cornerRadius: CGFloat = 20.0
    static let blurIntensity: CGFloat = 0.8
}

// MARK: - Liquid Glass Specular Layer for Lock

private final class LockGlassSpecularLayer: CALayer {
    
    private var backgroundLayer: CALayer?
    private var specularLayer: CAGradientLayer?
    private var borderLayer: CAShapeLayer?
    private var innerGlowLayer: CALayer?
    
    override init() {
        super.init()
        setupLayers()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        // Subtle background tint
        let bg = CALayer()
        bg.backgroundColor = UIColor.white.withAlphaComponent(0.06).cgColor
        self.backgroundLayer = bg
        addSublayer(bg)
        
        // Inner glow effect
        let innerGlow = CALayer()
        innerGlow.backgroundColor = UIColor.white.withAlphaComponent(0.03).cgColor
        self.innerGlowLayer = innerGlow
        addSublayer(innerGlow)
        
        // Specular highlight gradient (top-lit glass effect)
        let specular = CAGradientLayer()
        specular.colors = [
            UIColor.white.withAlphaComponent(0.4).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
            UIColor.clear.cgColor
        ]
        specular.locations = [0.0, 0.3, 1.0]
        specular.startPoint = CGPoint(x: 0.5, y: 0)
        specular.endPoint = CGPoint(x: 0.5, y: 1)
        specular.opacity = 0.3
        self.specularLayer = specular
        addSublayer(specular)
        
        // Border glow
        let border = CAShapeLayer()
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        border.lineWidth = 0.5
        self.borderLayer = border
        addSublayer(border)
    }
    
    func configure(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        masksToBounds = true
        
        backgroundLayer?.cornerRadius = cornerRadius
        innerGlowLayer?.cornerRadius = cornerRadius - 2
        specularLayer?.cornerRadius = cornerRadius
        
        setNeedsLayout()
    }
    
    override func layoutSublayers() {
        super.layoutSublayers()
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        backgroundLayer?.frame = bounds
        innerGlowLayer?.frame = bounds.insetBy(dx: 2, dy: 2)
        specularLayer?.frame = bounds
        
        let borderPath = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
            cornerRadius: cornerRadius
        )
        borderLayer?.path = borderPath.cgPath
        borderLayer?.frame = bounds
        
        CATransaction.commit()
    }
    
    func animateHighlight(_ highlighted: Bool) {
        let targetOpacity: Float = highlighted ? 0.5 : 0.3
        let targetBgAlpha: CGFloat = highlighted ? 0.12 : 0.06
        
        let duration: TimeInterval = highlighted ? 0.1 : 0.3
        
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.toValue = targetOpacity
        opacityAnim.duration = duration
        opacityAnim.fillMode = .forwards
        opacityAnim.isRemovedOnCompletion = false
        specularLayer?.add(opacityAnim, forKey: "highlight")
        
        let bgAnim = CABasicAnimation(keyPath: "backgroundColor")
        bgAnim.toValue = UIColor.white.withAlphaComponent(targetBgAlpha).cgColor
        bgAnim.duration = duration
        bgAnim.fillMode = .forwards
        bgAnim.isRemovedOnCompletion = false
        backgroundLayer?.add(bgAnim, forKey: "highlightBg")
    }
    
    func animateLockness(_ lockness: CGFloat) {
        // Increase specular intensity as user approaches lock position
        let intensity = 0.3 + (lockness * 0.2)
        specularLayer?.opacity = Float(intensity)
        
        // Pulse the border when close to locking
        if lockness > 0.8 {
            let pulseAnim = CABasicAnimation(keyPath: "strokeColor")
            pulseAnim.fromValue = UIColor.white.withAlphaComponent(0.25).cgColor
            pulseAnim.toValue = UIColor.white.withAlphaComponent(0.5).cgColor
            pulseAnim.duration = 0.15
            pulseAnim.autoreverses = true
            borderLayer?.add(pulseAnim, forKey: "pulse")
        }
    }
}

// MARK: - Lock View with Liquid Glass

final class LockView: UIButton, TGModernConversationInputMicButtonLock {
    private let useDarkTheme: Bool
    private let pause: Bool
    
    private let idleView: AnimationView
    private let lockingView: AnimationView
    
    // MARK: - Liquid Glass Properties
    
    /// Blur view for glass effect
    private var glassBlurView: UIVisualEffectView?
    
    /// Specular shine layer
    private var glassSpecularLayer: LockGlassSpecularLayer?
    
    /// Press highlight layer
    private var glassPressLayer: CALayer?
    
    /// Haptic generators
    private var lightImpact: UIImpactFeedbackGenerator?
    private var mediumImpact: UIImpactFeedbackGenerator?
    
    /// Track press state
    private var isPressed: Bool = false
    
    init(frame: CGRect, theme: PresentationTheme, useDarkTheme: Bool = false, pause: Bool = false, strings: PresentationStrings) {
        self.useDarkTheme = useDarkTheme
        self.pause = pause
        
        if let url = getAppBundle().url(forResource: "LockWait", withExtension: "json"), let animation = Animation.filepath(url.path) {
            let view = AnimationView(animation: animation, configuration: LottieConfiguration(renderingEngine: .mainThread, decodingStrategy: .codable))
            view.loopMode = .autoReverse
            view.backgroundColor = .clear
            view.isOpaque = false
            self.idleView = view
        } else {
            self.idleView = AnimationView()
        }
        
        if let url = getAppBundle().url(forResource: self.pause ? "LockPause" : "Lock", withExtension: "json"), let animation = Animation.filepath(url.path) {
            let view = AnimationView(animation: animation, configuration: LottieConfiguration(renderingEngine: .mainThread, decodingStrategy: .codable))
            view.backgroundColor = .clear
            view.isOpaque = false
            self.lockingView = view
        } else {
            self.lockingView = AnimationView()
        }
        
        super.init(frame: frame)
        
        accessibilityLabel = strings.VoiceOver_Recording_StopAndPreview
        
        // Setup Liquid Glass effect FIRST (behind content)
        setupLiquidGlassEffect()
        
        // Then add animation views
        addSubview(idleView)
        idleView.frame = bounds
        
        addSubview(lockingView)
        lockingView.frame = bounds
        
        updateTheme(theme)
        updateLockness(0)
        
        // Add touch handlers for glass animations
        addTarget(self, action: #selector(handleTouchDown), for: .touchDown)
        addTarget(self, action: #selector(handleTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Liquid Glass Setup
    
    private func setupLiquidGlassEffect() {
        // Initialize haptic generators
        if #available(iOS 10.0, *) {
            lightImpact = UIImpactFeedbackGenerator(style: .light)
            mediumImpact = UIImpactFeedbackGenerator(style: .medium)
        }
        
        // 1. Create blur view (glass body) - ONLY the lock icon should have blur
        // Per contest: "Only the moving element itself should apply blur"
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let blur = UIVisualEffectView(effect: blurEffect)
        blur.layer.cornerRadius = LockGlassConfig.cornerRadius
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false
        insertSubview(blur, at: 0)
        self.glassBlurView = blur
        
        // 2. Create specular layer (shine)
        let specular = LockGlassSpecularLayer()
        specular.configure(cornerRadius: LockGlassConfig.cornerRadius)
        layer.insertSublayer(specular, above: blur.layer)
        self.glassSpecularLayer = specular
        
        // 3. Create press highlight
        let press = CALayer()
        press.backgroundColor = UIColor.white.withAlphaComponent(0.2).cgColor
        press.cornerRadius = LockGlassConfig.cornerRadius
        press.opacity = 0
        layer.insertSublayer(press, above: specular)
        self.glassPressLayer = press
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        idleView.frame = bounds
        lockingView.frame = bounds
        
        // Update glass effect frames
        let glassFrame = bounds.insetBy(dx: 0, dy: 0)
        glassBlurView?.frame = glassFrame
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glassSpecularLayer?.frame = glassFrame
        glassPressLayer?.frame = glassFrame
        CATransaction.commit()
    }
    
    // MARK: - Liquid Glass Animations
    
    @objc private func handleTouchDown() {
        isPressed = true
        animateGlassPressDown()
    }
    
    @objc private func handleTouchUp() {
        guard isPressed else { return }
        isPressed = false
        animateGlassRelease()
    }
    
    /// Press down: 92% scale in 0.12s
    private func animateGlassPressDown() {
        lightImpact?.impactOccurred()
        
        UIView.animate(
            withDuration: LockGlassConfig.pressDownDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.transform = CGAffineTransform(
                    scaleX: LockGlassConfig.pressedScale,
                    y: LockGlassConfig.pressedScale
                )
            }
        )
        
        // Show press highlight
        let highlightAnim = CABasicAnimation(keyPath: "opacity")
        highlightAnim.fromValue = 0
        highlightAnim.toValue = 1
        highlightAnim.duration = LockGlassConfig.pressDownDuration
        highlightAnim.fillMode = .forwards
        highlightAnim.isRemovedOnCompletion = false
        glassPressLayer?.add(highlightAnim, forKey: "press")
        
        glassSpecularLayer?.animateHighlight(true)
    }
    
    /// Release with spring bounce (0.65 damping)
    private func animateGlassRelease() {
        UIView.animate(
            withDuration: LockGlassConfig.releaseDuration,
            delay: 0,
            usingSpringWithDamping: LockGlassConfig.springDamping,
            initialSpringVelocity: LockGlassConfig.springVelocity,
            options: [.allowUserInteraction],
            animations: {
                self.transform = .identity
            }
        )
        
        let hideAnim = CABasicAnimation(keyPath: "opacity")
        hideAnim.toValue = 0
        hideAnim.duration = 0.25
        hideAnim.fillMode = .forwards
        hideAnim.isRemovedOnCompletion = false
        glassPressLayer?.add(hideAnim, forKey: "release")
        
        glassSpecularLayer?.animateHighlight(false)
    }
    
    /// Bounce animation when locked: 110% then spring back
    func animateLockBounce() {
        mediumImpact?.impactOccurred()
        
        UIView.animate(
            withDuration: 0.15,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                self.transform = CGAffineTransform(
                    scaleX: LockGlassConfig.bounceScale,
                    y: LockGlassConfig.bounceScale
                )
            }
        ) { _ in
            UIView.animate(
                withDuration: LockGlassConfig.releaseDuration,
                delay: 0,
                usingSpringWithDamping: LockGlassConfig.springDamping,
                initialSpringVelocity: LockGlassConfig.springVelocity,
                options: [],
                animations: {
                    self.transform = .identity
                }
            )
        }
    }
    
    // MARK: - TGModernConversationInputMicButtonLock Protocol
    
    func updateLockness(_ lockness: CGFloat) {
        idleView.isHidden = lockness > 0
        if lockness > 0 && idleView.isAnimationPlaying {
            idleView.stop()
        } else if lockness == 0 && !idleView.isAnimationPlaying {
            idleView.play()
        }
        lockingView.isHidden = !idleView.isHidden
        
        lockingView.currentProgress = lockness
        
        // Update glass effect based on lockness
        glassSpecularLayer?.animateLockness(lockness)
        
        // Trigger lock bounce when fully locked
        if lockness >= 1.0 {
            animateLockBounce()
        }
    }
    
    func updateTheme(_ theme: PresentationTheme) {
        for keypath in idleView.allKeypaths(predicate: { $0.keys.last == "Color" }) {
            idleView.setValueProvider(ColorValueProvider(theme.chat.inputPanel.panelControlColor.lottieColorValue), keypath: AnimationKeypath(keypath: keypath))
        }
        
        for keypath in lockingView.allKeypaths(predicate: { $0.keys.last == "Color" }) {
            lockingView.setValueProvider(ColorValueProvider(theme.chat.inputPanel.panelControlColor.lottieColorValue), keypath: AnimationKeypath(keypath: keypath))
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let superTest = super.hitTest(point, with: event)
        if superTest === lockingView {
            return self
        }
        return superTest
    }
}

