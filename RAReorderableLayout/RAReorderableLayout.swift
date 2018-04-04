//
//  RAReorderableLayout.swift
//  RAReorderableLayout
//
//  Created by Ryo Aoyama on 10/12/14.
//  Copyright (c) 2014 Ryo Aoyama. All rights reserved.
//

import UIKit

@objc public protocol RAReorderableLayoutDelegate: UICollectionViewDelegateFlowLayout {
    @objc optional func collectionView(_ collectionView: UICollectionView, at indexPath: IndexPath, willMoveTo toIndexPath: IndexPath)
    @objc optional func collectionView(_ collectionView: UICollectionView, at indexPath: IndexPath, didMoveTo toIndexPath: IndexPath)
    
    @objc optional func collectionView(_ collectionView: UICollectionView, allowMoveAt indexPath: IndexPath) -> Bool
    @objc optional func collectionView(_ collectionView: UICollectionView, at indexPath: IndexPath, canMoveTo toIndexPath: IndexPath) -> Bool
    
    @objc optional func collectionView(_ collectionView: UICollectionView, willRemoveAt indexPath: IndexPath)
    @objc optional func collectionView(_ collectionView: UICollectionView, didRemoveAt indexPath: IndexPath)
    @objc optional func collectionView(_ collectionView: UICollectionView, canRemoveAt indexPath: IndexPath) -> Bool
    
    @objc optional func collectionView(_ collectionView: UICollectionView, collectionViewLayout layout: RAReorderableLayout, willBeginDraggingItemAt indexPath: IndexPath)
    @objc optional func collectionView(_ collectionView: UICollectionView, collectionViewLayout layout: RAReorderableLayout, didBeginDraggingItemAt indexPath: IndexPath)
    @objc optional func collectionView(_ collectionView: UICollectionView, collectionViewLayout layout: RAReorderableLayout, willEndDraggingItemTo indexPath: IndexPath)
    @objc optional func collectionView(_ collectionView: UICollectionView, collectionViewLayout layout: RAReorderableLayout, didEndDraggingItemTo indexPath: IndexPath)
}

@objc public protocol RAReorderableLayoutDataSource: UICollectionViewDataSource {
    @objc optional func collectionView(_ collectionView: UICollectionView, reorderingItemAlphaInSection section: Int) -> CGFloat
    @objc optional func scrollTrigerEdgeInsetsInCollectionView(_ collectionView: UICollectionView) -> UIEdgeInsets
    @objc optional func scrollTrigerPaddingInCollectionView(_ collectionView: UICollectionView) -> UIEdgeInsets
    @objc optional func scrollSpeedValueInCollectionView(_ collectionView: UICollectionView) -> CGFloat
}

public class RAReorderableLayout: UICollectionViewFlowLayout, UIGestureRecognizerDelegate {
    
    private enum Direction {
        case toTop
        case toEnd
        case stay
        
        func scrollValue(speedValue: CGFloat, percentage: CGFloat) -> CGFloat {
            var value: CGFloat = 0.0
            switch self {
            case .toTop:
                value = -speedValue
            case .toEnd:
                value = speedValue
            case .stay:
                return 0
            }
            
            let proofedPercentage: CGFloat = max(min(1.0, percentage), 0)
            return value * proofedPercentage
        }
    }
    
    private enum actionType {
        case normal
        case removed
    }
    
    public weak var delegate: RAReorderableLayoutDelegate? {
        get { return collectionView?.delegate as? RAReorderableLayoutDelegate }
        set { collectionView?.delegate = delegate }
    }
    
    public weak var datasource: RAReorderableLayoutDataSource? {
        set { collectionView?.delegate = delegate }
        get { return collectionView?.dataSource as? RAReorderableLayoutDataSource }
    }
    
    private var displayLink: CADisplayLink?
    
    private var longPress: UILongPressGestureRecognizer?
    
    private var panGesture: UIPanGestureRecognizer?
    
    private var continuousScrollDirection: Direction = .stay
    
    private var cellFakeView: RACellFakeView?
    
    private var panTranslation: CGPoint?
    
    private var fakeCellCenter: CGPoint?
    
    public var trigerInsets: UIEdgeInsets = UIEdgeInsetsMake(100.0, 100.0, 100.0, 100.0)
    
    public var trigerPadding: UIEdgeInsets = .zero
    
    public var scrollSpeedValue: CGFloat = 10.0
    
    private var offsetFromTop: CGFloat {
        let contentOffset = collectionView!.contentOffset
        return scrollDirection == .vertical ? contentOffset.y : contentOffset.x
    }
    
