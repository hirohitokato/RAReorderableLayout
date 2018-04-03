//
//  RAReorderableLayout.swift
//  RAReorderableLayout
//
//  Created by Ryo Aoyama on 10/12/14.
//  Copyright (c) 2014 Ryo Aoyama. All rights reserved.
//

import UIKit

@objc public protocol RAReorderableLayoutDelegate: UICollectionViewDelegateFlowLayout {
    @objc optional func collectionView(collectionView: UICollectionView, atIndexPath: NSIndexPath, willMoveToIndexPath toIndexPath: NSIndexPath)
    @objc optional func collectionView(collectionView: UICollectionView, atIndexPath: NSIndexPath, didMoveToIndexPath toIndexPath: NSIndexPath)
    
    @objc optional func collectionView(collectionView: UICollectionView, allowMoveAtIndexPath indexPath: NSIndexPath) -> Bool
    @objc optional func collectionView(collectionView: UICollectionView, atIndexPath: NSIndexPath, canMoveToIndexPath: NSIndexPath) -> Bool
    
    @objc optional func collectionView(collectionView: UICollectionView, willRemoveAtIndexPath indexPath: NSIndexPath)
    @objc optional func collectionView(collectionView: UICollectionView, didRemoveAtIndexPath indexPath: NSIndexPath)
    @objc optional func collectionView(collectionView: UICollectionView, canRemoveAtIndexPath indexPath: NSIndexPath) -> Bool
    
    @objc optional func collectionView(collectionView: UICollectionView, collectionViewLayout layout: RAReorderableLayout, willBeginDraggingItemAtIndexPath indexPath: NSIndexPath)
    @objc optional func collectionView(collectionView: UICollectionView, collectionViewLayout layout: RAReorderableLayout, didBeginDraggingItemAtIndexPath indexPath: NSIndexPath)
    @objc optional func collectionView(collectionView: UICollectionView, collectionViewLayout layout: RAReorderableLayout, willEndDraggingItemToIndexPath indexPath: NSIndexPath)
    @objc optional func collectionView(collectionView: UICollectionView, collectionViewLayout layout: RAReorderableLayout, didEndDraggingItemToIndexPath indexPath: NSIndexPath)
}

@objc public protocol RAReorderableLayoutDataSource: UICollectionViewDataSource {
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int
    
    @objc optional func collectionView(collectionView: UICollectionView, reorderingItemAlphaInSection section: Int) -> CGFloat
    @objc optional func scrollTrigerEdgeInsetsInCollectionView(collectionView: UICollectionView) -> UIEdgeInsets
    @objc optional func scrollTrigerPaddingInCollectionView(collectionView: UICollectionView) -> UIEdgeInsets
    @objc optional func scrollSpeedValueInCollectionView(collectionView: UICollectionView) -> CGFloat
}

public class RAReorderableLayout: UICollectionViewFlowLayout, UIGestureRecognizerDelegate {
    
    private enum direction {
        case toTop
        case toEnd
        case stay
        
        private func scrollValue(speedValue: CGFloat, percentage: CGFloat) -> CGFloat {
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
    
    private var continuousScrollDirection: direction = .stay
    
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
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configureObserver()
    }
    
    public override init() {
        super.init()
        configureObserver()
    }
    
    deinit {
        removeObserver(self, forKeyPath: "collectionView")
    }
    
    override public func prepare() {
        super.prepare()
        
        // scroll trigger insets
        if let insets = datasource?.scrollTrigerEdgeInsetsInCollectionView?(collectionView: self.collectionView!) {
            trigerInsets = insets
        }
        
        // scroll trier padding
        if let padding = datasource?.scrollTrigerPaddingInCollectionView?(collectionView: self.collectionView!) {
            trigerPadding = padding
        }
        
        // scroll speed value
        if let speed = datasource?.scrollSpeedValueInCollectionView?(collectionView: collectionView!) {
            scrollSpeedValue = speed
        }
    }
    
    override public func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let attributesArray = super.layoutAttributesForElements(in: rect) else { return nil }

