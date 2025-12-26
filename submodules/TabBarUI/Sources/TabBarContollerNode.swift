import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import TabBarComponent

private extension ToolbarTheme {
    convenience init(theme: PresentationTheme) {
        self.init(barBackgroundColor: theme.rootController.tabBar.backgroundColor, barSeparatorColor: .clear, barTextColor: theme.rootController.tabBar.textColor, barSelectedTextColor: theme.rootController.tabBar.selectedTextColor)
    }
}

final class TabBarControllerNode: ASDisplayNode {
    private struct Params: Equatable {
        let layout: ContainerViewLayout
        let toolbar: Toolbar?
        let isTabBarHidden: Bool
        
        init(
            layout: ContainerViewLayout,
            toolbar: Toolbar?,
            isTabBarHidden: Bool
        ) {
            self.layout = layout
            self.toolbar = toolbar
            self.isTabBarHidden = isTabBarHidden
        }
    }
    
    private struct LayoutResult {
        let params: Params
        let bottomInset: CGFloat
        
        init(params: Params, bottomInset: CGFloat) {
            self.params = params
            self.bottomInset = bottomInset
        }
    }
    
    private final class View: UIView {
        var onLayout: (() -> Void)?
        
        override func layoutSubviews() {
            super.layoutSubviews()
            
            self.onLayout?()
        }
    }
    
    private var theme: PresentationTheme
    private let itemSelected: (Int, Bool, [ASDisplayNode]) -> Void
    private let contextAction: (Int, ContextExtractedContentContainingNode, ContextGesture) -> Void
    private let tabBarNode: TabBarNode
    
    private let disabledOverlayNode: ASDisplayNode
    private var toolbarNode: ToolbarNode?
    private let toolbarActionSelected: (ToolbarActionOption) -> Void
    private let disabledPressed: () -> Void
    
    private(set) var tabBarItems: [TabBarNodeItem] = []
    private(set) var selectedIndex: Int = 0

    private(set) var currentControllerNode: ASDisplayNode?
    
    private var layoutResult: LayoutResult?
    private var isUpdateRequested: Bool = false
    private var isChangingSelectedIndex: Bool = false
    
    func setCurrentControllerNode(_ node: ASDisplayNode?) -> () -> Void {
        guard node !== self.currentControllerNode else {
            return {}
        }
        
        let previousNode = self.currentControllerNode
        self.currentControllerNode = node
        if let currentControllerNode = self.currentControllerNode {
            if let previousNode {
                self.insertSubnode(currentControllerNode, aboveSubnode: previousNode)
            } else {
                self.insertSubnode(currentControllerNode, at: 0)
            }
            if let tabBarView = self.tabBarNode.view {
                self.view.bringSubviewToFront(tabBarView)
            }
        }
        
        return { [weak self, weak previousNode] in
            if previousNode !== self?.currentControllerNode {
                previousNode?.removeFromSupernode()
            }
        }
    }
    