    private var insetsTop: CGFloat {
        let contentInsets = collectionView!.contentInset
        return scrollDirection == .vertical ? contentInsets.top : contentInsets.left
    }
    
    private var insetsEnd: CGFloat {
        let contentInsets = collectionView!.contentInset
        return scrollDirection == .vertical ? contentInsets.bottom : contentInsets.right
    }
    
    private var contentLength: CGFloat {
        let contentSize = collectionView!.contentSize
        return scrollDirection == .vertical ? contentSize.height : contentSize.width
    }
    
    private var collectionViewLength: CGFloat {
        let collectionViewSize = collectionView!.bounds.size
        return scrollDirection == .vertical ? collectionViewSize.height : collectionViewSize.width
    }
    
    private var fakeCellTopEdge: CGFloat? {
        if let fakeCell = cellFakeView {
            return scrollDirection == .vertical ? fakeCell.frame.minY : fakeCell.frame.minX
        }
        return nil
    }
    
    private var fakeCellEndEdge: CGFloat? {
        if let fakeCell = cellFakeView {
            return scrollDirection == .vertical ? fakeCell.frame.maxY : fakeCell.frame.maxX
        }
        return nil
    }
    
    private var triggerInsetTop: CGFloat {
        return scrollDirection == .vertical ? trigerInsets.top : trigerInsets.left
    }
    
    private var triggerInsetEnd: CGFloat {
        return scrollDirection == .vertical ? trigerInsets.top : trigerInsets.left
    }
    
    private var triggerPaddingTop: CGFloat {
        return scrollDirection == .vertical ? trigerPadding.top : trigerPadding.left
    }
    
    private var triggerPaddingEnd: CGFloat {
        return scrollDirection == .vertical ? trigerPadding.bottom : trigerPadding.right
    }

