import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import LegacyComponents
import ComponentFlow

// MARK: - Liquid Glass Configuration for Slider

private struct SliderGlassConfig {
    static let pressedScale: CGFloat = 0.92
    static let pressDownDuration: TimeInterval = 0.12
    static let bounceScale: CGFloat = 1.10
    static let springDamping: CGFloat = 0.65
    static let springVelocity: CGFloat = 0.5
    static let releaseDuration: TimeInterval = 0.4
    static let knobSize: CGFloat = 28.0
}

// MARK: - Liquid Glass Knob Image Generator

/// Generates a knob image with Liquid Glass visual elements baked in
/// The blur effect is applied at runtime via UIVisualEffectView overlay
private func generateLiquidGlassKnobImage(size: CGFloat, knobColor: UIColor?) -> UIImage? {
    let fullSize = CGSize(width: 40.0, height: 40.0)
    
    return generateImage(fullSize, rotatedContext: { contextSize, context in
        context.clear(CGRect(origin: .zero, size: contextSize))
        
        let knobRect = CGRect(
            x: floor((contextSize.width - size) * 0.5),
            y: floor((contextSize.height - size) * 0.5),
            width: size,
            height: size
        )
        
        // Shadow
        context.setShadow(offset: CGSize(width: 0.0, height: 2.0), blur: 8.0, color: UIColor(white: 0.0, alpha: 0.2).cgColor)
        
        // Main knob fill
        let fillColor = knobColor ?? UIColor.white
        context.setFillColor(fillColor.withAlphaComponent(0.95).cgColor)
        context.fillEllipse(in: knobRect)
        
        // Reset shadow for decorations
        context.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Specular highlight (top gradient)
        let specularRect = CGRect(
            x: knobRect.minX + 2,
            y: knobRect.minY + 2,
            width: knobRect.width - 4,
            height: knobRect.height * 0.5
        )
        
        context.saveGState()
        context.addEllipse(in: knobRect)
        context.clip()
        
        let specularColors = [
            UIColor.white.withAlphaComponent(0.5).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
            UIColor.clear.cgColor
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: specularColors as CFArray, locations: [0.0, 0.4, 1.0]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: knobRect.midX, y: knobRect.minY),
                end: CGPoint(x: knobRect.midX, y: knobRect.maxY),
                options: []
            )
        }
        context.restoreGState()
        
        // Border glow
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(0.5)
        context.strokeEllipse(in: knobRect.insetBy(dx: 0.25, dy: 0.25))
    })
}

// MARK: - Liquid Glass Slider View

/// Custom slider with Liquid Glass effects on the knob ONLY
/// Per contest: "Only the moving element itself should apply blur"
private final class LiquidGlassSliderView: UIControl {
    
    // Value
    var value: CGFloat = 0 {
        didSet {
            if value != oldValue {
                updateKnobPosition(animated: false)
            }
        }
    }
    var minimumValue: CGFloat = 0
    var maximumValue: CGFloat = 1
    
