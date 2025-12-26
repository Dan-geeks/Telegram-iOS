import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import LegacyComponents
import AccountContext
import ChatInterfaceState
import AudioBlob
import ChatPresentationInterfaceState
import ComponentFlow
import LottieAnimationComponent
import LottieComponent
import LegacyInstantVideoController
import GlassBackgroundComponent
import ComponentDisplayAdapters

/// Liquid Glass animation configuration for recording button
private struct RecordingButtonGlassConfig {
    static let pressedScale: CGFloat = 0.92
    static let pressDownDuration: TimeInterval = 0.12
    static let bounceScale: CGFloat = 1.10
    static let springDamping: CGFloat = 0.65
    static let springVelocity: CGFloat = 0.5
    static let releaseDuration: TimeInterval = 0.4
    static let cornerRadius: CGFloat = 22.0
}

/// Specular highlight layer for recording button glass effect
private final class RecordingButtonGlassLayer: CALayer {
    private let gradientLayer = CAGradientLayer()

    override init() {
        super.init()
        setupGradient()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? RecordingButtonGlassLayer {
            gradientLayer.colors = other.gradientLayer.colors
            gradientLayer.locations = other.gradientLayer.locations
            gradientLayer.startPoint = other.gradientLayer.startPoint
            gradientLayer.endPoint = other.gradientLayer.endPoint
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupGradient() {
        gradientLayer.colors = [
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0.15).cgColor,
            UIColor.white.withAlphaComponent(0.05).cgColor
        ]
        gradientLayer.locations = [0.0, 0.5, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.3, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.7, y: 1.0)
        gradientLayer.compositingFilter = "screenBlendMode"
        addSublayer(gradientLayer)
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        gradientLayer.frame = bounds
    }
}

private let offsetThreshold: CGFloat = 10.0
private let dismissOffsetThreshold: CGFloat = 70.0

private func findTargetView(_ view: UIView, point: CGPoint) -> UIView? {
    if view.bounds.contains(point) && view.tag == 0x01f2bca {
        return view
    }
    for subview in view.subviews {
        let frame = subview.frame
        if let result = findTargetView(subview, point: point.offsetBy(dx: -frame.minX, dy: -frame.minY)) {
            return result
        }
    }
    return nil
}

private final class ChatTextInputMediaRecordingButtonPresenterContainer: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let result = findTargetView(self, point: point) {
            return result
        }
        for subview in self.subviews {
            if let result = subview.hitTest(point.offsetBy(dx: -subview.frame.minX, dy: -subview.frame.minY), with: event) {
                return result
            }
        }
        
        return super.hitTest(point, with: event)
    }
}

private final class ChatTextInputMediaRecordingButtonPresenterController: ViewController {
    private var controllerNode: ChatTextInputMediaRecordingButtonPresenterControllerNode {
        return self.displayNode as! ChatTextInputMediaRecordingButtonPresenterControllerNode
    }
    
    var containerView: UIView? {
        didSet {
            if self.isNodeLoaded {
                self.controllerNode.containerView = self.containerView
            }
        }
    }
    
    override func loadDisplayNode() {
        self.displayNode = ChatTextInputMediaRecordingButtonPresenterControllerNode()
        if let containerView = self.containerView {
            self.controllerNode.containerView = containerView
        }
    }
}

private final class ChatTextInputMediaRecordingButtonPresenterControllerNode: ViewControllerTracingNode {
    var containerView: UIView? {
        didSet {
            if self.containerView !== oldValue {
                if self.isNodeLoaded, let containerView = oldValue, containerView.superview === self.view {
                    containerView.removeFromSuperview()
                }
                if self.isNodeLoaded, let containerView = self.containerView {
                    self.view.addSubview(containerView)
                }
            }
        }
    }
    
    override func didLoad() {
        super.didLoad()
        if let containerView = self.containerView {
            self.view.addSubview(containerView)
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let containerView = self.containerView {
            if let result = containerView.hitTest(point, with: event), result !== containerView {
                return result
            }
        }
        return nil
    }
}

private final class ChatTextInputMediaRecordingButtonPresenter : NSObject, TGModernConversationInputMicButtonPresentation {
    private let statusBarHost: StatusBarHost?
    private let presentController: (ViewController) -> Void
    let container: ChatTextInputMediaRecordingButtonPresenterContainer
    private var presentationController: ChatTextInputMediaRecordingButtonPresenterController?
    private var timer: SwiftSignalKit.Timer?
    fileprivate weak var button: ChatTextInputMediaRecordingButton?
    