    private var observation: NSKeyValueObservation?

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configureObserver()
    }
    
    public override init() {
        super.init()
        configureObserver()
    }
    
    deinit {
        observation?.invalidate()
    }
    
    override public func prepare() {
        super.prepare()
        
        // scroll trigger insets
        if let insets = datasource?.scrollTrigerEdgeInsetsInCollectionView?(self.collectionView!) {
            trigerInsets = insets
        }
        
        // scroll trier padding
        if let padding = datasource?.scrollTrigerPaddingInCollectionView?(self.collectionView!) {
            trigerPadding = padding
        }
        
        // scroll speed value
        if let speed = datasource?.scrollSpeedValueInCollectionView?(collectionView!) {
            scrollSpeedValue = speed
        }
    }
    
    override public func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let attributesArray = super.layoutAttributesForElements(in: rect) else { return nil }
        guard let cellFakeView = cellFakeView else { return nil }

        attributesArray.filter {
            $0.representedElementCategory == .cell
        }.filter {
            $0.indexPath == cellFakeView.indexPath
        }.forEach {
            // reordering cell alpha
            $0.alpha = datasource?.collectionView?(collectionView!, reorderingItemAlphaInSection: $0.indexPath.section) ?? 0
        }

        return attributesArray
    }
    
    private func configureObserver() {
        observation = observe(\.collectionView) { (me, change) in
            me.setUpGestureRecognizers()
        }
    }
    
    private func setUpDisplayLink() {
        guard displayLink == nil else {
            return
        }
        
        displayLink = CADisplayLink(target: self, selector: #selector(RAReorderableLayout.continuousScroll))
        displayLink!.add(to: RunLoop.main, forMode: .commonModes)
    }
    
    private func invalidateDisplayLink() {
        continuousScrollDirection = .stay
        displayLink?.invalidate()
        displayLink = nil
    }
    
    // begein scroll
    private func beginScrollIfNeeded() {
        guard cellFakeView != nil else { return }
        guard let fakeCellTopEdge = fakeCellTopEdge,
            let fakeCellEndEdge = fakeCellEndEdge else { return }
        
        if  fakeCellTopEdge <= offsetFromTop + triggerPaddingTop + triggerInsetTop {
            continuousScrollDirection = .toTop
            setUpDisplayLink()
        } else if fakeCellEndEdge >= offsetFromTop + collectionViewLength - triggerPaddingEnd - triggerInsetEnd {
            continuousScrollDirection = .toEnd
            setUpDisplayLink()
        } else {
            invalidateDisplayLink()
        }
    }
    
    // move item
    private func moveItemIfNeeded() {
        guard let fakeCell = cellFakeView,
            let atIndexPath = fakeCell.indexPath,
            let toIndexPath = collectionView!.indexPathForItem(at: fakeCell.center) else {
                return
        }
        
        guard atIndexPath != toIndexPath else { return }
        
        // can move item
        if let canMove = delegate?.collectionView?(collectionView!, at: atIndexPath, canMoveTo: toIndexPath), !canMove {
            return
        }
        
        // will move item
        delegate?.collectionView?(collectionView!, at: atIndexPath, willMoveTo: toIndexPath)
        
        let attribute = self.layoutAttributesForItem(at: toIndexPath)!
        collectionView!.performBatchUpdates({
            fakeCell.indexPath = toIndexPath
            fakeCell.cellFrame = attribute.frame
            fakeCell.changeBoundsIfNeeded(bounds: attribute.bounds)
            
            self.collectionView!.deleteItems(at: [atIndexPath])
            self.collectionView!.insertItems(at: [toIndexPath])
            
            // did move item
            self.delegate?.collectionView?(self.collectionView!, at: atIndexPath, didMoveTo: toIndexPath)
            }, completion:nil)
    }
    
    @objc internal func continuousScroll() {
        guard let fakeCell = cellFakeView else { return }
        
        let percentage = calcTriggerPercentage()
        var scrollRate = continuousScrollDirection.scrollValue(speedValue: self.scrollSpeedValue, percentage: percentage)
        
        let offset = offsetFromTop
        let length = collectionViewLength
        
        if contentLength + insetsTop + insetsEnd <= length {
            return
        }
        
        if offset + scrollRate <= -insetsTop {
            scrollRate = -insetsTop - offset
        } else if offset + scrollRate >= contentLength + insetsEnd - length {
            scrollRate = contentLength + insetsEnd - length - offset
        }
        
        collectionView!.performBatchUpdates({
            if self.scrollDirection == .vertical {
                self.fakeCellCenter?.y += scrollRate
                fakeCell.center.y = self.fakeCellCenter!.y + self.panTranslation!.y
                self.collectionView?.contentOffset.y += scrollRate
            }else {
                self.fakeCellCenter?.x += scrollRate
                fakeCell.center.x = self.fakeCellCenter!.x + self.panTranslation!.x
                self.collectionView?.contentOffset.x += scrollRate
            }
            }, completion: nil)
        
        moveItemIfNeeded()
    }
    
    private func calcTriggerPercentage() -> CGFloat {
        guard cellFakeView != nil else { return 0 }
        
        let offset = offsetFromTop
        let offsetEnd = offsetFromTop + collectionViewLength
        let paddingEnd = triggerPaddingEnd
        
        var percentage: CGFloat = 0
        
        if self.continuousScrollDirection == .toTop {
            if let fakeCellEdge = fakeCellTopEdge {
                percentage = 1.0 - ((fakeCellEdge - (offset + triggerPaddingTop)) / triggerInsetTop)
            }
        }else if continuousScrollDirection == .toEnd {
            if let fakeCellEdge = fakeCellEndEdge {
                percentage = 1.0 - (((insetsTop + offsetEnd - paddingEnd) - (fakeCellEdge + insetsTop)) / triggerInsetEnd)
            }
        }
        
        percentage = min(1.0, percentage)
        percentage = max(0, percentage)
        return percentage
    }
    
    // gesture recognizers
    private func setUpGestureRecognizers() {
        guard let collectionView = collectionView else { return }
        
        longPress = UILongPressGestureRecognizer(target: self, action: #selector(RAReorderableLayout.handleLongPress(longPress:)))
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(RAReorderableLayout.handlePanGesture(pan:)))
        longPress?.delegate = self
        panGesture?.delegate = self
        panGesture?.maximumNumberOfTouches = 1
        let gestures = collectionView.gestureRecognizers
        gestures?.forEach { gestureRecognizer in
            if gestureRecognizer is UILongPressGestureRecognizer {
                gestureRecognizer.require(toFail: self.longPress!)
            }
            collectionView.addGestureRecognizer(self.longPress!)
            collectionView.addGestureRecognizer(self.panGesture!)
        }
    }
    
    public func cancelDrag() {
        cancelDrag(toIndexPath: nil)
    }
    
    private func cancelDrag(toIndexPath: IndexPath!, type: actionType = .normal) {
        guard cellFakeView != nil else { return }
        
        // will end drag item
        if type == .normal {
            delegate?.collectionView?(collectionView!, collectionViewLayout: self, willEndDraggingItemTo: toIndexPath)
        }
        
        collectionView?.scrollsToTop = true
        
        fakeCellCenter = nil
        
        invalidateDisplayLink()
        
        let completionHandler = { [unowned self] in
            self.cellFakeView!.removeFromSuperview()
            self.cellFakeView = nil
            self.invalidateLayout()
            
            // did end drag item
            if type == .normal {
                self.delegate?.collectionView?(self.collectionView!, collectionViewLayout: self, didEndDraggingItemTo: toIndexPath)
            }
        }
        
        switch type {
        case .normal:
            cellFakeView!.pushBackView(completion: completionHandler)
        case .removed:
            cellFakeView!.eraseView(completion: completionHandler)
        }
    }
    
    // long press gesture
    @objc internal func handleLongPress(longPress: UILongPressGestureRecognizer!) {
        let location = longPress.location(in: collectionView)
        var indexPath: IndexPath? = collectionView?.indexPathForItem(at: location)
        
        if let cellFakeView = cellFakeView {
            indexPath = cellFakeView.indexPath
        }
        
        if indexPath == nil { return }
        
        switch longPress.state {
        case .began:
            // will begin drag item
            delegate?.collectionView?(collectionView!, collectionViewLayout: self, willBeginDraggingItemAt: indexPath!)
            
            collectionView?.scrollsToTop = false
            
            let currentCell = collectionView?.cellForItem(at: indexPath!)
            
            cellFakeView = RACellFakeView(cell: currentCell!)
            cellFakeView!.indexPath = indexPath
            cellFakeView!.originalCenter = currentCell?.center
            cellFakeView!.cellFrame = layoutAttributesForItem(at: indexPath!)!.frame
            collectionView?.addSubview(cellFakeView!)
            
            fakeCellCenter = cellFakeView!.center
            
            invalidateLayout()
            
            cellFakeView?.pushFowardView()
            
            // did begin drag item
            delegate?.collectionView?(collectionView!, collectionViewLayout: self, didBeginDraggingItemAt: indexPath!)
        case .cancelled:
            cancelDrag(toIndexPath: indexPath)
        case .ended:
            let removed: actionType = removeItemIfNeeded() ? .removed : .normal
            cancelDrag(toIndexPath: indexPath, type: removed)
        default:
            break
        }
    }
    
    // pan gesture
    @objc func handlePanGesture(pan: UIPanGestureRecognizer!) {
        panTranslation = pan.translation(in: collectionView!)
        if let cellFakeView = cellFakeView,
            let fakeCellCenter = fakeCellCenter,
            let panTranslation = panTranslation {
            switch pan.state {
            case .changed:
                cellFakeView.center.x = fakeCellCenter.x + panTranslation.x
                cellFakeView.center.y = fakeCellCenter.y + panTranslation.y
                
                handleRemovability()
                beginScrollIfNeeded()
                moveItemIfNeeded()
            case .cancelled:
                invalidateDisplayLink()
            case .ended:
                invalidateDisplayLink()
            default:
                break
            }
        }
    }
    
    // gesture recognize delegate
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // allow move item
        let location = gestureRecognizer.location(in: collectionView)
        if let indexPath = collectionView?.indexPathForItem(at: location),
            delegate?.collectionView?(collectionView!, allowMoveAt: indexPath) == false {
            return false
        }
        
        switch gestureRecognizer {
        case longPress:
            if (collectionView!.panGestureRecognizer.state != .possible && collectionView!.panGestureRecognizer.state != .failed) {
                return false
            }
        case panGesture:
            if (longPress!.state == .possible || longPress!.state == .failed) {
                return false
            }
        default:
            return true
        }

        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case longPress:
            if otherGestureRecognizer.isEqual(panGesture) {
                return true
            }
        case panGesture:
            if otherGestureRecognizer.isEqual(longPress) {
                return true
            }else {
                return false
            }
        case collectionView?.panGestureRecognizer:
            if (longPress!.state != .possible || longPress!.state != .failed) {
                return false
            }
        default:
            return true
        }

        return true
    }
}