    // Colors
    var trackBackgroundColor: UIColor = UIColor(white: 0.9, alpha: 1.0) {
        didSet { trackBackgroundLayer.backgroundColor = trackBackgroundColor.cgColor }
    }
    var trackForegroundColor: UIColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) {
        didSet { trackForegroundLayer.backgroundColor = trackForegroundColor.cgColor }
    }
    var knobColor: UIColor? {
        didSet { updateKnobAppearance() }
    }
    var knobSize: CGFloat = SliderGlassConfig.knobSize {
        didSet { updateKnobAppearance() }
    }
    
    // Discrete mode
    var isDiscrete = false
    var discreteValueCount = 0
    var markPositions = false
    
    // Callbacks
    var interactionBegan: (() -> Void)?
    var interactionEnded: (() -> Void)?
    
    // Layout
    private let trackHeight: CGFloat = 4.0
    private let hitAreaExpansion: CGFloat = 22.0
    
    // Track layers (NO blur)
    private let trackBackgroundLayer = CALayer()
    private let trackForegroundLayer = CALayer()
    private var discreteMarkLayers: [CALayer] = []
    
    // Knob container (moving element with blur)
    private let knobContainer = UIView()
    
    // LIQUID GLASS COMPONENTS - KNOB ONLY
    private var glassBlurView: UIVisualEffectView!
    private var knobImageView: UIImageView!
    private var glassSpecularLayer: CAGradientLayer!
    private var glassBorderLayer: CAShapeLayer!
    private var glassPressHighlightLayer: CALayer!
    
    // Haptics
    private var lightImpact: UIImpactFeedbackGenerator?
    private var mediumImpact: UIImpactFeedbackGenerator?
    
    // Gesture state
    private var isTracking = false
    private var initialTouchPoint: CGPoint?
    private var initialValue: CGFloat = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
        setupGestures()
        setupHaptics()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupLayers() {
        // Track background (NO blur)
        trackBackgroundLayer.backgroundColor = trackBackgroundColor.cgColor
        trackBackgroundLayer.cornerRadius = trackHeight / 2
        layer.addSublayer(trackBackgroundLayer)
        
        // Track foreground/fill (NO blur)
        trackForegroundLayer.backgroundColor = trackForegroundColor.cgColor
        trackForegroundLayer.cornerRadius = trackHeight / 2
        layer.addSublayer(trackForegroundLayer)
        
        // Knob container
        knobContainer.isUserInteractionEnabled = false
        addSubview(knobContainer)
        
        // BLUR VIEW - Only on knob (moving element)
        // Contest: "Only the moving element itself should apply blur"
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        glassBlurView = UIVisualEffectView(effect: blurEffect)
        glassBlurView.layer.cornerRadius = knobSize / 2
        glassBlurView.clipsToBounds = true
        glassBlurView.isUserInteractionEnabled = false
        knobContainer.addSubview(glassBlurView)
        
        // Knob image (white circle with baked-in specular)
        knobImageView = UIImageView()
        knobImageView.image = generateLiquidGlassKnobImage(size: knobSize, knobColor: knobColor)
        knobImageView.contentMode = .center
        knobContainer.addSubview(knobImageView)
        
        // Specular overlay (additional shine)
        glassSpecularLayer = CAGradientLayer()
        glassSpecularLayer.colors = [
            UIColor.white.withAlphaComponent(0.4).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
            UIColor.clear.cgColor
        ]
        glassSpecularLayer.locations = [0.0, 0.35, 1.0]
        glassSpecularLayer.startPoint = CGPoint(x: 0.5, y: 0)
        glassSpecularLayer.endPoint = CGPoint(x: 0.5, y: 1)
        glassSpecularLayer.cornerRadius = knobSize / 2
        glassSpecularLayer.opacity = 0.2
        knobContainer.layer.addSublayer(glassSpecularLayer)
        
        // Border glow
        glassBorderLayer = CAShapeLayer()
        glassBorderLayer.fillColor = UIColor.clear.cgColor
        glassBorderLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        glassBorderLayer.lineWidth = 0.5
        knobContainer.layer.addSublayer(glassBorderLayer)
        
        // Press highlight
        glassPressHighlightLayer = CALayer()
        glassPressHighlightLayer.backgroundColor = UIColor.white.withAlphaComponent(0.3).cgColor
        glassPressHighlightLayer.cornerRadius = knobSize / 2
        glassPressHighlightLayer.opacity = 0
        knobContainer.layer.addSublayer(glassPressHighlightLayer)
        
        updateKnobAppearance()
    }
    
    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }
    
    private func setupHaptics() {
        lightImpact = UIImpactFeedbackGenerator(style: .light)
        mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    }
    
    private func updateKnobAppearance() {
        let containerSize = CGSize(width: 40, height: 40)
        knobContainer.bounds = CGRect(origin: .zero, size: containerSize)
        
        glassBlurView.frame = CGRect(
            x: (containerSize.width - knobSize) / 2,
            y: (containerSize.height - knobSize) / 2,
            width: knobSize,
            height: knobSize
        )
        glassBlurView.layer.cornerRadius = knobSize / 2
        
        knobImageView.frame = knobContainer.bounds
        knobImageView.image = generateLiquidGlassKnobImage(size: knobSize, knobColor: knobColor)
        
        let knobRect = CGRect(
            x: (containerSize.width - knobSize) / 2,
            y: (containerSize.height - knobSize) / 2,
            width: knobSize,
            height: knobSize
        )
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glassSpecularLayer.frame = knobRect
        glassSpecularLayer.cornerRadius = knobSize / 2
        
        glassBorderLayer.path = UIBezierPath(
            roundedRect: knobRect.insetBy(dx: 0.25, dy: 0.25),
            cornerRadius: knobSize / 2
        ).cgPath
        glassBorderLayer.frame = CGRect(origin: .zero, size: containerSize)
        
        glassPressHighlightLayer.frame = knobRect
        glassPressHighlightLayer.cornerRadius = knobSize / 2
        CATransaction.commit()
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let trackY = (bounds.height - trackHeight) / 2
        trackBackgroundLayer.frame = CGRect(x: 0, y: trackY, width: bounds.width, height: trackHeight)
        
        updateKnobPosition(animated: false)
        updateDiscreteMarks()
    }
    
    private func updateKnobPosition(animated: Bool) {
        let range = maximumValue - minimumValue
        guard range > 0 else { return }
        
        let normalizedValue = (value - minimumValue) / range
        let trackWidth = bounds.width - 40 // Account for knob width
        let knobX = 20 + normalizedValue * trackWidth
        let knobY = bounds.height / 2
        
        let knobCenter = CGPoint(x: knobX, y: knobY)
        
        // Track foreground width
        let foregroundWidth = knobX
        let trackY = (bounds.height - trackHeight) / 2
        let foregroundFrame = CGRect(x: 0, y: trackY, width: foregroundWidth, height: trackHeight)
        
        if animated {
            UIView.animate(
                withDuration: SliderGlassConfig.releaseDuration,
                delay: 0,
                usingSpringWithDamping: SliderGlassConfig.springDamping,
                initialSpringVelocity: SliderGlassConfig.springVelocity,
                options: [.allowUserInteraction],
                animations: {
                    self.knobContainer.center = knobCenter
                }
            )
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            trackForegroundLayer.frame = foregroundFrame
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            knobContainer.center = knobCenter
            trackForegroundLayer.frame = foregroundFrame
            CATransaction.commit()
        }
    }
    
    private func updateDiscreteMarks() {
        // Remove old marks
        discreteMarkLayers.forEach { $0.removeFromSuperlayer() }
        discreteMarkLayers.removeAll()
        
        guard isDiscrete, discreteValueCount > 1, markPositions else { return }
        
        let trackWidth = bounds.width - 40
        let trackY = (bounds.height - trackHeight) / 2
        
        for i in 0..<discreteValueCount {
            let markX = 20 + (CGFloat(i) / CGFloat(discreteValueCount - 1)) * trackWidth
            
            let markLayer = CALayer()
            markLayer.backgroundColor = UIColor.white.withAlphaComponent(0.8).cgColor
            markLayer.cornerRadius = 2.5
            markLayer.frame = CGRect(x: markX - 2.5, y: trackY - 1, width: 5, height: trackHeight + 2)
            layer.insertSublayer(markLayer, above: trackForegroundLayer)
            discreteMarkLayers.append(markLayer)
        }
    }
    
    // MARK: - Gestures
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isTracking = true
            initialTouchPoint = gesture.location(in: self)
            initialValue = value
            animatePressDown()
            interactionBegan?()
            lightImpact?.impactOccurred()
            
        case .changed:
            guard let initialPoint = initialTouchPoint else { return }
            
            let translation = gesture.translation(in: self)
            let velocity = gesture.velocity(in: self)
            
            let trackWidth = bounds.width - 40
            let valueDelta = (translation.x / trackWidth) * (maximumValue - minimumValue)
            var newValue = initialValue + valueDelta
            
            // Clamp
            newValue = max(minimumValue, min(maximumValue, newValue))
            
            // Snap to discrete values if needed
            if isDiscrete, discreteValueCount > 1 {
                let step = (maximumValue - minimumValue) / CGFloat(discreteValueCount - 1)
                newValue = round(newValue / step) * step
                
                // Haptic on discrete step change
                if abs(newValue - value) >= step * 0.5 {
                    lightImpact?.impactOccurred()
                }
            }
            
            value = newValue
            sendActions(for: .valueChanged)
            
            // Apply morphing stretch
            applyMorphingStretch(velocity: velocity)
            
        case .ended, .cancelled:
            isTracking = false
            animateRelease()
            interactionEnded?()
            initialTouchPoint = nil
            
        default:
            break
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let trackWidth = bounds.width - 40
        
        var normalizedValue = (location.x - 20) / trackWidth
        normalizedValue = max(0, min(1, normalizedValue))
        
        var newValue = minimumValue + normalizedValue * (maximumValue - minimumValue)
        
        // Snap to discrete
        if isDiscrete, discreteValueCount > 1 {
            let step = (maximumValue - minimumValue) / CGFloat(discreteValueCount - 1)
            newValue = round(newValue / step) * step
        }
        
        // Animate bounce
        animatePressDown()
        lightImpact?.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + SliderGlassConfig.pressDownDuration) { [weak self] in
            guard let self = self else { return }
            self.value = newValue
            self.sendActions(for: .valueChanged)
            self.updateKnobPosition(animated: true)
            self.animateSelectionBounce()
        }
    }
    
    // MARK: - Liquid Glass Animations
    
    private func animatePressDown() {
        UIView.animate(
            withDuration: SliderGlassConfig.pressDownDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.knobContainer.transform = CGAffineTransform(
                    scaleX: SliderGlassConfig.pressedScale,
                    y: SliderGlassConfig.pressedScale
                )
            }
        )
        
        // Show press highlight
        let highlightAnim = CABasicAnimation(keyPath: "opacity")
        highlightAnim.fromValue = 0
        highlightAnim.toValue = 1
        highlightAnim.duration = SliderGlassConfig.pressDownDuration
        highlightAnim.fillMode = .forwards
        highlightAnim.isRemovedOnCompletion = false
        glassPressHighlightLayer.add(highlightAnim, forKey: "press")
        
        // Enhance specular
        let specularAnim = CABasicAnimation(keyPath: "opacity")
        specularAnim.toValue = 0.4
        specularAnim.duration = SliderGlassConfig.pressDownDuration
        specularAnim.fillMode = .forwards
        specularAnim.isRemovedOnCompletion = false
        glassSpecularLayer.add(specularAnim, forKey: "pressSpecular")
    }
    
    private func animateRelease() {
        UIView.animate(
            withDuration: SliderGlassConfig.releaseDuration,
            delay: 0,
            usingSpringWithDamping: SliderGlassConfig.springDamping,
            initialSpringVelocity: SliderGlassConfig.springVelocity,
            options: [.allowUserInteraction],
            animations: {
                self.knobContainer.transform = .identity
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
        specularAnim.toValue = 0.2
        specularAnim.duration = 0.25
        specularAnim.fillMode = .forwards
        specularAnim.isRemovedOnCompletion = false
        glassSpecularLayer.add(specularAnim, forKey: "releaseSpecular")
    }
    
    private func animateSelectionBounce() {
        mediumImpact?.impactOccurred()
        
        UIView.animate(
            withDuration: 0.15,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                self.knobContainer.transform = CGAffineTransform(
                    scaleX: SliderGlassConfig.bounceScale,
                    y: SliderGlassConfig.bounceScale
                )
            }
        ) { _ in
            UIView.animate(
                withDuration: SliderGlassConfig.releaseDuration,
                delay: 0,
                usingSpringWithDamping: SliderGlassConfig.springDamping,
                initialSpringVelocity: SliderGlassConfig.springVelocity,
                options: [],
                animations: {
                    self.knobContainer.transform = .identity
                }
            )
        }
    }
    
    private func applyMorphingStretch(velocity: CGPoint) {
        let stretchFactor: CGFloat = 0.0003
        let maxStretch: CGFloat = 0.1
        
        let stretchX = min(abs(velocity.x) * stretchFactor, maxStretch)
        let stretchY = stretchX * 0.5
        
        let scaleX = SliderGlassConfig.pressedScale + stretchX
        let scaleY = SliderGlassConfig.pressedScale - stretchY
        
        UIView.animate(withDuration: 0.08, delay: 0, options: [.curveLinear, .allowUserInteraction]) {
            self.knobContainer.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        }
    }
    
    // MARK: - Hit Testing
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = bounds.insetBy(dx: -hitAreaExpansion, dy: -hitAreaExpansion)
        return expandedBounds.contains(point)
    }
}