    init(statusBarHost: StatusBarHost?, presentController: @escaping (ViewController) -> Void) {
        self.statusBarHost = statusBarHost
        self.presentController = presentController
        self.container = ChatTextInputMediaRecordingButtonPresenterContainer()
    }
    
    deinit {
        self.container.removeFromSuperview()
        if let presentationController = self.presentationController {
            presentationController.presentingViewController?.dismiss(animated: false, completion: {})
            self.presentationController = nil
        }
        self.timer?.invalidate()
    }
    
    func view() -> UIView! {
        return self.container
    }
    
    func setUserInteractionEnabled(_ enabled: Bool) {
        self.container.isUserInteractionEnabled = enabled
    }
    
    func present() {
        let windowIsVisible: (UIWindow) -> Bool = { window in
            return !window.frame.height.isZero
        }
        
        if let statusBarHost = self.statusBarHost, let keyboardWindow = statusBarHost.keyboardWindow, let keyboardView = statusBarHost.keyboardView, !keyboardView.frame.height.isZero, isViewVisibleInHierarchy(keyboardView) {
            keyboardWindow.addSubview(self.container)
            
            self.timer = SwiftSignalKit.Timer(timeout: 0.05, repeat: true, completion: { [weak self] in
                if let keyboardWindow = LegacyComponentsGlobals.provider().applicationKeyboardWindow(), windowIsVisible(keyboardWindow) {
                } else {
                    self?.present()
                }
            }, queue: Queue.mainQueue())
            self.timer?.start()
        } else {
            var presentNow = false
            if self.presentationController == nil {
                let presentationController = ChatTextInputMediaRecordingButtonPresenterController(navigationBarPresentationData: nil)
                presentationController.statusBar.statusBarStyle = .Ignore
                self.presentationController = presentationController
                presentNow = true
            }
            
            self.presentationController?.containerView = self.container
            if let presentationController = self.presentationController, presentNow {
                self.presentController(presentationController)
            }
            
            if let timer = self.timer {
                self.button?.reset()
                timer.invalidate()
            }
        }
    }
    
    func dismiss() {
        self.timer?.invalidate()
        self.container.removeFromSuperview()
        if let presentationController = self.presentationController {
            presentationController.presentingViewController?.dismiss(animated: false, completion: {})
            self.presentationController = nil
        }
    }
}

public final class ChatTextInputMediaRecordingButton: TGModernConversationInputMicButton, TGModernConversationInputMicButtonDelegate {
    private let context: AccountContext
    private var theme: PresentationTheme
    private let useDarkTheme: Bool
    private let pause: Bool
    private let strings: PresentationStrings
    
    public var mode: ChatTextInputMediaRecordingButtonMode = .audio
    public var statusBarHost: StatusBarHost?
    public let presentController: (ViewController) -> Void
    public var recordingDisabled: () -> Void = { }
    public var beginRecording: () -> Void = { }
    public var endRecording: (Bool) -> Void = { _ in }
    public var stopRecording: () -> Void = { }
    public var offsetRecordingControls: () -> Void = { }
    public var switchMode: () -> Void = { }
    public var updateLocked: (Bool) -> Void = { _ in }
    public var updateCancelTranslation: () -> Void = { }
    
    private var modeTimeoutTimer: SwiftSignalKit.Timer?
    
    private let animationView: ComponentView<Empty>
    public var animationOutput: UIImageView? {
        didSet {
            if let view = self.animationView.view as? LottieComponent.View {
                view.output = self.animationOutput
            }
        }
    }
    
    private var recordingOverlay: ChatTextInputAudioRecordingOverlay?
    private var startTouchLocation: CGPoint?
    fileprivate var controlsOffset: CGFloat = 0.0
    public private(set) var cancelTranslation: CGFloat = 0.0
    
    private var micLevelDisposable: MetaDisposable?

    private weak var currentPresenter: UIView?

