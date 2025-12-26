import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import Display
import UIKitRuntimeUtils
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import TelegramPresentationData

private extension CGRect {
    var center: CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
}

// MARK: - Liquid Glass Configuration

private struct LiquidGlassConfiguration {
    var cornerRadius: CGFloat
    var tintColor: UIColor
    var tintOpacity: CGFloat
    var specularIntensity: CGFloat
    var borderWidth: CGFloat
    var borderColor: UIColor
    
    static let tabBarItem = LiquidGlassConfiguration(
        cornerRadius: 18,
        tintColor: UIColor.white.withAlphaComponent(0.08),
        tintOpacity: 0.12,
        specularIntensity: 0.25,
        borderWidth: 0.33,
        borderColor: UIColor.white.withAlphaComponent(0.2)
    )
    
    static let selectionIndicator = LiquidGlassConfiguration(
        cornerRadius: 20,
        tintColor: UIColor.white.withAlphaComponent(0.12),
        tintOpacity: 0.18,
        specularIntensity: 0.35,
        borderWidth: 0.5,
        borderColor: UIColor.white.withAlphaComponent(0.3)
    )
}

// MARK: - Liquid Glass Animation Configuration

private struct LiquidGlassAnimationConfiguration {
    /// Scale factor when pressed (92% as per contest spec)
    let pressedScale: CGFloat = 0.92
    
    /// Duration of the press-down animation (0.12s as per contest spec)
    let pressDownDuration: TimeInterval = 0.12
    
    /// Scale factor for selection bounce (110% as per contest spec)
    let selectionBounceScale: CGFloat = 1.10
    
    /// Damping ratio for spring animations (0.65 as per contest spec)
    let springDamping: CGFloat = 0.65
    
    /// Initial spring velocity
    let springVelocity: CGFloat = 0.5
    
    /// Duration of the release/bounce animation
    let releaseDuration: TimeInterval = 0.4
    
    static let standard = LiquidGlassAnimationConfiguration()
}

// MARK: - Liquid Glass Layer

private class LiquidGlassLayer: CALayer {
    
    private var glassBackgroundLayer: CALayer?
    private var specularHighlightLayer: CAGradientLayer?
    private var borderLayer: CAShapeLayer?
    
    private var configuration: LiquidGlassConfiguration = .tabBarItem
    
    override init() {
        super.init()
        setupLayers()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        if let glassLayer = layer as? LiquidGlassLayer {
            self.configuration = glassLayer.configuration
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        let background = CALayer()
        background.backgroundColor = UIColor.white.withAlphaComponent(0.05).cgColor
        self.glassBackgroundLayer = background
        addSublayer(background)
        
        let specular = CAGradientLayer()
        specular.colors = [
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0.08).cgColor,
            UIColor.clear.cgColor
        ]
        specular.locations = [0.0, 0.25, 1.0]
        specular.startPoint = CGPoint(x: 0.5, y: 0)
        specular.endPoint = CGPoint(x: 0.5, y: 1)
        self.specularHighlightLayer = specular
        addSublayer(specular)
        
        let border = CAShapeLayer()
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        border.lineWidth = 0.5
        self.borderLayer = border
        addSublayer(border)
    }
    
    func configure(with config: LiquidGlassConfiguration) {
        self.configuration = config
        
        cornerRadius = config.cornerRadius
        masksToBounds = true
        
        glassBackgroundLayer?.backgroundColor = config.tintColor.withAlphaComponent(config.tintOpacity).cgColor
        glassBackgroundLayer?.cornerRadius = config.cornerRadius
        
        specularHighlightLayer?.cornerRadius = config.cornerRadius
        specularHighlightLayer?.opacity = Float(config.specularIntensity)
        
        borderLayer?.strokeColor = config.borderColor.cgColor
        borderLayer?.lineWidth = config.borderWidth
        
        setNeedsLayout()
    }
    
    override func layoutSublayers() {
        super.layoutSublayers()
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let bounds = self.bounds
        
        glassBackgroundLayer?.frame = bounds
        specularHighlightLayer?.frame = bounds
        
        let borderPath = UIBezierPath(roundedRect: bounds.insetBy(dx: configuration.borderWidth / 2, dy: configuration.borderWidth / 2), cornerRadius: configuration.cornerRadius)
        borderLayer?.path = borderPath.cgPath
        borderLayer?.frame = bounds
        
        CATransaction.commit()
    }
    
    func animateHighlight(_ highlighted: Bool, animated: Bool = true) {
        let targetOpacity: Float = highlighted ? Float(configuration.specularIntensity * 1.6) : Float(configuration.specularIntensity)
        let targetBackgroundAlpha: CGFloat = highlighted ? configuration.tintOpacity * 2.0 : configuration.tintOpacity
        
        if animated {
            let duration: TimeInterval = highlighted ? 0.08 : 0.25
            
            let opacityAnimation = CABasicAnimation(keyPath: "opacity")
            opacityAnimation.toValue = targetOpacity
            opacityAnimation.duration = duration
            opacityAnimation.fillMode = .forwards
            opacityAnimation.isRemovedOnCompletion = false
            specularHighlightLayer?.add(opacityAnimation, forKey: "highlightOpacity")
            
            let backgroundAnimation = CABasicAnimation(keyPath: "backgroundColor")
            backgroundAnimation.toValue = configuration.tintColor.withAlphaComponent(targetBackgroundAlpha).cgColor
            backgroundAnimation.duration = duration
            backgroundAnimation.fillMode = .forwards
            backgroundAnimation.isRemovedOnCompletion = false
            glassBackgroundLayer?.add(backgroundAnimation, forKey: "highlightBackground")
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            specularHighlightLayer?.opacity = targetOpacity
            glassBackgroundLayer?.backgroundColor = configuration.tintColor.withAlphaComponent(targetBackgroundAlpha).cgColor
            CATransaction.commit()
        }
    }
}

// MARK: - Helper Functions

private let separatorHeight: CGFloat = 1.0 / UIScreen.main.scale