// MARK: - SliderComponent

public final class SliderComponent: Component {
    public final class Discrete: Equatable {
        public let valueCount: Int
        public let value: Int
        public let minValue: Int?
        public let markPositions: Bool
        public let valueUpdated: (Int) -> Void
        
        public init(valueCount: Int, value: Int, minValue: Int? = nil, markPositions: Bool, valueUpdated: @escaping (Int) -> Void) {
            self.valueCount = valueCount
            self.value = value
            self.minValue = minValue
            self.markPositions = markPositions
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Discrete, rhs: Discrete) -> Bool {
            if lhs.valueCount != rhs.valueCount {
                return false
            }
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            if lhs.markPositions != rhs.markPositions {
                return false
            }
            return true
        }
    }
    
    public final class Continuous: Equatable {
        public let value: CGFloat
        public let minValue: CGFloat?
        public let valueUpdated: (CGFloat) -> Void
        
        public init(value: CGFloat, minValue: CGFloat? = nil, valueUpdated: @escaping (CGFloat) -> Void) {
            self.value = value
            self.minValue = minValue
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Continuous, rhs: Continuous) -> Bool {
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            return true
        }
    }
    
    public enum Content: Equatable {
        case discrete(Discrete)
        case continuous(Continuous)
    }
    
    public let content: Content
    public let useNative: Bool
    public let trackBackgroundColor: UIColor
    public let trackForegroundColor: UIColor
    public let minTrackForegroundColor: UIColor?
    public let knobSize: CGFloat?
    public let knobColor: UIColor?
    public let isTrackingUpdated: ((Bool) -> Void)?
    