        attributesArray.filter {
            $0.representedElementCategory == .Cell
        }.filter {
            $0.indexPath == cellFakeView?.indexPath
        }.forEach {
            // reordering cell alpha
            $0.alpha = datasource?.collectionView?(collectionView!, reorderingItemAlphaInSection: $0.indexPath.section) ?? 0
        }

        return attributesArray
    }
    
    public override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutableRawPointer) {
        if keyPath == "collectionView" {
            setUpGestureRecognizers()
        }else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
    
    private func configureObserver() {
        addObserver(self, forKeyPath: "collectionView", options: [], context: nil)
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
        if cellFakeView == nil { return }
        
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
            atIndexPath = fakeCell.indexPath,
            toIndexPath = collectionView!.indexPathForItemAtPoint(fakeCell.center) else {
                return
        }
        
        guard !atIndexPath.isEqual(toIndexPath) else { return }
        
        // can move item
        if let canMove = delegate?.collectionView?(collectionView!, atIndexPath: atIndexPath, canMoveToIndexPath: toIndexPath), !canMove {
            return
        }
        
        // will move item
        delegate?.collectionView?(collectionView!, atIndexPath: atIndexPath, willMoveToIndexPath: toIndexPath)
        
        let attribute = self.layoutAttributesForItem(at: toIndexPath)!
        collectionView!.performBatchUpdates({
            fakeCell.indexPath = toIndexPath
            fakeCell.cellFrame = attribute.frame
            fakeCell.changeBoundsIfNeeded(bounds: attribute.bounds)
            
            self.collectionView!.deleteItemsAtIndexPaths([atIndexPath])
            self.collectionView!.insertItems(at: [toIndexPath])
            
            // did move item
            self.delegate?.collectionView?(self.collectionView!, atIndexPath: atIndexPath, didMoveToIndexPath: toIndexPath)
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
        
        longPress = UILongPressGestureRecognizer(target: self, action: #selector(RAReorderableLayout.handleLongPress(_:)))
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(RAReorderableLayout.handlePanGesture(_:)))
        longPress?.delegate = self
        panGesture?.delegate = self
        panGesture?.maximumNumberOfTouches = 1
        let gestures: NSArray! = collectionView.gestureRecognizers
        gestures.enumerateObjectsUsingBlock { gestureRecognizer, index, finish in
            if gestureRecognizer is UILongPressGestureRecognizer {
                gestureRecognizer.requireGestureRecognizerToFail(self.longPress!)
            }
            collectionView.addGestureRecognizer(self.longPress!)
            collectionView.addGestureRecognizer(self.panGesture!)
        }
    }
    
    public func cancelDrag() {
        cancelDrag(toIndexPath: nil)
    }
    
    private func cancelDrag(toIndexPath toIndexPath: NSIndexPath!, type: actionType = .normal) {
        guard cellFakeView != nil else { return }
        
        // will end drag item
        if type == .normal {
            delegate?.collectionView?(collectionView!, collectionViewLayout: self, willEndDraggingItemToIndexPath: toIndexPath)
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
                self.delegate?.collectionView?(self.collectionView!, collectionViewLayout: self, didEndDraggingItemToIndexPath: toIndexPath)
            }
        }
        
        switch type {
        case .normal:
            cellFakeView!.pushBackView(completionHandler)
        case .removed:
            cellFakeView!.eraseView(completionHandler)
        }
    }
    
    // long press gesture
    internal func handleLongPress(longPress: UILongPressGestureRecognizer!) {
        let location = longPress.locationInView(collectionView)
        var indexPath: NSIndexPath? = collectionView?.indexPathForItemAtPoint(location)
        
        if let cellFakeView = cellFakeView {
            indexPath = cellFakeView.indexPath
        }
        
        if indexPath == nil { return }
        
        switch longPress.state {
        case .Began:
            // will begin drag item
            delegate?.collectionView?(collectionView!, collectionViewLayout: self, willBeginDraggingItemAtIndexPath: indexPath!)
            
            collectionView?.scrollsToTop = false
            
            let currentCell = collectionView?.cellForItemAtIndexPath(indexPath!)
            
            cellFakeView = RACellFakeView(cell: currentCell!)
            cellFakeView!.indexPath = indexPath
            cellFakeView!.originalCenter = currentCell?.center
            cellFakeView!.cellFrame = layoutAttributesForItemAtIndexPath(indexPath!)!.frame
            collectionView?.addSubview(cellFakeView!)
            
            fakeCellCenter = cellFakeView!.center
            
            invalidateLayout()
            
            cellFakeView?.pushFowardView()
            
            // did begin drag item
            delegate?.collectionView?(collectionView!, collectionViewLayout: self, didBeginDraggingItemAtIndexPath: indexPath!)
        case .Cancelled:
            cancelDrag(toIndexPath: indexPath)
        case .Ended:
            let removed: actionType = removeItemIfNeeded() ? .removed : .normal
            cancelDrag(toIndexPath: indexPath, type: removed)
        default:
            break
        }
    }
    
    // pan gesture
    func handlePanGesture(pan: UIPanGestureRecognizer!) {
        panTranslation = pan.translationInView(collectionView!)
        if let cellFakeView = cellFakeView,
            fakeCellCenter = fakeCellCenter,
            panTranslation = panTranslation {
            switch pan.state {
            case .Changed:
                cellFakeView.center.x = fakeCellCenter.x + panTranslation.x
                cellFakeView.center.y = fakeCellCenter.y + panTranslation.y
                
                handleRemovability()
                beginScrollIfNeeded()
                moveItemIfNeeded()
            case .Cancelled:
                invalidateDisplayLink()
            case .Ended:
                invalidateDisplayLink()
            default:
                break
            }
        }
    }
    
    // gesture recognize delegate
    public func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
        // allow move item
        let location = gestureRecognizer.locationInView(collectionView)
        if let indexPath = collectionView?.indexPathForItemAtPoint(location) where
            delegate?.collectionView?(collectionView!, allowMoveAtIndexPath: indexPath) == false {
            return false
        }
        
        switch gestureRecognizer {
        case longPress:
            if (collectionView!.panGestureRecognizer.state != .Possible && collectionView!.panGestureRecognizer.state != .Failed) {
                return false
            }
        case panGesture:
            if (longPress!.state == .Possible || longPress!.state == .Failed) {
                return false
            }
        default:
            return true
        }

        return true
    }
    
    public func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
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
            if (longPress!.state != .Possible || longPress!.state != .Failed) {
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
        let overlapped = isOverlapped(collectionView, withView: cellFakeView)
        let removable = delegate?.collectionView?(collectionView!, canRemoveAtIndexPath: cellFakeView!.indexPath!) ?? false

        if !overlapped && removable {
            cellFakeView?.alpha = 0.5
        } else {
            cellFakeView?.alpha = 1.0
        }
    }
    
    private func removeItemIfNeeded() -> Bool {
        let overlapped = isOverlapped(collectionView, withView: cellFakeView)
        let removable = delegate?.collectionView?(collectionView!, canRemoveAtIndexPath: cellFakeView!.indexPath!) ?? false
        if !overlapped && removable {
            // will remove the item
            self.delegate?.collectionView?(self.collectionView!, willRemoveAtIndexPath: self.cellFakeView!.indexPath!)
            collectionView!.performBatchUpdates({
                // Remove the item only if the delegate object have the callback.
                if let callback = self.delegate?.collectionView(_: didRemoveAtIndexPath:) {
                    self.collectionView!.deleteItemsAtIndexPaths([self.cellFakeView!.indexPath!])
                    
                    // did remove the item
                    callback(self.collectionView!, didRemoveAtIndexPath: self.cellFakeView!.indexPath!)
                }
                }, completion:nil)
            return true
        } else {
            return false
        }
    }

    private func isOverlapped(view: UIView?, withView otherView: UIView?) -> Bool {
        if let view = view, otherView = otherView {
            let viewFrame = view.frame
            let otherViewFrame = view.convertRect(otherView.frame, toView: view.superview)
            return CGRectIntersectsRect(viewFrame, otherViewFrame)
        }
        return false
    }
}