private func tabBarItemImage(_ image: UIImage?, title: String, backgroundColor: UIColor, tintColor: UIColor, horizontal: Bool, imageMode: Bool, centered: Bool = false) -> (UIImage, CGFloat) {
    let font = horizontal ? Font.regular(13.0) : Font.medium(10.0)
    let titleSize = (title as NSString).boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [NSAttributedString.Key.font: font], context: nil).size
    
    let imageSize: CGSize
    if let image = image {
        if horizontal {
            let factor: CGFloat = 0.8
            imageSize = CGSize(width: floor(image.size.width * factor), height: floor(image.size.height * factor))
        } else {
            imageSize = image.size
        }
    } else {
        imageSize = CGSize()
    }
    
    let horizontalSpacing: CGFloat = 4.0
    
    let size: CGSize
    let contentWidth: CGFloat
    if horizontal {
        let width = max(1.0, centered ? imageSize.width : ceil(titleSize.width) + horizontalSpacing + imageSize.width)
        size = CGSize(width: width, height: 34.0)
        contentWidth = size.width
    } else {
        let width = max(1.0, centered ? imageSize.width : max(ceil(titleSize.width), imageSize.width), 1.0)
        size = CGSize(width: width, height: 45.0)
        contentWidth = imageSize.width
    }
    
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    if let context = UIGraphicsGetCurrentContext() {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: CGPoint(), size: size))
        
        if let image = image, imageMode {
            let imageRect: CGRect
            if horizontal {
                imageRect = CGRect(origin: CGPoint(x: 0.0, y: floor((size.height - imageSize.height) / 2.0)), size: imageSize)
            } else {
                imageRect = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - imageSize.width) / 2.0), y: centered ? floor((size.height - imageSize.height) / 2.0) : 0.0), size: imageSize)
            }
            context.saveGState()
            context.translateBy(x: imageRect.midX, y: imageRect.midY)
            context.scaleBy(x: 1.0, y: -1.0)
            context.translateBy(x: -imageRect.midX, y: -imageRect.midY)
            if image.renderingMode == .alwaysOriginal {
                context.draw(image.cgImage!, in: imageRect)
            } else {
                context.clip(to: imageRect, mask: image.cgImage!)
                context.setFillColor(tintColor.cgColor)
                context.fill(imageRect)
            }
            context.restoreGState()
        }
    }
    
    if !imageMode {
        if horizontal {
            (title as NSString).draw(at: CGPoint(x: imageSize.width + horizontalSpacing, y: floor((size.height - titleSize.height) / 2.0)), withAttributes: [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: tintColor])
        } else {
            (title as NSString).draw(at: CGPoint(x: floorToScreenPixels((size.width - titleSize.width) / 2.0), y: size.height - titleSize.height - 1.0), withAttributes: [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: tintColor])
        }
    }
    
    let resultImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return (resultImage!, contentWidth)
}

private let badgeFont = Font.regular(13.0)

// MARK: - Tab Bar Item Node

private final class TabBarItemNode: ASDisplayNode {
    let extractedContainerNode: ContextExtractedContentContainingNode
    let containerNode: ContextControllerSourceNode
    let imageNode: ASImageNode
    let animationContainerNode: ASDisplayNode
    let animationNode: AnimatedStickerNode
    let textImageNode: ASImageNode
    let contextImageNode: ASImageNode
    let contextTextImageNode: ASImageNode
    var contentWidth: CGFloat?
    var isSelected: Bool = false {
        didSet {
            if isSelected != oldValue {
                updateGlassLensState(animated: true)
            }
        }
    }
    
    let ringImageNode: ASImageNode
    var ringColor: UIColor? {
        didSet {
            if let ringColor = self.ringColor {
                self.ringImageNode.image = generateCircleImage(diameter: 29.0, lineWidth: 1.0, color: ringColor, backgroundColor: nil)
            } else {
                self.ringImageNode.image = nil
            }
        }
    }
    
    // MARK: - Liquid Glass Properties
    

    private var glassLensLayer: LiquidGlassLayer?
    private var blurView: UIVisualEffectView?
    private var pressHighlightLayer: CALayer?
    private var isPressed: Bool = false
    private let glassAnimConfig = LiquidGlassAnimationConfiguration.standard
    private var lastTouchLocation: CGPoint?
    private var lastTouchTime: TimeInterval?
    
    var swiped: ((TabBarItemSwipeDirection) -> Void)?
    
    var pointerInteraction: PointerInteraction?
    
    override init() {
        self.extractedContainerNode = ContextExtractedContentContainingNode()
        self.containerNode = ContextControllerSourceNode()
        
        self.ringImageNode = ASImageNode()
        self.ringImageNode.isUserInteractionEnabled = false
        self.ringImageNode.displayWithoutProcessing = true
        self.ringImageNode.displaysAsynchronously = false
        
        self.imageNode = ASImageNode()
        self.imageNode.isUserInteractionEnabled = false
        self.imageNode.displayWithoutProcessing = true
        self.imageNode.displaysAsynchronously = false
        self.imageNode.isAccessibilityElement = false
        
        self.animationContainerNode = ASDisplayNode()
        
        self.animationNode = DefaultAnimatedStickerNodeImpl()
        self.animationNode.autoplay = true
        self.animationNode.automaticallyLoadLastFrame = true
        
        self.textImageNode = ASImageNode()
        self.textImageNode.isUserInteractionEnabled = false
        self.textImageNode.displayWithoutProcessing = true
        self.textImageNode.displaysAsynchronously = false
        self.textImageNode.isAccessibilityElement = false
        
        self.contextImageNode = ASImageNode()
        self.contextImageNode.isUserInteractionEnabled = false
        self.contextImageNode.displayWithoutProcessing = true
        self.contextImageNode.displaysAsynchronously = false
        self.contextImageNode.isAccessibilityElement = false
        self.contextImageNode.alpha = 0.0
        self.contextTextImageNode = ASImageNode()
        self.contextTextImageNode.isUserInteractionEnabled = false
        self.contextTextImageNode.displayWithoutProcessing = true
        self.contextTextImageNode.displaysAsynchronously = false
        self.contextTextImageNode.isAccessibilityElement = false
        self.contextTextImageNode.alpha = 0.0
        
        super.init()
        
        self.isAccessibilityElement = true
        
        self.extractedContainerNode.contentNode.addSubnode(self.ringImageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.textImageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.imageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.animationContainerNode)
        self.animationContainerNode.addSubnode(self.animationNode)
        self.extractedContainerNode.contentNode.addSubnode(self.contextTextImageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.contextImageNode)
        self.containerNode.addSubnode(self.extractedContainerNode)
        self.containerNode.targetNodeForActivationProgress = self.extractedContainerNode.contentNode
        self.addSubnode(self.containerNode)
        
        self.extractedContainerNode.willUpdateIsExtractedToContextPreview = { [weak self] isExtracted, transition in
            guard let strongSelf = self else {
                return
            }
            transition.updateAlpha(node: strongSelf.ringImageNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.imageNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.animationNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.textImageNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.contextImageNode, alpha: isExtracted ? 1.0 : 0.0)
            transition.updateAlpha(node: strongSelf.contextTextImageNode, alpha: isExtracted ? 1.0 : 0.0)
            
            // Hide glass lens when extracting to context menu
            if let glassLayer = strongSelf.glassLensLayer {
                let targetOpacity: Float = isExtracted ? 0.0 : (strongSelf.isSelected ? 1.0 : 0.0)
                if transition.isAnimated {
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.fromValue = glassLayer.presentation()?.opacity ?? glassLayer.opacity
                    animation.toValue = targetOpacity
                    animation.duration = 0.2
                    animation.fillMode = .forwards
                    animation.isRemovedOnCompletion = false
                    glassLayer.add(animation, forKey: "extractionOpacity")
                } else {
                    glassLayer.opacity = targetOpacity
                }
            }
        }
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.pointerInteraction = PointerInteraction(node: self, style: .rectangle(CGSize(width: 90.0, height: 50.0)))
        
        setupGlassLens()
    }
    