private extension RAReorderableLayout {
    private func handleRemovability() {
        let overlapped = isOverlapped(view: collectionView, withView: cellFakeView)
        let removable = delegate?.collectionView?(collectionView!, canRemoveAt: cellFakeView!.indexPath!) ?? false

        if !overlapped && removable {
            cellFakeView?.alpha = 0.5
        } else {
            cellFakeView?.alpha = 1.0
        }
    }
    
    private func removeItemIfNeeded() -> Bool {
        let overlapped = isOverlapped(view: collectionView, withView: cellFakeView)
        let removable = delegate?.collectionView?(collectionView!, canRemoveAt: cellFakeView!.indexPath!) ?? false
        if !overlapped && removable {
            // will remove the item
            self.delegate?.collectionView?(self.collectionView!, willRemoveAt: self.cellFakeView!.indexPath!)
            collectionView!.performBatchUpdates({
                // Remove the item only if the delegate object have the callback.
                if let callback = self.delegate?.collectionView(_: didRemoveAt:) {
                    self.collectionView!.deleteItems(at: [self.cellFakeView!.indexPath!])
                    
                    // did remove the item
                    callback(self.collectionView!, self.cellFakeView!.indexPath!)
                }
                }, completion:nil)
            return true
        } else {
            return false
        }
    }