    // MARK: - Liquid Glass Properties
    private var glassBlurView: UIVisualEffectView?
    private var glassSpecularLayer: RecordingButtonGlassLayer?
    private var glassPressHighlightLayer: CALayer?
    private var isGlassEffectVisible: Bool = false
    private var glassLightImpact: UIImpactFeedbackGenerator?
    private var glassMediumImpact: UIImpactFeedbackGenerator?

    private func setupLiquidGlassEffect() {
        // Setup blur background
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        blurView.layer.cornerRadius = RecordingButtonGlassConfig.cornerRadius
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        blurView.alpha = 0.0
        self.insertSubview(blurView, at: 0)
        self.glassBlurView = blurView

        // Setup specular highlight layer
        let specularLayer = RecordingButtonGlassLayer()
        specularLayer.cornerRadius = RecordingButtonGlassConfig.cornerRadius
        specularLayer.masksToBounds = true
        specularLayer.opacity = 0.0
        self.layer.insertSublayer(specularLayer, above: blurView.layer)
        self.glassSpecularLayer = specularLayer

        // Setup press highlight layer
        let highlightLayer = CALayer()
        highlightLayer.backgroundColor = UIColor.white.withAlphaComponent(0.2).cgColor
        highlightLayer.cornerRadius = RecordingButtonGlassConfig.cornerRadius
        highlightLayer.opacity = 0.0
        self.layer.insertSublayer(highlightLayer, above: specularLayer)
        self.glassPressHighlightLayer = highlightLayer

        // Setup haptic feedback generators
        self.glassLightImpact = UIImpactFeedbackGenerator(style: .light)
        self.glassMediumImpact = UIImpactFeedbackGenerator(style: .medium)
        self.glassLightImpact?.prepare()
        self.glassMediumImpact?.prepare()
    }

    public var hasShadow: Bool = false {
        didSet {
            self.updateShadow()
        }
    }
    
    public var hidesOnLock: Bool = false {
        didSet {
            if self.hidesOnLock {
                self.setHidesPanelOnLock()
            }
        }
    }
    
    private func updateShadow() {
        if let view = self.animationView.view {
            if self.hasShadow {
                view.layer.shadowOffset = CGSize(width: 0.0, height: 0.0)
                view.layer.shadowRadius = 2.0
                view.layer.shadowColor = UIColor.black.cgColor
                view.layer.shadowOpacity = 0.35
            } else {
                view.layer.shadowRadius = 0.0
                view.layer.shadowColor = UIColor.clear.cgColor
                view.layer.shadowOpacity = 0.0
            }
        }
    }

    public var contentContainer: (UIView, CGRect)? {
        if let _ = self.currentPresenter {
            return (self.micDecoration, self.micDecoration.bounds)
        } else {
            return nil
        }
    }
    
    public var audioRecorder: ManagedAudioRecorder? {
        didSet {
            if self.audioRecorder !== oldValue {
                if self.micLevelDisposable == nil {
                    micLevelDisposable = MetaDisposable()
                }
                if let audioRecorder = self.audioRecorder {
                    self.micLevelDisposable?.set(audioRecorder.micLevel.start(next: { [weak self] level in
                        Queue.mainQueue().async {
                            self?.addMicLevel(CGFloat(level))
                        }
                    }))
                } else if self.videoRecordingStatus == nil {
                    self.micLevelDisposable?.set(nil)
                }
                
                self.hasRecorder = self.audioRecorder != nil || self.videoRecordingStatus != nil
            }
        }
    }
    
    public var videoRecordingStatus: InstantVideoControllerRecordingStatus? {
        didSet {
            if self.videoRecordingStatus !== oldValue {
                if self.micLevelDisposable == nil {
                    micLevelDisposable = MetaDisposable()
                }
                
                if let videoRecordingStatus = self.videoRecordingStatus {
                    self.micLevelDisposable?.set(videoRecordingStatus.micLevel.start(next: { [weak self] level in
                        Queue.mainQueue().async {
                            self?.addMicLevel(CGFloat(level))
                        }
                    }))
                } else if self.audioRecorder == nil {
                    self.micLevelDisposable?.set(nil)
                }
                
                self.hasRecorder = self.audioRecorder != nil || self.videoRecordingStatus != nil
            }
        }
    }
    