    // MARK: - Liquid Glass Setup
    
private func setupGlassLens() {
    // 1. Create the Blur (The actual glass body)
    // .systemUltraThinMaterial creates that "frosted" look
    let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.layer.cornerRadius = LiquidGlassConfiguration.tabBarItem.cornerRadius
    blurView.clipsToBounds = true
    blurView.isUserInteractionEnabled = false
    blurView.alpha = 0 // Hidden until selected
    
    // Insert at index 0 so it sits BEHIND the icon
    self.view.insertSubview(blurView, at: 0)
    self.blurView = blurView

    // 2. Create the Specular Layer (The shine)
    let lens = LiquidGlassLayer()
    lens.configure(with: .tabBarItem)
    lens.opacity = 0 
    // Place the shine ON TOP of the blur
    layer.insertSublayer(lens, above: blurView.layer)
    self.glassLensLayer = lens
    
    // Create press highlight layer
    let highlight = CALayer()
    highlight.backgroundColor = UIColor.white.withAlphaComponent(0.25).cgColor
    highlight.cornerRadius = LiquidGlassConfiguration.tabBarItem.cornerRadius
    highlight.opacity = 0
    layer.insertSublayer(highlight, above: lens)
    self.pressHighlightLayer = highlight
}
    
    override func layout() {
    super.layout()
    
    let bounds = self.bounds
    // Inset slightly so it looks like a pill button
    let lensFrame = bounds.insetBy(dx: 4, dy: 2)
    
    // Update the Blur Frame
    blurView?.frame = lensFrame
    
    // Update the Shine Frame
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    glassLensLayer?.frame = lensFrame
    pressHighlightLayer?.frame = lensFrame
    CATransaction.commit()
}
    
    private func updateGlassLensFrame() {
        let bounds = self.bounds
        let insetX: CGFloat = 4
        let insetY: CGFloat = 2
        let lensFrame = bounds.insetBy(dx: insetX, dy: insetY)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        glassLensLayer?.frame = lensFrame
        pressHighlightLayer?.frame = lensFrame
        
        CATransaction.commit()
    }
    

    
   override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    isPressed = true
    
    if let touch = touches.first {
        lastTouchLocation = touch.location(in: self.view)
        lastTouchTime = CACurrentMediaTime()
    }
    animateGlassPressDown()
}