    public init(
        content: Content,
        useNative: Bool = false,
        trackBackgroundColor: UIColor,
        trackForegroundColor: UIColor,
        minTrackForegroundColor: UIColor? = nil,
        knobSize: CGFloat? = nil,
        knobColor: UIColor? = nil,
        isTrackingUpdated: ((Bool) -> Void)? = nil
    ) {
        self.content = content
        self.useNative = useNative
        self.trackBackgroundColor = trackBackgroundColor
        self.trackForegroundColor = trackForegroundColor
        self.minTrackForegroundColor = minTrackForegroundColor
        self.knobSize = knobSize
        self.knobColor = knobColor
        self.isTrackingUpdated = isTrackingUpdated
    }
    
    public static func ==(lhs: SliderComponent, rhs: SliderComponent) -> Bool {
        if lhs.content != rhs.content {
            return false
        }
        if lhs.trackBackgroundColor != rhs.trackBackgroundColor {
            return false
        }
        if lhs.trackForegroundColor != rhs.trackForegroundColor {
            return false
        }
        if lhs.minTrackForegroundColor != rhs.minTrackForegroundColor {
            return false
        }
        if lhs.knobSize != rhs.knobSize {
            return false
        }
        if lhs.knobColor != rhs.knobColor {
            return false
        }
        return true
    }
    