    private var hasRecorder: Bool = false {
        didSet {
            if self.hasRecorder != oldValue {
                if self.hasRecorder {
                    self.animateIn()
                } else {
                    self.animateOut(false)
                }
            }
        }
    }
    
    private var micDecorationValue: VoiceBlobView?
    private var micDecoration: (UIView & TGModernConversationInputMicButtonDecoration) {
        if let micDecorationValue = self.micDecorationValue {
            return micDecorationValue
        } else {
            let blobView = VoiceBlobView(
                frame: CGRect(origin: CGPoint(), size: CGSize(width: 220.0, height: 220.0)),
                maxLevel: 4,
                smallBlobRange: (0.45, 0.55),
                mediumBlobRange: (0.52, 0.87),
                bigBlobRange: (0.57, 1.00)
            )
            let theme = self.hidesOnLock ? defaultDarkColorPresentationTheme : self.theme
            blobView.setColor(theme.chat.inputPanel.actionControlFillColor)
            self.micDecorationValue = blobView
            return blobView
        }
    }
    
    private var micLockValue: (UIView & TGModernConversationInputMicButtonLock)?
    private var micLock: UIView & TGModernConversationInputMicButtonLock {
        if let current = self.micLockValue {
            return current
        } else {
            let lockView = LockView(frame: CGRect(origin: CGPoint(), size: CGSize(width: 40.0, height: 60.0)), theme: self.theme, useDarkTheme: self.useDarkTheme, pause: self.pause, strings: self.strings)
            lockView.addTarget(self, action: #selector(handleStopTap), for: .touchUpInside)
            self.micLockValue = lockView
            return lockView
        }
    }
    
    public init(context: AccountContext, theme: PresentationTheme, useDarkTheme: Bool = false, pause: Bool = false, strings: PresentationStrings, presentController: @escaping (ViewController) -> Void) {
        self.context = context
        self.theme = theme
        self.useDarkTheme = useDarkTheme
        self.pause = pause
        self.strings = strings
        self.animationView = ComponentView<Empty>()
        self.presentController = presentController
         
        super.init(frame: CGRect())
        
        self.disablesInteractiveTransitionGestureRecognizer = true
        
        self.pallete = legacyInputMicPalette(from: theme)
        
        self.disablesInteractiveTransitionGestureRecognizer = true
        
        self.updateMode(mode: self.mode, animated: false, force: true)
        
        self.delegate = self
        self.isExclusiveTouch = false;

        self.centerOffset = CGPoint(x: 0.0, y: -1.0 + UIScreenPixel)

        setupLiquidGlassEffect()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let micLevelDisposable = self.micLevelDisposable {
            micLevelDisposable.dispose()
        }
        if let recordingOverlay = self.recordingOverlay {
            recordingOverlay.dismiss()
        }
    }
    
    public func updateMode(mode: ChatTextInputMediaRecordingButtonMode, animated: Bool) {
        self.updateMode(mode: mode, animated: animated, force: false)
    }
        
    private func updateMode(mode: ChatTextInputMediaRecordingButtonMode, animated: Bool, force: Bool) {
        let previousMode = self.mode
        if mode != self.mode || force {
            self.mode = mode

            self.updateAnimation(previousMode: previousMode)
        }
    }
    
    private func updateAnimation(previousMode: ChatTextInputMediaRecordingButtonMode) {
        let image: UIImage?
        let theme = self.hidesOnLock ? defaultDarkColorPresentationTheme : self.theme
        switch self.mode {
            case .audio:
                self.icon = PresentationResourcesChat.chatInputPanelVoiceActiveButtonImage(theme)
                image = PresentationResourcesChat.chatInputPanelVoiceButtonImage(theme)
            case .video:
                self.icon = PresentationResourcesChat.chatInputPanelVideoActiveButtonImage(theme)
                image = PresentationResourcesChat.chatInputPanelVoiceButtonImage(theme)
        }
        
        let size = self.bounds.size
        let iconSize: CGSize
        if let image = image {
            iconSize = image.size
        } else {
            iconSize = size
        }

        let animationFrame = CGRect(origin: CGPoint(x: floor((size.width - iconSize.width) / 2.0), y: floor((size.height - iconSize.height) / 2.0)), size: iconSize)
        
        let animationName: String
        switch self.mode {
            case .audio:
                animationName = "anim_videoToMic"
            case .video:
                animationName = "anim_micToVideo"
        }

        let animationTintColor = self.useDarkTheme ? .white : self.theme.chat.inputPanel.panelControlColor
        let _ = self.animationView.update(
            transition: .immediate,
            component: AnyComponent(LottieComponent(
                content: LottieComponent.AppBundleContent(name: animationName),
                color: animationTintColor
            )),
            environment: {},
            containerSize: animationFrame.size
        )

        if let view = self.animationView.view as? LottieComponent.View {
            view.isUserInteractionEnabled = false
            if view.superview == nil {
                self.insertSubview(view, at: 0)
                view.output = self.animationOutput
                self.updateShadow()
            }
            view.setMonochromaticEffect(tintColor: animationTintColor)
            view.frame = animationFrame
            
            if previousMode != mode {
                view.playOnce()
            }
        }
        
        if let animationOutput = self.animationOutput {
            animationOutput.frame = animationFrame
        }
    }
    
    public func updateTheme(theme: PresentationTheme) {
        self.theme = theme
        
        self.updateAnimation(previousMode: self.mode)
        
        self.pallete = legacyInputMicPalette(from: theme)
        self.micDecorationValue?.setColor(self.theme.chat.inputPanel.actionControlFillColor)
        (self.micLockValue as? LockView)?.updateTheme(theme)
    }
    
    public override func createLockPanelView() -> (UIView & TGModernConversationInputMicButtonLockPanelView)! {
        let isDark: Bool
        let tintColor: UIColor
        if self.hidesOnLock {
            isDark = false
            tintColor = UIColor(white: 0.0, alpha: 0.5)
        } else {
            isDark = self.theme.overallDarkAppearance
            tintColor = self.theme.chat.inputPanel.inputBackgroundColor.withMultipliedAlpha(0.7)
        }
        
        let view = WrapperBlurrredBackgroundView(size: CGSize(width: 40.0, height: 72.0), isDark: isDark, tintColor: tintColor)
        return view
    }
    
    public func cancelRecording() {
        self.isEnabled = false
        self.isEnabled = true
    }
    
    public func micButtonInteractionBegan() {
        animateGlassPressDown()

        if self.fadeDisabled {
            self.recordingDisabled()
        } else {
            //print("\(CFAbsoluteTimeGetCurrent()) began")
            self.modeTimeoutTimer?.invalidate()
            let modeTimeoutTimer = SwiftSignalKit.Timer(timeout: 0.19, repeat: false, completion: { [weak self] in
                if let strongSelf = self {
                    strongSelf.modeTimeoutTimer = nil
                    strongSelf.beginRecording()
                }
            }, queue: Queue.mainQueue())
            self.modeTimeoutTimer = modeTimeoutTimer
            modeTimeoutTimer.start()
        }
    }
    
    public func micButtonInteractionCancelled(_ velocity: CGPoint) {
        animateGlassRelease()

        //print("\(CFAbsoluteTimeGetCurrent()) cancelled")
        self.modeTimeoutTimer?.invalidate()
        self.endRecording(false)
    }
    
    public func micButtonInteractionCompleted(_ velocity: CGPoint) {
        animateGlassRelease()

        //print("\(CFAbsoluteTimeGetCurrent()) completed")
        if let modeTimeoutTimer = self.modeTimeoutTimer {
            //print("\(CFAbsoluteTimeGetCurrent()) switch")
            modeTimeoutTimer.invalidate()
            self.modeTimeoutTimer = nil
            self.switchMode()
        }
        self.endRecording(true)
    }
    
    public func micButtonInteractionUpdate(_ offset: CGPoint) {
        self.controlsOffset = offset.x
        self.offsetRecordingControls()
    }
    
    public func micButtonInteractionUpdateCancelTranslation(_ translation: CGFloat) {
        self.cancelTranslation = translation
        self.updateCancelTranslation()
    }
    
    public func micButtonInteractionLocked() {
        self.updateLocked(true)
    }
    
    public func micButtonInteractionRequestedLockedAction() {
    }
    
    public func micButtonInteractionStopped() {
        self.stopRecording()
    }
    
    public func micButtonShouldLock() -> Bool {
        return true
    }
    
    public func micButtonPresenter() -> TGModernConversationInputMicButtonPresentation! {
        let presenter = ChatTextInputMediaRecordingButtonPresenter(statusBarHost: self.statusBarHost, presentController: self.presentController)
        presenter.button = self
        self.currentPresenter = presenter.view()
        return presenter
    }
    
    public func micButtonDecoration() -> (UIView & TGModernConversationInputMicButtonDecoration)! {
        return micDecoration
    }
    
    public func micButtonLock() -> (UIView & TGModernConversationInputMicButtonLock)! {
        return micLock
    }
    
    @objc private func handleStopTap() {
        micButtonInteractionStopped()
    }
    
    public func lock() {
        super._commitLocked()
    }
    
    override public func animateIn() {
        super.animateIn()
        showGlassEffect(animated: true)

        if self.context.sharedContext.energyUsageSettings.fullTranslucency {
            micDecoration.isHidden = false
            micDecoration.startAnimating()
        }

        let transition = ContainedViewLayoutTransition.animated(duration: 0.15, curve: .easeInOut)
        if let layer = self.animationView.view?.layer {
            transition.updateAlpha(layer: layer, alpha: 0.0)
            transition.updateTransformScale(layer: layer, scale: 0.3)

            if let animationOutput = self.animationOutput {
                transition.updateAlpha(layer: animationOutput.layer, alpha: 0.0)
                transition.updateTransformScale(layer: animationOutput.layer, scale: 0.3)
            }
        }
    }

    override public func animateOut(_ toSmallSize: Bool) {
        hideGlassEffect(animated: !toSmallSize)

        super.animateOut(toSmallSize)

        micDecoration.stopAnimating()

        if toSmallSize {
            micDecoration.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.03, delay: 0.15, removeOnCompletion: false)
        } else {
            micDecoration.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18, removeOnCompletion: false)
            let transition = ContainedViewLayoutTransition.animated(duration: 0.15, curve: .easeInOut)
            if let layer = self.animationView.view?.layer {
                transition.updateAlpha(layer: layer, alpha: 1.0)
                transition.updateTransformScale(layer: layer, scale: 1.0)

                if let animationOutput = self.animationOutput {
                    transition.updateAlpha(layer: animationOutput.layer, alpha: 1.0)
                    transition.updateTransformScale(layer: animationOutput.layer, scale: 1.0)
                }
            }
        }
    }
    