override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    
    guard let touch = touches.first, 
          let lastLoc = lastTouchLocation, 
          let lastTime = lastTouchTime else { return }
    
    let currentLocation = touch.location(in: self.view)
    let currentTime = CACurrentMediaTime()
    let timeDelta = currentTime - lastTime
    
    // Calculate velocity (pixels per second)
    if timeDelta > 0 {
        let velX = (currentLocation.x - lastLoc.x) / CGFloat(timeDelta)
        
        // STRETCH FORMULA:
        // High divisor = stiffer jelly. 
        let stretchFactor: CGFloat = 0.001 
        
        // If moving right (pos vel), stretch width. If left (neg vel), stretch width.
        let scaleX = 1.0 + (abs(velX) * stretchFactor)
        // Conservation of volume: if it gets wider, it must get shorter
        let scaleY = 1.0 - (abs(velX) * stretchFactor * 0.5) 
        
        // Apply the stretch ON TOP of the press scale (0.92)
        UIView.animate(withDuration: 0.1) {
            self.view.transform = CGAffineTransform(scaleX: 0.92 * scaleX, y: 0.92 * scaleY)
        }
    }
    
    lastTouchLocation = currentLocation
    lastTouchTime = currentTime
}

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if isPressed {
            isPressed = false
            animateGlassRelease()
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if isPressed {
            isPressed = false
            animateGlassRelease()
        }
    }
    
    // MARK: - Liquid Glass Animations
    
    /// Animates the press-down state: 92% scale in 0.12s
    private func animateGlassPressDown() {
        let config = glassAnimConfig
        
        // Scale down to 92% as per contest spec
        UIView.animate(
            withDuration: config.pressDownDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.view.transform = CGAffineTransform(scaleX: config.pressedScale, y: config.pressedScale)
            }
        )
        
        // Show highlight on glass lens
        let highlightAnim = CABasicAnimation(keyPath: "opacity")
        highlightAnim.fromValue = 0
        highlightAnim.toValue = 1
        highlightAnim.duration = config.pressDownDuration
        highlightAnim.fillMode = .forwards
        highlightAnim.isRemovedOnCompletion = false
        highlightAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pressHighlightLayer?.add(highlightAnim, forKey: "pressHighlight")
        
        // Enhance glass specular
        glassLensLayer?.animateHighlight(true)
        
        // Haptic feedback
        if #available(iOS 10.0, *) {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    /// Animates the release state with spring bounce (0.65 damping)
    private func animateGlassRelease() {
        let config = glassAnimConfig
        
        // Spring bounce back with 0.65 damping as per spec
        UIView.animate(
            withDuration: config.releaseDuration,
            delay: 0,
            usingSpringWithDamping: config.springDamping,
            initialSpringVelocity: config.springVelocity,
            options: [.allowUserInteraction],
            animations: {
                self.view.transform = .identity
            }
        )
        
        // Hide highlight
        let hideAnim = CABasicAnimation(keyPath: "opacity")
        hideAnim.fromValue = pressHighlightLayer?.presentation()?.opacity ?? 1
        hideAnim.toValue = 0
        hideAnim.duration = 0.25
        hideAnim.fillMode = .forwards
        hideAnim.isRemovedOnCompletion = false
        hideAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        pressHighlightLayer?.add(hideAnim, forKey: "hideHighlight")
        
        // Remove glass highlight
        glassLensLayer?.animateHighlight(false)
    }
    
    /// Animates selection with bounce: 110% scale then spring back
    func animateSelectionBounce() {
        let config = glassAnimConfig
        
        // Bounce up to 110% as per contest spec
        UIView.animate(
            withDuration: 0.15,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                self.view.transform = CGAffineTransform(scaleX: config.selectionBounceScale, y: config.selectionBounceScale)
            }
        ) { _ in
            UIView.animate(
                withDuration: config.releaseDuration,
                delay: 0,
                usingSpringWithDamping: config.springDamping,
                initialSpringVelocity: config.springVelocity,
                options: [],
                animations: {
                    self.view.transform = .identity
                }
            )
        }
        
        // Haptic feedback
        if #available(iOS 10.0, *) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
   private func updateGlassLensState(animated: Bool) {
    let targetOpacity: Float = isSelected ? 1.0 : 0.0
    let targetAlpha: CGFloat = isSelected ? 1.0 : 0.0 // Blur alpha
    
    if animated {
        // Animate Shine
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = glassLensLayer?.presentation()?.opacity ?? (isSelected ? 0.0 : 1.0)
        animation.toValue = targetOpacity
        animation.duration = 0.25
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        glassLensLayer?.add(animation, forKey: "glassVisibility")
        
        // Animate Blur
        UIView.animate(withDuration: 0.25) {
            self.blurView?.alpha = targetAlpha
        }
    } else {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glassLensLayer?.opacity = targetOpacity
        CATransaction.commit()
        
        self.blurView?.alpha = targetAlpha
    }
}

    @objc private func swipeGesture(_ gesture: UISwipeGestureRecognizer) {
        if case .ended = gesture.state {
            self.containerNode.cancelGesture()
            
            switch gesture.direction {
            case .left:
                self.swiped?(.left)
            default:
                self.swiped?(.right)
            }
        }
    }
}

// MARK: - Tab Bar Node Container

private final class TabBarNodeContainer {
    let item: UITabBarItem
    let updateBadgeListenerIndex: Int
    let updateTitleListenerIndex: Int
    let updateImageListenerIndex: Int
    let updateSelectedImageListenerIndex: Int
    
    let imageNode: TabBarItemNode
    let badgeContainerNode: ASDisplayNode
    let badgeBackgroundNode: ASImageNode
    let badgeTextNode: ImmediateTextNode
    
    var badgeValue: String?
    var appliedBadgeValue: String?
    
    var titleValue: String?
    var appliedTitleValue: String?
    
    var imageValue: UIImage?
    var appliedImageValue: UIImage?
    
    var selectedImageValue: UIImage?
    var appliedSelectedImageValue: UIImage?
    
    init(item: TabBarNodeItem, imageNode: TabBarItemNode, updateBadge: @escaping (String) -> Void, updateTitle: @escaping (String, Bool) -> Void, updateImage: @escaping (UIImage?) -> Void, updateSelectedImage: @escaping (UIImage?) -> Void, contextAction: @escaping (ContextExtractedContentContainingNode, ContextGesture) -> Void, swipeAction: @escaping (TabBarItemSwipeDirection) -> Void) {
        self.item = item.item
        
        self.imageNode = imageNode
        self.imageNode.isAccessibilityElement = true
        self.imageNode.accessibilityTraits = .button
        
        self.badgeContainerNode = ASDisplayNode()
        self.badgeContainerNode.isUserInteractionEnabled = false
        self.badgeContainerNode.isAccessibilityElement = false
        
        self.badgeBackgroundNode = ASImageNode()
        self.badgeBackgroundNode.isUserInteractionEnabled = false
        self.badgeBackgroundNode.displayWithoutProcessing = true
        self.badgeBackgroundNode.displaysAsynchronously = false
        self.badgeBackgroundNode.isAccessibilityElement = false
        
        self.badgeTextNode = ImmediateTextNode()
        self.badgeTextNode.maximumNumberOfLines = 1
        self.badgeTextNode.isUserInteractionEnabled = false
        self.badgeTextNode.displaysAsynchronously = false
        self.badgeTextNode.isAccessibilityElement = false
        
        self.badgeContainerNode.addSubnode(self.badgeBackgroundNode)
        self.badgeContainerNode.addSubnode(self.badgeTextNode)
        
        self.badgeValue = item.item.badgeValue ?? ""
        self.updateBadgeListenerIndex = UITabBarItem_addSetBadgeListener(item.item, { value in
            updateBadge(value ?? "")
        })
        
        self.titleValue = item.item.title
        self.updateTitleListenerIndex = item.item.addSetTitleListener { value, animated in
            updateTitle(value ?? "", animated)
        }
        
        self.imageValue = item.item.image
        self.updateImageListenerIndex = item.item.addSetImageListener { value in
            updateImage(value)
        }
        
        self.selectedImageValue = item.item.selectedImage
        self.updateSelectedImageListenerIndex = item.item.addSetSelectedImageListener { value in
            updateSelectedImage(value)
        }
        
        imageNode.containerNode.activated = { [weak self] gesture, _ in
            guard let strongSelf = self else {
                return
            }
            contextAction(strongSelf.imageNode.extractedContainerNode, gesture)
        }
        imageNode.swiped = { [weak imageNode] direction in
            guard let imageNode = imageNode, imageNode.isSelected else {
                return
            }
            swipeAction(direction)
        }
        imageNode.containerNode.isGestureEnabled = item.contextActionType != .none
        let contextActionType = item.contextActionType
        imageNode.containerNode.shouldBegin = { [weak imageNode] _ in
            switch contextActionType {
            case .none:
                return false
            case .always:
                return true
            case .whenActive:
                return imageNode?.isSelected ?? false
            }
        }
    }
    