    public final class View: UIView {
        // CHANGED: Use LiquidGlassSliderView for custom glass effects
        private var liquidGlassSliderView: LiquidGlassSliderView?
        
        // Keep legacy views for iOS 26+ native support
        private var nativeSliderView: UISlider?
        private var legacySliderView: TGPhotoEditorSliderView?
        
        private var component: SliderComponent?
        private weak var state: EmptyComponentState?
        
        public var hitTestTarget: UIView? {
            return self.liquidGlassSliderView ?? self.legacySliderView
        }
        
        override public init(frame: CGRect) {
            super.init(frame: frame)
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
                
        public func cancelGestures() {
            if let sliderView = self.liquidGlassSliderView, let gestureRecognizers = sliderView.gestureRecognizers {
                for gestureRecognizer in gestureRecognizers {
                    if gestureRecognizer.isEnabled {
                        gestureRecognizer.isEnabled = false
                        gestureRecognizer.isEnabled = true
                    }
                }
            }
        }
        
        func update(component: SliderComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state
            
            let size = CGSize(width: availableSize.width, height: 44.0)
            
            // Use native slider for iOS 26+ if requested
            if #available(iOS 26.0, *), component.useNative {
                // Keep original native implementation
                let sliderView: UISlider
                if let current = self.nativeSliderView {
                    sliderView = current
                } else {
                    sliderView = UISlider()
                    sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    self.addSubview(sliderView)
                    self.nativeSliderView = sliderView
                    
                    switch component.content {
                    case let .continuous(continuous):
                        sliderView.minimumValue = Float(continuous.minValue ?? 0.0)
                        sliderView.maximumValue = 1.0
                    case let .discrete(discrete):
                        sliderView.minimumValue = 0.0
                        sliderView.maximumValue = Float(discrete.valueCount - 1)
                    }
                }
                switch component.content {
                case let .continuous(continuous):
                    sliderView.value = Float(continuous.value)
                case let .discrete(discrete):
                    sliderView.value = Float(discrete.value)
                }
                sliderView.minimumTrackTintColor = component.trackForegroundColor
                sliderView.maximumTrackTintColor = component.trackBackgroundColor
                
                transition.setFrame(view: sliderView, frame: CGRect(origin: .zero, size: size))
            } else {
                // USE LIQUID GLASS SLIDER
                let sliderView: LiquidGlassSliderView
                if let current = self.liquidGlassSliderView {
                    sliderView = current
                } else {
                    sliderView = LiquidGlassSliderView()
                    sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    self.addSubview(sliderView)
                    self.liquidGlassSliderView = sliderView
                }
                
                // Configure
                sliderView.trackBackgroundColor = component.trackBackgroundColor
                sliderView.trackForegroundColor = component.trackForegroundColor
                sliderView.knobColor = component.knobColor
                if let knobSize = component.knobSize {
                    sliderView.knobSize = knobSize
                }
                
                switch component.content {
                case let .discrete(discrete):
                    sliderView.minimumValue = 0
                    sliderView.maximumValue = CGFloat(discrete.valueCount - 1)
                    sliderView.value = CGFloat(discrete.value)
                    sliderView.isDiscrete = true
                    sliderView.discreteValueCount = discrete.valueCount
                    sliderView.markPositions = discrete.markPositions
                case let .continuous(continuous):
                    sliderView.minimumValue = continuous.minValue ?? 0
                    sliderView.maximumValue = 1.0
                    sliderView.value = continuous.value
                    sliderView.isDiscrete = false
                }
                
                // Callbacks
                sliderView.interactionBegan = { [weak self] in
                    self?.component?.isTrackingUpdated?(true)
                }
                sliderView.interactionEnded = { [weak self] in
                    self?.component?.isTrackingUpdated?(false)
                }
                
                transition.setFrame(view: sliderView, frame: CGRect(origin: .zero, size: size))
            }
            
            return size
        }
        
        @objc private func sliderValueChanged() {
            guard let component = self.component else { return }
            
            let floatValue: CGFloat
            if let sliderView = self.liquidGlassSliderView {
                floatValue = sliderView.value
            } else if let nativeSliderView = self.nativeSliderView {
                floatValue = CGFloat(nativeSliderView.value)
            } else {
                return
            }
            
            switch component.content {
            case let .discrete(discrete):
                discrete.valueUpdated(Int(floatValue))
            case let .continuous(continuous):
                continuous.valueUpdated(floatValue)
            }
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}