    init(theme: PresentationTheme, itemSelected: @escaping (Int, Bool, [ASDisplayNode]) -> Void, contextAction: @escaping (Int, ContextExtractedContentContainingView, ContextGesture) -> Void, swipeAction: @escaping (Int, TabBarItemSwipeDirection) -> Void, toolbarActionSelected: @escaping (ToolbarActionOption) -> Void, disabledPressed: @escaping () -> Void) {
        self.theme = theme
        self.itemSelected = itemSelected
        self.contextAction = contextAction
        self.disabledOverlayNode = ASDisplayNode()
        self.disabledOverlayNode.backgroundColor = theme.rootController.tabBar.backgroundColor.withAlphaComponent(0.5)
        self.disabledOverlayNode.alpha = 0.0
        self.toolbarActionSelected = toolbarActionSelected
        self.disabledPressed = disabledPressed
        
        self.tabBarNode = TabBarNode(
            theme: theme,
            itemSelected: itemSelected,
            contextAction: contextAction,
            swipeAction: swipeAction
        )

        super.init()

        self.setViewBlock({
            return View(frame: CGRect())
        })

        self.addSubnode(self.tabBarNode)
        self.addSubnode(self.disabledOverlayNode)
        
        (self.view as? View)?.onLayout = { [weak self] in
            guard let self else {
                return
            }
            if self.isUpdateRequested {
                self.isUpdateRequested = false
                if let layoutResult = self.layoutResult {
                    let _ = self.updateImpl(params: layoutResult.params, transition: .immediate)
                }
            }
        }
        
        self.backgroundColor = theme.list.plainBackgroundColor
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.disabledOverlayNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.disabledTapGesture(_:))))
    }
    
    @objc private func disabledTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.disabledPressed()
        }
    }
    
    func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        self.backgroundColor = theme.list.plainBackgroundColor
        
        self.disabledOverlayNode.backgroundColor = theme.rootController.tabBar.backgroundColor.withAlphaComponent(0.5)
        self.toolbarNode?.updateTheme(ToolbarTheme(theme: theme))
        self.tabBarNode.updateTheme(theme)
        self.requestUpdate()
    }
    
    func updateIsTabBarEnabled(_ value: Bool, transition: ContainedViewLayoutTransition) {
        transition.updateAlpha(node: self.disabledOverlayNode, alpha: value ? 0.0 : 1.0)
    }
    
    var tabBarHidden = false {
        didSet {
            if self.tabBarHidden != oldValue {
                self.requestUpdate()
            }
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, toolbar: Toolbar?, transition: ContainedViewLayoutTransition) -> CGFloat {
        let params = Params(layout: layout, toolbar: toolbar, isTabBarHidden: self.tabBarHidden)
        if let layoutResult = self.layoutResult, layoutResult.params == params {
            return layoutResult.bottomInset
        } else {
            let bottomInset = self.updateImpl(params: params, transition: transition)
            self.layoutResult = LayoutResult(params: params, bottomInset: bottomInset)
            return bottomInset
        }
    }
    
    private func requestUpdate() {
        self.isUpdateRequested = true
        self.view.setNeedsLayout()
    }
    
    private func updateImpl(params: Params, transition: ContainedViewLayoutTransition) -> CGFloat {
        var options: ContainerViewLayoutInsetOptions = []
        if params.layout.metrics.widthClass == .regular {
            options.insert(.input)
        }
        
        var bottomInset: CGFloat = params.layout.insets(options: options).bottom
        if bottomInset == 0.0 {
            bottomInset = 8.0
        } else {
            bottomInset = max(bottomInset, 8.0)
        }
        
        // Pass data to your Liquid Glass Node
        self.tabBarNode.tabBarItems = self.tabBarItems
        self.tabBarNode.selectedIndex = self.selectedIndex

        // Calculate Frame
        let tabBarHeight = 49.0 + bottomInset
        let tabBarFrame = CGRect(
            x: 0,
            y: params.layout.size.height - (self.tabBarHidden ? 0.0 : tabBarHeight),
            width: params.layout.size.width,
            height: tabBarHeight
        )

        // Update Tab Bar Layout
        transition.updateFrame(node: self.tabBarNode, frame: tabBarFrame)
        self.tabBarNode.updateLayout(
            size: tabBarFrame.size,
            leftInset: params.layout.safeInsets.left,
            rightInset: params.layout.safeInsets.right,
            additionalSideInsets: params.layout.additionalInsets,
            bottomInset: bottomInset,
            transition: transition
        )
        
        // Update tab bar visibility based on toolbar presence
        transition.updateAlpha(node: self.tabBarNode, alpha: params.toolbar == nil ? 1.0 : 0.0)
        
        // Update disabled overlay
        transition.updateFrame(node: self.disabledOverlayNode, frame: tabBarFrame)
        
        // Handle Toolbar
        let toolbarHeight = 50.0 + params.layout.insets(options: options).bottom
        let toolbarFrame = CGRect(origin: CGPoint(x: 0.0, y: params.layout.size.height - toolbarHeight), size: CGSize(width: params.layout.size.width, height: toolbarHeight))
        
        if let toolbar = params.toolbar {
            if let toolbarNode = self.toolbarNode {
                transition.updateFrame(node: toolbarNode, frame: toolbarFrame)
                toolbarNode.updateLayout(size: toolbarFrame.size, leftInset: params.layout.safeInsets.left, rightInset: params.layout.safeInsets.right, additionalSideInsets: params.layout.additionalInsets, bottomInset: bottomInset, toolbar: toolbar, transition: transition)
            } else {
                let toolbarNode = ToolbarNode(theme: ToolbarTheme(theme: self.theme), displaySeparator: true, left: { [weak self] in
                    self?.toolbarActionSelected(.left)
                }, right: { [weak self] in
                    self?.toolbarActionSelected(.right)
                }, middle: { [weak self] in
                    self?.toolbarActionSelected(.middle)
                })
                toolbarNode.frame = toolbarFrame
                toolbarNode.updateLayout(size: toolbarFrame.size, leftInset: params.layout.safeInsets.left, rightInset: params.layout.safeInsets.right, additionalSideInsets: params.layout.additionalInsets, bottomInset: bottomInset, toolbar: toolbar, transition: .immediate)
                self.addSubnode(toolbarNode)
                self.toolbarNode = toolbarNode
                if transition.isAnimated {
                    toolbarNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }
        } else if let toolbarNode = self.toolbarNode {
            self.toolbarNode = nil
            transition.updateAlpha(node: toolbarNode, alpha: 0.0, completion: { [weak toolbarNode] _ in
                toolbarNode?.removeFromSupernode()
            })
        }
        
        // Return the bottom inset
        return self.tabBarHidden ? 0.0 : tabBarHeight
    }
    
    func frameForControllerTab(at index: Int) -> CGRect? {
        guard let itemFrame = self.tabBarNode.frameForControllerTab(at: index) else {
            return nil
        }
        return self.view.convert(itemFrame, from: self.tabBarNode.view)
    }
    
    func isPointInsideContentArea(point: CGPoint) -> Bool {
        guard let tabBarView = self.tabBarNode.view else {
            return false
        }
        if point.y < tabBarView.frame.minY {
            return true
        }
        return false
    }
    
    func updateTabBarItems(items: [TabBarNodeItem]) {
        self.tabBarItems = items
        self.requestUpdate()
    }
    
    func updateSelectedIndex(index: Int) {
        self.selectedIndex = index
        self.isChangingSelectedIndex = true
        self.requestUpdate()
    }
}