    deinit {
        self.item.removeSetBadgeListener(self.updateBadgeListenerIndex)
        self.item.removeSetTitleListener(self.updateTitleListenerIndex)
        self.item.removeSetImageListener(self.updateImageListenerIndex)
        self.item.removeSetSelectedImageListener(self.updateSelectedImageListenerIndex)
    }
}

// MARK: - Tab Bar Node Item

final class TabBarNodeItem {
    let item: UITabBarItem
    let contextActionType: TabBarItemContextActionType
    
    init(item: UITabBarItem, contextActionType: TabBarItemContextActionType) {
        self.item = item
        self.contextActionType = contextActionType
    }
}

// MARK: - Tab Bar Node

class TabBarNode: ASDisplayNode, ASGestureRecognizerDelegate {
    var tabBarItems: [TabBarNodeItem] = [] {
        didSet {
            self.reloadTabBarItems()
        }
    }
    
    var reduceMotion: Bool = false
    
    var selectedIndex: Int? {
        didSet {
            if self.selectedIndex != oldValue {
                if let oldValue = oldValue {
                    self.updateNodeImage(oldValue, layout: true)
                }
                
                if let selectedIndex = self.selectedIndex {
                    self.updateNodeImage(selectedIndex, layout: true)
                    
                    // Trigger selection bounce animation
                    if selectedIndex < tabBarNodeContainers.count && !self.reduceMotion {
                        tabBarNodeContainers[selectedIndex].imageNode.animateSelectionBounce()
                    }
                }
                
                // Update selection indicator position
                updateSelectionIndicatorPosition(animated: oldValue != nil)
            }
        }
    }
    
    private let itemSelected: (Int, Bool, [ASDisplayNode]) -> Void
    private let contextAction: (Int, ContextExtractedContentContainingNode, ContextGesture) -> Void
    private let swipeAction: (Int, TabBarItemSwipeDirection) -> Void
    
    private var theme: PresentationTheme
    private var validLayout: (CGSize, CGFloat, CGFloat, UIEdgeInsets, CGFloat)?
    private var horizontal: Bool = false
    private var centered: Bool = false
    
    private var badgeImage: UIImage
    
    /// Selection indicator glass layer
    private var selectionGlassLayer: LiquidGlassLayer?
    
    // ============================================================
    // CRITICAL FIX: Use ASDisplayNode instead of NavigationBackgroundNode
    // NavigationBackgroundNode adds blur which violates contest rule:
    // "Omit background blur behind the bar itself"
    // ============================================================
    let backgroundNode: ASDisplayNode
    
    private var tabBarNodeContainers: [TabBarNodeContainer] = []
    
    private var tapRecognizer: TapLongTapOrDoubleTapGestureRecognizer?
    