    private func isOverlapped(view: UIView?, withView otherView: UIView?) -> Bool {
        if let view = view, let otherView = otherView {
            let viewFrame = view.frame
            let otherViewFrame = view.convert(otherView.frame, to: view.superview)
            return viewFrame.intersects(otherViewFrame)
        }
        return false
    }
}

private class RACellFakeView: UIView {
    
    weak var cell: UICollectionViewCell?
    
    var cellFakeImageView: UIImageView?
    
    var cellFakeHightedView: UIImageView?
    
    var indexPath: IndexPath?
    
    var originalCenter: CGPoint?
    
    var cellFrame: CGRect?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    init(cell: UICollectionViewCell) {
        super.init(frame: cell.frame)
        
        self.cell = cell
        
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 0)
        layer.shadowOpacity = 0
        layer.shadowRadius = 5.0
        layer.shouldRasterize = false
        
        cellFakeImageView = UIImageView(frame: self.bounds)
        cellFakeImageView?.contentMode = .scaleAspectFill
        cellFakeImageView?.autoresizingMask = [.flexibleWidth , .flexibleHeight]
        
        cellFakeHightedView = UIImageView(frame: self.bounds)
        cellFakeHightedView?.contentMode = UIViewContentMode.scaleAspectFill
        cellFakeHightedView?.autoresizingMask = [.flexibleWidth , .flexibleHeight]
        
        cell.isHighlighted = true
        cellFakeHightedView?.image = getCellImage()
        cell.isHighlighted = false
        cellFakeImageView?.image = getCellImage()
        
        addSubview(cellFakeImageView!)
        addSubview(cellFakeHightedView!)
    }
    
    func changeBoundsIfNeeded(bounds: CGRect) {
        if bounds.equalTo(bounds) { return }
        
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                self.bounds = bounds
            },
            completion: nil
        )
    }
    
    func pushFowardView() {
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                self.center = self.originalCenter!
                self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                self.cellFakeHightedView!.alpha = 0;
                let shadowAnimation = CABasicAnimation(keyPath: "shadowOpacity")
                shadowAnimation.fromValue = 0
                shadowAnimation.toValue = 0.7
                shadowAnimation.isRemovedOnCompletion = false
                shadowAnimation.fillMode = kCAFillModeForwards
                self.layer.add(shadowAnimation, forKey: "applyShadow")
            },
            completion: { _ in
                self.cellFakeHightedView?.removeFromSuperview()
            }
        )
    }
    
    func pushBackView(completion: (()->Void)?) {
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                self.transform = CGAffineTransform.identity
                self.frame = self.cellFrame!
                let shadowAnimation = CABasicAnimation(keyPath: "shadowOpacity")
                shadowAnimation.fromValue = 0.7
                shadowAnimation.toValue = 0
                shadowAnimation.isRemovedOnCompletion = false
                shadowAnimation.fillMode = kCAFillModeForwards
                self.layer.add(shadowAnimation, forKey: "removeShadow")
            },
            completion: { _ in
                completion?()
            }
        )
    }
    
    func eraseView(completion: (()->Void)?) {
        self.alpha = 1.0
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: { 
                self.transform = CGAffineTransform.identity
                self.alpha = 0.0
            },
            completion: { _ in
                completion?()
            }
        )
    }
    
    private func getCellImage() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(cell!.bounds.size, false, UIScreen.main.scale * 2)
        defer { UIGraphicsEndImageContext() }

        cell!.drawHierarchy(in: cell!.bounds, afterScreenUpdates: true)
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
}

// Convenience method
private func ~= (obj:NSObjectProtocol?, r:UIGestureRecognizer) -> Bool
{
    return r.isEqual(obj)
}