private class RACellFakeView: UIView {
    
    weak var cell: UICollectionViewCell?
    
    var cellFakeImageView: UIImageView?
    
    var cellFakeHightedView: UIImageView?
    
    private var indexPath: NSIndexPath?
    
    private var originalCenter: CGPoint?
    
    private var cellFrame: CGRect?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    init(cell: UICollectionViewCell) {
        super.init(frame: cell.frame)
        
        self.cell = cell
        
        layer.shadowColor = UIColor.blackColor().CGColor
        layer.shadowOffset = CGSizeMake(0, 0)
        layer.shadowOpacity = 0
        layer.shadowRadius = 5.0
        layer.shouldRasterize = false
        
        cellFakeImageView = UIImageView(frame: self.bounds)
        cellFakeImageView?.contentMode = UIViewContentMode.ScaleAspectFill
        cellFakeImageView?.autoresizingMask = [.FlexibleWidth , .FlexibleHeight]
        
        cellFakeHightedView = UIImageView(frame: self.bounds)
        cellFakeHightedView?.contentMode = UIViewContentMode.ScaleAspectFill
        cellFakeHightedView?.autoresizingMask = [.FlexibleWidth , .FlexibleHeight]
        
        cell.highlighted = true
        cellFakeHightedView?.image = getCellImage()
        cell.highlighted = false
        cellFakeImageView?.image = getCellImage()
        
        addSubview(cellFakeImageView!)
        addSubview(cellFakeHightedView!)
    }
    