    init(theme: PresentationTheme, itemSelected: @escaping (Int, Bool, [ASDisplayNode]) -> Void, contextAction: @escaping (Int, ContextExtractedContentContainingNode, ContextGesture) -> Void, swipeAction: @escaping (Int, TabBarItemSwipeDirection) -> Void) {
        self.itemSelected = itemSelected
        self.contextAction = contextAction
        self.swipeAction = swipeAction
        self.theme = theme
        
        // ============================================================
        // CRITICAL FIX: Use plain ASDisplayNode for background
        // This ensures NO blur behind the tab bar (contest requirement)
        // ============================================================
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.backgroundColor = theme.rootController.tabBar.backgroundColor
        self.backgroundNode.isLayerBacked = true // Performance optimization
        
        self.badgeImage = generateStretchableFilledCircleImage(diameter: 18.0, color: theme.rootController.tabBar.badgeBackgroundColor, strokeColor: theme.rootController.tabBar.badgeStrokeColor, strokeWidth: 1.0, backgroundColor: nil)!
        
        super.init()
        
        self.isAccessibilityContainer = false
        self.accessibilityTraits = [.tabBar]
        
        self.isOpaque = false
        self.backgroundColor = nil
        
        self.isExclusiveTouch = true
        
        self.addSubnode(self.backgroundNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        let recognizer = TapLongTapOrDoubleTapGestureRecognizer(target: self, action: #selector(self.tapLongTapOrDoubleTapGesture(_:)))
        recognizer.delegate = self.wrappedGestureRecognizerDelegate
        recognizer.tapActionAtPoint = { _ in
            return .keepWithSingleTap
        }
        self.tapRecognizer = recognizer
        self.view.addGestureRecognizer(recognizer)
        
        setupSelectionIndicator()
    }
    
    private func setupSelectionIndicator() {
        let selectionLayer = LiquidGlassLayer()
        selectionLayer.configure(with: .selectionIndicator)
        selectionLayer.opacity = 0.5
        layer.insertSublayer(selectionLayer, above: backgroundNode.layer)
        self.selectionGlassLayer = selectionLayer
    }
    
    private func updateSelectionIndicatorPosition(animated: Bool) {
        guard let selectedIndex = selectedIndex,
              selectedIndex < tabBarNodeContainers.count,
              let selectionLayer = selectionGlassLayer else { return }
        
        let selectedNode = tabBarNodeContainers[selectedIndex].imageNode
        let nodeFrame = selectedNode.frame
        let indicatorFrame = nodeFrame.insetBy(dx: 2, dy: 0)
        
        if animated {
            let positionAnimation = CASpringAnimation(keyPath: "position")
            positionAnimation.fromValue = selectionLayer.presentation()?.position ?? selectionLayer.position
            positionAnimation.toValue = CGPoint(x: indicatorFrame.midX, y: indicatorFrame.midY)
            positionAnimation.damping = 15
            positionAnimation.initialVelocity = 5
            positionAnimation.duration = 0.5
            positionAnimation.fillMode = .forwards
            positionAnimation.isRemovedOnCompletion = false
            
            let boundsAnimation = CASpringAnimation(keyPath: "bounds")
            boundsAnimation.fromValue = selectionLayer.presentation()?.bounds ?? selectionLayer.bounds
            boundsAnimation.toValue = CGRect(origin: .zero, size: indicatorFrame.size)
            boundsAnimation.damping = 15
            boundsAnimation.initialVelocity = 5
            boundsAnimation.duration = 0.5
            boundsAnimation.fillMode = .forwards
            boundsAnimation.isRemovedOnCompletion = false
            
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                selectionLayer.position = CGPoint(x: indicatorFrame.midX, y: indicatorFrame.midY)
                selectionLayer.bounds = CGRect(origin: .zero, size: indicatorFrame.size)
                selectionLayer.removeAnimation(forKey: "selectionPosition")
                selectionLayer.removeAnimation(forKey: "selectionBounds")
            }
            selectionLayer.add(positionAnimation, forKey: "selectionPosition")
            selectionLayer.add(boundsAnimation, forKey: "selectionBounds")
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selectionLayer.position = CGPoint(x: indicatorFrame.midX, y: indicatorFrame.midY)
            selectionLayer.bounds = CGRect(origin: .zero, size: indicatorFrame.size)
            CATransaction.commit()
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        return true
    }
    
    @objc private func tapLongTapOrDoubleTapGesture(_ recognizer: TapLongTapOrDoubleTapGestureRecognizer) {
        switch recognizer.state {
        case .ended:
            if let (gesture, location) = recognizer.lastRecognizedGestureAndLocation {
                if case .tap = gesture {
                    self.tapped(at: location, longTap: false)
                }
            }
        default:
            break
        }
    }
    
    func updateTheme(_ theme: PresentationTheme) {
        if self.theme !== theme {
            self.theme = theme
            
            // FIXED: Direct backgroundColor assignment (ASDisplayNode doesn't have updateColor)
            self.backgroundNode.backgroundColor = theme.rootController.tabBar.backgroundColor
            
            self.badgeImage = generateStretchableFilledCircleImage(diameter: 18.0, color: theme.rootController.tabBar.badgeBackgroundColor, strokeColor: theme.rootController.tabBar.badgeStrokeColor, strokeWidth: 1.0, backgroundColor: nil)!
            for container in self.tabBarNodeContainers {
                if let attributedText = container.badgeTextNode.attributedText, !attributedText.string.isEmpty {
                    container.badgeTextNode.attributedText = NSAttributedString(string: attributedText.string, font: badgeFont, textColor: theme.rootController.tabBar.badgeTextColor)
                }
            }
            
            for i in 0 ..< self.tabBarItems.count {
                self.updateNodeImage(i, layout: false)
                
                self.tabBarNodeContainers[i].badgeBackgroundNode.image = self.badgeImage
            }
            
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
            }
        }
    }
    
    func frameForControllerTab(at index: Int) -> CGRect? {
        guard index >= 0 && index < self.tabBarNodeContainers.count else {
            return nil
        }
        let container = self.tabBarNodeContainers[index]
        return container.imageNode.frame
    }
    
    func viewForControllerTab(at index: Int) -> UIView? {
        guard index >= 0 && index < self.tabBarNodeContainers.count else {
            return nil
        }
        let container = self.tabBarNodeContainers[index]
        return container.imageNode.view
    }
    
    private func reloadTabBarItems() {
        for node in self.tabBarNodeContainers {
            node.imageNode.removeFromSupernode()
        }
        
        self.centered = self.theme.rootController.tabBar.textColor == .clear
        
        var tabBarNodeContainers: [TabBarNodeContainer] = []
        for i in 0 ..< self.tabBarItems.count {
            let item = self.tabBarItems[i]
            let node = TabBarItemNode()
            let container = TabBarNodeContainer(item: item, imageNode: node, updateBadge: { [weak self] value in
                self?.updateNodeBadge(i, value: value)
            }, updateTitle: { [weak self] _, _ in
                self?.updateNodeImage(i, layout: true)
            }, updateImage: { [weak self] _ in
                self?.updateNodeImage(i, layout: true)
            }, updateSelectedImage: { [weak self] _ in
                self?.updateNodeImage(i, layout: true)
            }, contextAction: { [weak self] node, gesture in
                self?.tapRecognizer?.cancel()
                self?.contextAction(i, node, gesture)
            }, swipeAction: { [weak self] direction in
                self?.swipeAction(i, direction)
            })
            if item.item.ringSelection {
                node.ringColor = self.theme.rootController.tabBar.selectedIconColor
            } else {
                node.ringColor = nil
            }
            
            if let selectedIndex = self.selectedIndex, selectedIndex == i {
                let (textImage, contentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.selectedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (image, imageContentWidth): (UIImage, CGFloat)
                
                if let _ = item.item.animationName {
                    (image, imageContentWidth) = (UIImage(), 0.0)
                    
                    node.animationNode.isHidden = false
                    let animationSize: Int = Int(51.0 * UIScreen.main.scale)
                    node.animationNode.visibility = true
                    if !node.isSelected {
                        node.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: item.item.animationName ?? ""), width: animationSize, height: animationSize, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
                    }
                    node.animationNode.setOverlayColor(self.theme.rootController.tabBar.selectedIconColor, replace: true, animated: false)
                    node.animationNode.updateLayout(size: CGSize(width: 51.0, height: 51.0))
                } else {
                    (image, imageContentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.selectedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                    
                    node.animationNode.isHidden = true
                    node.animationNode.visibility = false
                }
                
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                node.textImageNode.image = textImage
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button, .selected]
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = true
            } else {
                let (textImage, contentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.textColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (image, imageContentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.iconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                
                node.animationNode.isHidden = true
                node.animationNode.visibility = false
                
                node.textImageNode.image = textImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button]
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = false
            }
            container.badgeBackgroundNode.image = self.badgeImage
            node.extractedContainerNode.contentNode.addSubnode(container.badgeContainerNode)
            tabBarNodeContainers.append(container)
            self.addSubnode(node)
        }
        
        self.tabBarNodeContainers = tabBarNodeContainers
        
        self.setNeedsLayout()
    }
    
    private func updateNodeImage(_ index: Int, layout: Bool) {
        if index < self.tabBarNodeContainers.count && index < self.tabBarItems.count {
            let node = self.tabBarNodeContainers[index].imageNode
            let item = self.tabBarItems[index]
            
            self.centered = self.theme.rootController.tabBar.textColor == .clear
            
            if item.item.ringSelection {
                node.ringColor = self.theme.rootController.tabBar.selectedIconColor
            } else {
                node.ringColor = nil
            }
            
            let previousImageSize = node.imageNode.image?.size ?? CGSize()
            let previousTextImageSize = node.textImageNode.image?.size ?? CGSize()
            if let selectedIndex = self.selectedIndex, selectedIndex == index {
                let (textImage, contentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.selectedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (image, imageContentWidth): (UIImage, CGFloat)
                if let _ = item.item.animationName {
                    (image, imageContentWidth) = (UIImage(), 0.0)
                    
                    node.animationNode.isHidden = false
                    let animationSize: Int = Int(51.0 * UIScreen.main.scale)
                    node.animationNode.visibility = true
                    if !node.isSelected {
                        node.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: item.item.animationName ?? ""), width: animationSize, height: animationSize, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
                    }
                    node.animationNode.setOverlayColor(self.theme.rootController.tabBar.selectedIconColor, replace: true, animated: false)
                    node.animationNode.updateLayout(size: CGSize(width: 51.0, height: 51.0))
                } else {
                    if item.item.ringSelection {
                        (image, imageContentWidth) = (item.item.selectedImage ?? UIImage(), item.item.selectedImage?.size.width ?? 0.0)
                    } else {
                        (image, imageContentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.selectedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                    }
                    
                    node.animationNode.isHidden = true
                    node.animationNode.visibility = false
                }
                
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                node.textImageNode.image = textImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button, .selected]
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = true
                
                if !self.reduceMotion && item.item.ringSelection {
                    ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateTransformScale(node: node.ringImageNode, scale: 1.0, delay: 0.1)
                    node.imageNode.layer.animateScale(from: 1.0, to: 0.87, duration: 0.1, removeOnCompletion: false, completion: { [weak node] _ in
                        node?.imageNode.layer.animateScale(from: 0.87, to: 1.0, duration: 0.14, removeOnCompletion: false, completion: { [weak node] _ in
                            node?.imageNode.layer.removeAllAnimations()
                        })
                    })
                }
            } else {
                let (textImage, contentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.textColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                
                let (image, imageContentWidth): (UIImage, CGFloat)
                if item.item.ringSelection {
                    (image, imageContentWidth) = (item.item.image ?? UIImage(), item.item.image?.size.width ?? 0.0)
                } else {
                    (image, imageContentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.iconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                }
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                
                node.animationNode.stop()
                node.animationNode.isHidden = true
                node.animationNode.visibility = false
                
                node.textImageNode.image = textImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button]
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = false
                
                ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateTransformScale(node: node.ringImageNode, scale: 0.5)
            }
            
            let updatedImageSize = node.imageNode.image?.size ?? CGSize()
            let updatedTextImageSize = node.textImageNode.image?.size ?? CGSize()
            
            if previousImageSize != updatedImageSize || previousTextImageSize != updatedTextImageSize {
                if let validLayout = self.validLayout, layout {
                    self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
                }
            }
        }
    }
    
    private func updateNodeBadge(_ index: Int, value: String) {
        self.tabBarNodeContainers[index].badgeValue = value
        if self.tabBarNodeContainers[index].badgeValue != self.tabBarNodeContainers[index].appliedBadgeValue {
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
            }
        }
    }
    
    private func updateNodeTitle(_ index: Int, value: String) {
        self.tabBarNodeContainers[index].titleValue = value
        if self.tabBarNodeContainers[index].titleValue != self.tabBarNodeContainers[index].appliedTitleValue {
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
            }
        }
    }
    
    func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, additionalSideInsets: UIEdgeInsets, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, leftInset, rightInset, additionalSideInsets, bottomInset)
        
        transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(), size: size))
        // NOTE: Removed self.backgroundNode.update() - ASDisplayNode doesn't have this method
        // NavigationBackgroundNode had it but we're using plain ASDisplayNode now
        
        let horizontal = !leftInset.isZero
        if self.horizontal != horizontal {
            self.horizontal = horizontal
            for i in 0 ..< self.tabBarItems.count {
                self.updateNodeImage(i, layout: false)
            }
        }
        
        if self.tabBarNodeContainers.count != 0 {
            var tabBarNodeContainers = self.tabBarNodeContainers
            var width = size.width
            
            var callsTabBarNodeContainer: TabBarNodeContainer?
            if tabBarNodeContainers.count == 4 {
                callsTabBarNodeContainer = tabBarNodeContainers[1]
            }
            
            if additionalSideInsets.right > 0.0 {
                width -= additionalSideInsets.right
                
                if let callsTabBarNodeContainer = callsTabBarNodeContainer {
                    tabBarNodeContainers.remove(at: 1)
                    transition.updateAlpha(node: callsTabBarNodeContainer.imageNode, alpha: 0.0)
                    callsTabBarNodeContainer.imageNode.isUserInteractionEnabled = false
                }
            } else {
                if let callsTabBarNodeContainer = callsTabBarNodeContainer {
                    transition.updateAlpha(node: callsTabBarNodeContainer.imageNode, alpha: 1.0)
                    callsTabBarNodeContainer.imageNode.isUserInteractionEnabled = true
                }
            }
            
            let distanceBetweenNodes = width / CGFloat(tabBarNodeContainers.count)
            
            let internalWidth = distanceBetweenNodes * CGFloat(tabBarNodeContainers.count - 1)
            let leftNodeOriginX = (width - internalWidth) / 2.0
            
            for i in 0 ..< tabBarNodeContainers.count {
                let container = tabBarNodeContainers[i]
                let node = container.imageNode
                let nodeSize = node.textImageNode.image?.size ?? CGSize()
                
                let originX = floor(leftNodeOriginX + CGFloat(i) * distanceBetweenNodes - nodeSize.width / 2.0)
                let horizontalHitTestInset = distanceBetweenNodes / 2.0 - nodeSize.width / 2.0
                let nodeFrame = CGRect(origin: CGPoint(x: originX, y: 3.0), size: nodeSize)
                transition.updateFrame(node: node, frame: nodeFrame)
                node.extractedContainerNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                node.extractedContainerNode.contentNode.frame = node.extractedContainerNode.bounds
                node.extractedContainerNode.contentRect = node.extractedContainerNode.bounds
                node.containerNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                node.hitTestSlop = UIEdgeInsets(top: -3.0, left: -horizontalHitTestInset, bottom: -3.0, right: -horizontalHitTestInset)
                node.containerNode.hitTestSlop = UIEdgeInsets(top: -3.0, left: -horizontalHitTestInset, bottom: -3.0, right: -horizontalHitTestInset)
                node.accessibilityFrame = nodeFrame.insetBy(dx: -horizontalHitTestInset, dy: 0.0).offsetBy(dx: 0.0, dy: size.height - nodeSize.height - bottomInset)
                if node.ringColor == nil {
                    node.imageNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                }
                node.textImageNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                node.contextImageNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                node.contextTextImageNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                
                let scaleFactor: CGFloat = horizontal ? 0.8 : 1.0
                node.animationContainerNode.subnodeTransform = CATransform3DMakeScale(scaleFactor, scaleFactor, 1.0)
                let animationOffset: CGPoint = self.tabBarItems[i].item.animationOffset
                let ringImageFrame: CGRect
                let imageFrame: CGRect
                if horizontal {
                    node.animationNode.frame = CGRect(origin: CGPoint(x: -10.0 - UIScreenPixel, y: -4.0 - UIScreenPixel), size: CGSize(width: 51.0, height: 51.0))
                    ringImageFrame = CGRect(origin: CGPoint(x: UIScreenPixel, y: 5.0 + UIScreenPixel), size: CGSize(width: 23.0, height: 23.0))
                    imageFrame = ringImageFrame.insetBy(dx: -1.0 + UIScreenPixel, dy: -1.0 + UIScreenPixel)
                } else {
                    node.animationNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((nodeSize.width - 51.0) / 2.0), y: -10.0 - UIScreenPixel).offsetBy(dx: animationOffset.x, dy: animationOffset.y), size: CGSize(width: 51.0, height: 51.0))
                    ringImageFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((nodeSize.width - 29.0) / 2.0), y: 1.0), size: CGSize(width: 29.0, height: 29.0))
                    imageFrame = ringImageFrame.insetBy(dx: -1.0, dy: -1.0)
                }
                node.ringImageNode.bounds = CGRect(origin: CGPoint(), size: ringImageFrame.size)
                node.ringImageNode.position = ringImageFrame.center
                
                if node.ringColor != nil {
                    node.imageNode.bounds = CGRect(origin: CGPoint(), size: imageFrame.size)
                    node.imageNode.position = imageFrame.center
                }
                
                if container.badgeValue != container.appliedBadgeValue {
                    container.appliedBadgeValue = container.badgeValue
                    if let badgeValue = container.badgeValue, !badgeValue.isEmpty {
                        container.badgeTextNode.attributedText = NSAttributedString(string: badgeValue, font: badgeFont, textColor: self.theme.rootController.tabBar.badgeTextColor)
                        container.badgeContainerNode.isHidden = false
                    } else {
                        container.badgeContainerNode.isHidden = true
                    }
                }
                
                if !container.badgeContainerNode.isHidden {
                    var hasSingleLetterValue: Bool = false
                    if let string = container.badgeTextNode.attributedText?.string {
                        hasSingleLetterValue = string.count == 1
                    }
                    let badgeSize = container.badgeTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
                    let backgroundSize = CGSize(width: hasSingleLetterValue ? 18.0 : max(18.0, badgeSize.width + 10.0 + 1.0), height: 18.0)
                    let backgroundFrame: CGRect
                    if horizontal {
                        backgroundFrame = CGRect(origin: CGPoint(x: 13.0, y: 0.0), size: backgroundSize)
                    } else {
                        let contentWidth: CGFloat = 25.0
                        backgroundFrame = CGRect(origin: CGPoint(x: floor(node.frame.width / 2.0) + contentWidth - backgroundSize.width - 5.0, y: self.centered ? 6.0 : -1.0), size: backgroundSize)
                    }
                    transition.updateFrame(node: container.badgeContainerNode, frame: backgroundFrame)
                    container.badgeBackgroundNode.frame = CGRect(origin: CGPoint(), size: backgroundFrame.size)
                    
                    container.badgeContainerNode.subnodeTransform = CATransform3DMakeScale(scaleFactor, scaleFactor, 1.0)
                    
                    container.badgeTextNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundFrame.size.width - badgeSize.width) / 2.0), y: 1.0), size: badgeSize)
                }
            }
            
            // Update selection indicator position after layout
            updateSelectionIndicatorPosition(animated: transition.isAnimated)
        }
    }
    
    private func tapped(at location: CGPoint, longTap: Bool) {
        if let bottomInset = self.validLayout?.4 {
            if location.y > self.bounds.size.height - bottomInset {
                return
            }
            var closestNode: (Int, CGFloat)?
            for i in 0 ..< self.tabBarNodeContainers.count {
                let node = self.tabBarNodeContainers[i].imageNode
                if !node.isUserInteractionEnabled {
                    continue
                }
                let distance = abs(location.x - node.position.x)
                if let previousClosestNode = closestNode {
                    if previousClosestNode.1 > distance {
                        closestNode = (i, distance)
                    }
                } else {
                    closestNode = (i, distance)
                }
            }
            
            if let closestNode = closestNode {
                let container = self.tabBarNodeContainers[closestNode.0]
                let previousSelectedIndex = self.selectedIndex
                self.itemSelected(closestNode.0, longTap, [container.imageNode.imageNode, container.imageNode.textImageNode, container.badgeContainerNode])
                if previousSelectedIndex != closestNode.0 {
                    if let selectedIndex = self.selectedIndex, let _ = self.tabBarItems[selectedIndex].item.animationName {
                        container.imageNode.animationNode.play(firstFrame: false, fromIndex: nil)
                    }
                }
            }
        }
    }
}