    private var previousSize = CGSize()
    public func layoutItems() {
        let size = self.bounds.size
        if size != self.previousSize {
            self.previousSize = size
            if let view = self.animationView.view {
                let iconSize = view.bounds.size
                view.bounds = CGRect(origin: .zero, size: iconSize)
                view.center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)

                if let animationOutput = self.animationOutput {
                    animationOutput.bounds = view.bounds
                    animationOutput.center = view.center
                }
            }
        }

        updateGlassEffectFrames()
    }

    private func updateGlassEffectFrames() {
        let glassFrame = bounds.insetBy(dx: -4, dy: -4)
        glassBlurView?.frame = glassFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glassSpecularLayer?.frame = glassFrame
        glassPressHighlightLayer?.frame = glassFrame
        CATransaction.commit()
    }

    // MARK: - Liquid Glass Animations

    private func showGlassEffect(animated: Bool) {
        guard !isGlassEffectVisible else { return }
        isGlassEffectVisible = true

        let duration: TimeInterval = animated ? 0.3 : 0.0

        UIView.animate(withDuration: duration, delay: 0.0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.glassBlurView?.alpha = 1.0
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        self.glassSpecularLayer?.opacity = 1.0
        CATransaction.commit()
    }

    private func hideGlassEffect(animated: Bool) {
        guard isGlassEffectVisible else { return }
        isGlassEffectVisible = false

        let duration: TimeInterval = animated ? 0.2 : 0.0

        UIView.animate(withDuration: duration, delay: 0.0, options: [.curveEaseIn, .allowUserInteraction]) {
            self.glassBlurView?.alpha = 0.0
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
        self.glassSpecularLayer?.opacity = 0.0
        self.glassPressHighlightLayer?.opacity = 0.0
        CATransaction.commit()
    }

    private func animateGlassPressDown() {
        guard isGlassEffectVisible else { return }

        // Trigger light haptic feedback
        glassLightImpact?.impactOccurred()

        // Quick scale down with subtle highlight
        UIView.animate(withDuration: RecordingButtonGlassConfig.pressDownDuration, delay: 0.0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: RecordingButtonGlassConfig.pressedScale, y: RecordingButtonGlassConfig.pressedScale)
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(RecordingButtonGlassConfig.pressDownDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        self.glassPressHighlightLayer?.opacity = 0.3
        CATransaction.commit()
    }

    private func animateGlassRelease() {
        guard isGlassEffectVisible else { return }

        // Prepare haptics for potential bounce
        glassMediumImpact?.prepare()

        // Spring back to normal size
        UIView.animate(withDuration: RecordingButtonGlassConfig.releaseDuration, delay: 0.0, usingSpringWithDamping: RecordingButtonGlassConfig.springDamping, initialSpringVelocity: RecordingButtonGlassConfig.springVelocity, options: [.curveEaseInOut, .allowUserInteraction], animations: {
            self.transform = .identity
        })

        CATransaction.begin()
        CATransaction.setAnimationDuration(RecordingButtonGlassConfig.releaseDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        self.glassPressHighlightLayer?.opacity = 0.0
        CATransaction.commit()
    }

    private func animateGlassSelectionBounce() {
        guard isGlassEffectVisible else { return }

        // Trigger medium haptic feedback
        glassMediumImpact?.impactOccurred()

        // Scale up slightly then return with spring
        let scaleUp = CABasicAnimation(keyPath: "transform.scale")
        scaleUp.fromValue = 1.0
        scaleUp.toValue = RecordingButtonGlassConfig.bounceScale
        scaleUp.duration = 0.1
        scaleUp.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let scaleDown = CABasicAnimation(keyPath: "transform.scale")
        scaleDown.fromValue = RecordingButtonGlassConfig.bounceScale
        scaleDown.toValue = 1.0
        scaleDown.beginTime = 0.1
        scaleDown.duration = RecordingButtonGlassConfig.releaseDuration
        scaleDown.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0) // Spring curve

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [scaleUp, scaleDown]
        animationGroup.duration = 0.1 + RecordingButtonGlassConfig.releaseDuration
        animationGroup.fillMode = .forwards
        animationGroup.isRemovedOnCompletion = true

        self.layer.add(animationGroup, forKey: "glassSelectionBounce")

        // Flash highlight briefly
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        self.glassPressHighlightLayer?.opacity = 0.4

        CATransaction.setCompletionBlock {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            self.glassPressHighlightLayer?.opacity = 0.0
            CATransaction.commit()
        }
        CATransaction.commit()
    }
}

private final class WrapperBlurrredBackgroundView: UIView, TGModernConversationInputMicButtonLockPanelView {
    let isDark: Bool
    let glassTintColor: UIColor

    // Glass components
    private let blurView: UIVisualEffectView
    private let specularLayer: CAGradientLayer
    private let borderLayer: CAShapeLayer
    private let innerGlowLayer: CALayer

    // Animation state
    private var displayLink: CADisplayLink?
    private var animationProgress: CGFloat = 0

    init(size: CGSize, isDark: Bool, tintColor: UIColor) {
        self.isDark = isDark
        self.glassTintColor = tintColor

        // 1. Create blur view (glass body)
        let blurStyle: UIBlurEffect.Style
        if #available(iOS 13.0, *) {
            blurStyle = isDark ? .systemThinMaterialDark : .systemThinMaterial
        } else {
            blurStyle = isDark ? .dark : .light
        }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        blur.layer.cornerRadius = min(size.width, size.height) * 0.5
        blur.clipsToBounds = true
        self.blurView = blur

        // 2. Create specular highlight
        let specular = CAGradientLayer()
        specular.colors = [
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
            UIColor.clear.cgColor
        ]
        specular.locations = [0.0, 0.3, 1.0]
        specular.startPoint = CGPoint(x: 0.5, y: 0)
        specular.endPoint = CGPoint(x: 0.5, y: 1)
        specular.opacity = 0.25
        self.specularLayer = specular

        // 3. Create border glow
        let border = CAShapeLayer()
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = UIColor.white.withAlphaComponent(0.2).cgColor
        border.lineWidth = 0.5
        self.borderLayer = border

        // 4. Create inner glow
        let innerGlow = CALayer()
        innerGlow.backgroundColor = UIColor.white.withAlphaComponent(0.04).cgColor
        self.innerGlowLayer = innerGlow

        super.init(frame: CGRect(origin: .zero, size: size))

        // Add layers in correct order
        addSubview(blurView)
        layer.addSublayer(innerGlowLayer)
        layer.addSublayer(specularLayer)
        layer.addSublayer(borderLayer)

        // Initial layout
        updateLayout(size: size)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    private func updateLayout(size: CGSize) {
        let cornerRadius = min(size.width, size.height) * 0.5

        blurView.frame = CGRect(origin: .zero, size: size)
        blurView.layer.cornerRadius = cornerRadius

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        specularLayer.frame = CGRect(origin: .zero, size: size)
        specularLayer.cornerRadius = cornerRadius

        innerGlowLayer.frame = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        innerGlowLayer.cornerRadius = cornerRadius - 2

        let borderPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.25, dy: 0.25),
            cornerRadius: cornerRadius
        )
        borderLayer.path = borderPath.cgPath
        borderLayer.frame = CGRect(origin: .zero, size: size)

        CATransaction.commit()
    }

    override var frame: CGRect {
        get {
            return super.frame
        }
        set {
            super.frame = newValue
            updateLayout(size: newValue.size)
        }
    }

    // TGModernConversationInputMicButtonLockPanelView protocol
    func update(_ size: CGSize) {
        let transition = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut)

        // Animate the frame change
        transition.updateFrame(view: self.blurView, frame: CGRect(origin: .zero, size: size))

        // Update corner radius with animation
        let cornerRadius = min(size.width, size.height) * 0.5

        let cornerAnim = CABasicAnimation(keyPath: "cornerRadius")
        cornerAnim.toValue = cornerRadius
        cornerAnim.duration = 0.2
        cornerAnim.fillMode = .forwards
        cornerAnim.isRemovedOnCompletion = false
        blurView.layer.add(cornerAnim, forKey: "cornerRadius")
        specularLayer.add(cornerAnim, forKey: "cornerRadius")
        innerGlowLayer.add(cornerAnim, forKey: "cornerRadius")

        // Update other layers
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)

        specularLayer.frame = CGRect(origin: .zero, size: size)
        innerGlowLayer.frame = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)

        let borderPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.25, dy: 0.25),
            cornerRadius: cornerRadius
        )
        borderLayer.path = borderPath.cgPath
        borderLayer.frame = CGRect(origin: .zero, size: size)

        CATransaction.commit()

        // Animate specular highlight during size change (morphing effect)
        animateMorphingSpecular()
    }

    /// Animate the specular highlight during morphing transitions
    private func animateMorphingSpecular() {
        // Pulse the specular during morph
        let pulseAnim = CAKeyframeAnimation(keyPath: "opacity")
        pulseAnim.values = [0.25, 0.4, 0.25]
        pulseAnim.keyTimes = [0, 0.5, 1]
        pulseAnim.duration = 0.3
        specularLayer.add(pulseAnim, forKey: "morphPulse")

        // Shift the highlight position during morph (simulates light refraction)
        let positionAnim = CABasicAnimation(keyPath: "startPoint")
        positionAnim.fromValue = CGPoint(x: 0.3, y: 0)
        positionAnim.toValue = CGPoint(x: 0.7, y: 0)
        positionAnim.duration = 0.3
        positionAnim.autoreverses = true
        specularLayer.add(positionAnim, forKey: "morphPosition")
    }

    /// Show entrance animation
    func animateIn() {
        // Scale bounce entrance
        transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        alpha = 0

        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.65,
            initialSpringVelocity: 0.5,
            options: [],
            animations: {
                self.transform = .identity
                self.alpha = 1
            }
        )

        // Fade in specular
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 0.25
        fadeIn.duration = 0.3
        specularLayer.add(fadeIn, forKey: "fadeIn")
    }

    /// Show exit animation
    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseIn],
            animations: {
                self.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                self.alpha = 0
            }
        ) { _ in
            completion()
        }
    }
}