    func changeBoundsIfNeeded(bounds: CGRect) {
        if CGRectEqualToRect(bounds, bounds) { return }
        
        UIView.animateWithDuration(
            0.3,
            delay: 0,
            options: [.CurveEaseInOut, .BeginFromCurrentState],
            animations: {
                self.bounds = bounds
            },
            completion: nil
        )
    }
    
    func pushFowardView() {
        UIView.animateWithDuration(
            0.3,
            delay: 0,
            options: [.CurveEaseInOut, .BeginFromCurrentState],
            animations: {
                self.center = self.originalCenter!
                self.transform = CGAffineTransformMakeScale(1.1, 1.1)
                self.cellFakeHightedView!.alpha = 0;
                let shadowAnimation = CABasicAnimation(keyPath: "shadowOpacity")
                shadowAnimation.fromValue = 0
                shadowAnimation.toValue = 0.7
                shadowAnimation.removedOnCompletion = false
                shadowAnimation.fillMode = kCAFillModeForwards
                self.layer.addAnimation(shadowAnimation, forKey: "applyShadow")
            },
            completion: { _ in
                self.cellFakeHightedView?.removeFromSuperview()
            }
        )
    }
    
    func pushBackView(completion: (()->Void)?) {
        UIView.animateWithDuration(
            0.3,
            delay: 0,
            options: [.CurveEaseInOut, .BeginFromCurrentState],
            animations: {
                self.transform = CGAffineTransformIdentity
                self.frame = self.cellFrame!
                let shadowAnimation = CABasicAnimation(keyPath: "shadowOpacity")
                shadowAnimation.fromValue = 0.7
                shadowAnimation.toValue = 0
                shadowAnimation.removedOnCompletion = false
                shadowAnimation.fillMode = kCAFillModeForwards
                self.layer.addAnimation(shadowAnimation, forKey: "removeShadow")
            },
            completion: { _ in
                completion?()
            }
        )
    }
    
    func eraseView(completion: (()->Void)?) {
        self.alpha = 1.0
        UIView.animateWithDuration(
            0.3,
            delay: 0,
            options: [.CurveEaseInOut, .BeginFromCurrentState],
            animations: { 
                self.transform = CGAffineTransformIdentity
                self.alpha = 0.0
            },
            completion: { _ in
                completion?()
            }
        )
    }
    
    private func getCellImage() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(cell!.bounds.size, false, UIScreen.mainScreen().scale * 2)
        defer { UIGraphicsEndImageContext() }

        cell!.drawViewHierarchyInRect(cell!.bounds, afterScreenUpdates: true)
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// Convenience method
private func ~= (obj:NSObjectProtocol?, r:UIGestureRecognizer) -> Bool
{
    return r.isEqual(obj)
}
