//
//  Controller.swift
//  Ubiquity
//
//  Created by sagesse on 21/12/2017.
//  Copyright © 2017 SAGESSE. All rights reserved.
//

import UIKit

internal protocol Controller {
    
    /// Base controller craete method
    init(container: Container, source: Source, factory: Factory, parameter: Any?)
}


internal extension Factory {
    /// Templated collection view controller.
    internal class CollectionViewController: UICollectionViewController {
        
        /// Create an instance using class factory.
        public init(factory: Factory) {
            // If did not provide `UICollectionViewLayout`, create failure
            guard let collectionViewLayout = (factory.class(for: "layout") as? UICollectionViewLayout.Type)?.init() else {
                fatalError("The class factory must provide layout!!!")
            }
            
            // Saving all context.
            self.factory = factory
            super.init(collectionViewLayout: collectionViewLayout)
        }
        /// Create an instance for the file.
        public required init?(coder aDecoder: NSCoder) {
            // The class farctory must be provided to create.
            guard let factory = aDecoder.decodeObject(forKey: "factory") as? Factory else {
                return nil
            }
            
            // If did not provide `UICollectionViewLayout`, create failure
            guard let collectionViewLayout = (factory.class(for: "layout") as? UICollectionViewLayout.Type)?.init() else {
                fatalError("The class factory must provide layout!!!")
            }
            
            // Saving all context.
            self.factory = factory
            super.init(collectionViewLayout: collectionViewLayout)
        }
        
        /// The current using of the class factory.
        public let factory: Factory
        
        /// Load the view.
        public override func loadView() {
            super.loadView()
            
            // setup background color.
            view.backgroundColor = .white
            collectionView?.backgroundColor = view.backgroundColor
            
            // setup registered cells for factory.
            factory.mapping(for: "cell").forEach {
                collectionView?.register($0.value, forCellWithReuseIdentifier: $0.key)
            }
        }
    }
}

internal extension Source {
    /// Templated collection view controller.
    internal class CollectionViewController: Factory.CollectionViewController, Controller, ChangeObserver, ExceptionHandling {
        
        /// Create an instance using class factory.
        public required init(container: Container, source: Source, factory: Factory, parameter: Any?) {
            // setup init data
            self.source = source
            self.container = container
            
            super.init(factory: factory)
            
            // if not configure title
            // the title will follow data source change
            super.title = source.title
            super.navigationItem.backBarButtonItem = UIBarButtonItem(title: "Back", style: .done, target: nil, action: nil)
            
            // if the navigation bar disable translucent will have an error offset
            // enabled `extendedLayoutIncludesOpaqueBars` can solve the problem
            self.extendedLayoutIncludesOpaqueBars = true
            self.automaticallyAdjustsScrollViewInsets = true
            
            // add change observer for library.
            self.container.addChangeObserver(self)
        }
        /// Create an instance for the file.
        public required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// When an instance is destroyed, the listener must be removed.
        deinit {
            // Remove chnage observer for library.
            self.container.removeChangeObserver(self)
            
            // Clear all cache request when destroyed
            self.cachingClear()
        }

        /// The current using of the user container.
        open let container: Container
        /// The current using of the data source.
        open var source: Source {
            willSet {
                // Only when in did not set the title will be updated
                super.title = _title ?? newValue.title
            }
        }
        
        /// The current displayed title,
        /// Default title only when in did not set the title will be updated.
        open override var title: String? {
            willSet {
                // If take the initiative to update the title, never use the title
                _title = newValue
            }
        }

        /// Whether the current library has been prepared.
        open var prepared: Bool = false
        /// Whether the current library has been authorization.
        open var authorized: Bool = false
        
        /// Whether allowe item precache.
        open var cachingItemEnabled: Bool = true
        /// Specify the caching item size.
        open var cachingItemSize: CGSize {
            return .init(width: 80, height: 80)
        }
        
        /// The view is loaded successfully, Check access authorization.
        open override func viewDidLoad() {
            super.viewDidLoad()
            
            /// If there is no access authorization, will request access authorize.
            if !authorized {
                ub_initialize(with: self.container, source: self.source)
            }
        }
        
        // MARK: Collection View Configure
        
        /// Returns the section numbers
        open override func numberOfSections(in collectionView: UICollectionView) -> Int {
            // Without access authorization, shows blank
            guard authorized else {
                return 0
            }
            
            return source.numberOfCollections
        }
        
        /// Return the items number in section
        open override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            // Without access authorization, shows blank
            guard authorized else {
                return 0
            }
            
            return source.numberOfAssets(inCollection: section)
        }
        
        open override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            // Fetch asset for source.
            let asset = source.asset(at: indexPath)
            
            // The type must be registered
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ub_reuseIdentifier(with: asset), for: indexPath)
            
            // Apply data for asset.
            if let displayer = cell as? Displayable, prepared {
                asset.map {
                    displayer.apply(with: $0, container: container)
                }
            }
            
            return cell
        }
        
        open override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            // The cell must king of `Displayable`
            guard let displayer = cell as? Displayable, let asset = source.asset(at: indexPath), prepared else {
                return
            }
            
            // Show asset with container and orientation
            displayer.willDisplay(with: asset, container: container, orientation: orientation(container, for: asset))
        }
        
        open override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            // the cell must king of `Displayable`
            guard let displayer = cell as? Displayable, prepared else {
                return
            }
            
            displayer.endDisplay(with: container)
        }
        
        /// Update the cache area when scrolling.
        open override func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // The library is prepared?
            guard prepared else {
                return
            }
            
            // If isTracking is true, is a draging, sync target offset to offset
            if scrollView.isTracking {
                targetContentOffset = scrollView.contentOffset
            }
            
            // Update caching items.
            cachingUpdate()
        }
        
        /// Default is allows scroll to top.
        open override func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            // Update target content offset
            targetContentOffset = .init(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
            
            return true
        }
        
        /// Collecting scrolling information.
        open override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            // Update target content offset
            targetContentOffset = scrollView.contentOffset
        }
        
        /// Collecting scrolling information.
        override func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset newTargetContentOffset: UnsafeMutablePointer<CGPoint>) {
            // Update target content offset
            targetContentOffset = newTargetContentOffset.move()
        }

        // MARK: Controller Loading
        
        /// The controller will request access authorization.
        open func controller(_ container: Container, willAuthorization source: Source) {
            logger.trace?.write()
        }
        /// The controller access authorization has been completed.
        open func controller(_ container: Container, didAuthorization source: Source, error: Error?) {
            logger.trace?.write(error ?? "")
            
            // The error message has been processed by the ExceptionHandling
            guard error == nil else {
                return
            }
            
            // The library authorized successed
            authorized = true
        }
        
        /// The controller will request source data.
        open func controller(_ container: Container, willLoad source: Source) {
            logger.trace?.write()
        }
        /// The controller source data has been completed.
        open func controller(_ container: Container, didLoad source: Source, error: Error?) {
            logger.trace?.write(error ?? "")
            
            // The error message has been processed by the ExceptionHandling
            guard error == nil else {
                return
            }
            
            // Ready to complete
            controller(container, willPrepare: source)
            prepared = true
            controller(container, didPrepare: source)
        }
        
        /// The controller will prepare UI element.
        open func controller(_ container: Container, willPrepare source: Source) {
            logger.trace?.write()
            
            // refresh UI
            self.source = source
            self.collectionView?.reloadData()
        }
        /// The controller prepare UI has been completed.
        open func controller(_ container: Container, didPrepare source: Source) {
            logger.trace?.write()
            
            guard let collectionView = collectionView, prepared, cachingItemEnabled else {
                return
            }
            
            // The layout must be updated to create the elements.
            collectionView.layoutIfNeeded()

            // after the prepared to update the cache information
            targetContentOffset = collectionView.contentOffset

            // Update caching items.
            cachingUpdate()
        }
        
        // MARK: Item Rotation
        
        /// The controller request orientation for asset.
        open func orientation(_ container: Container, for asset: Asset) -> UIImageOrientation {
            return .up
        }
        
        // MARK: Item Caching
        
        /// Clear all cached assets.
        open func cachingClear() {
            // The collectionView must be set
            guard let collectionView = collectionView, prepared, cachingItemEnabled else {
                return
            }
            logger.trace?.write(collectionView.contentOffset)
            
            // Stop cache all
            container.stopCachingImagesForAllAssets()

            // Reset all cache preheat rect.
            previousPreheatRect = .zero
            previousTargetPreheatRect = .zero
        }
        
        /// Update all cached assets with content offset
        open func cachingUpdate() {
            // The collectionView must be set
            guard let collectionView = collectionView, prepared, cachingItemEnabled else {
                return
            }
            //logger.trace?.write(collectionView.contentOffset)

            // Calculated content offset scale.
            let scale: CGVector = ((collectionViewLayout as? UICollectionViewFlowLayout)?.scrollDirection).map {
                switch $0 {
                case .horizontal:
                    return .init(dx: 0.5, dy: 0.0)

                case .vertical:
                    return .init(dx: 0.0, dy: 0.5)
                }
            } ?? .init(dx: 0.5, dy: 0.5)

            // The preheat window is twice the height of the visible rect.
            let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
            let targetVisibleRect = CGRect(origin: self.targetContentOffset, size: collectionView.bounds.size)

            let preheatRect = visibleRect.insetBy(dx: -scale.dx * visibleRect.width, dy: -scale.dy * visibleRect.height)
            let targetPreheatRect = targetVisibleRect.insetBy(dx: -scale.dx * targetVisibleRect.width, dy: -scale.dy * targetVisibleRect.height)

            var changes = [(new: CGRect, old: CGRect)]()

            // Update only if the visible area is significantly different from the last preheated area.
            let delta = max(abs(preheatRect.midY - self.previousPreheatRect.midY) / max(view.bounds.height / 3, 1),
                            abs(preheatRect.midX - self.previousPreheatRect.midX) / max(view.bounds.width / 3, 1))
            if delta >= 1 {
                // need change
                changes.append((preheatRect, self.previousPreheatRect))
                // Store the preheat rect to compare against in the future.
                self.previousPreheatRect = preheatRect
            }

            // Update only if the taget visible area is significantly different from the last preheated area.
            let targetDelta = max(abs(targetPreheatRect.midY - self.previousTargetPreheatRect.midY) / max(view.bounds.height / 3, 1),
                                  abs(targetPreheatRect.midX - self.previousTargetPreheatRect.midX) / max(view.bounds.width / 3, 1))
            if targetDelta >= 1 {
                // need change
                changes.append((targetPreheatRect, self.previousTargetPreheatRect))
                // Store the preheat rect to compare against in the future.
                self.previousTargetPreheatRect = targetPreheatRect
            }

            // is change?
            guard !changes.isEmpty else {
                return
            }
            //logger.trace?.write("preheatRect is change: \(changes)")

            // Compute the assets to start caching and to stop caching.
            let details = _diff(changes.map { $0.new }, changes.map { $0.old })

            let added = details.added.flatMap { cachingItems(in: $0) }
            let removed = details.removed.flatMap { cachingItems(in: $0) }.filter { added.contains($0) }

            // Update the assets the PHCachingImageManager is caching.
            container.startCachingImages(for: added.flatMap { source.asset(at: $0) },
                                         size: cachingItemSize,
                                         mode: .aspectFill,
                                         options: nil)
            
            container.stopCachingImages(for: removed.flatMap { source.asset(at: $0) },
                                        size: cachingItemSize,
                                        mode: .aspectFill,
                                        options: nil)
        }
        
        /// Get the items that needs to be cached in the specified area.
        open func cachingItems(in rect: CGRect) -> [IndexPath] {
            return collectionViewLayout.layoutAttributesForElements(in: rect)?.flatMap {
                guard $0.representedElementCategory == .cell else {
                    return nil
                }
                return $0.indexPath
            } ?? []
        }
        
        // MARK: Library Change Notification
        
        /// Tells your observer that a set of changes has occurred in the Photos library.
        open func library(_ library: Library, didChange change: Change) {
            // if the library no authorized, ignore all change
            guard authorized else {
                return
            }
            logger.debug?.write()
            
            // Fetch the source change.
            guard let newChangeDetails = self.library(library, change: change, fetch: source) else {
                return
            }
            
            // If new source is empty, is a unknow error.
            guard let newSource = newChangeDetails.after else {
                return
            }
            
            // Change notifications may be made on a background queue.
            // Re-dispatch to the main queue to update the UI.
            DispatchQueue.main.async {
                // progressing
                self.library(library, change: change, source: newSource, apply: newChangeDetails)
            }
        }
        
        /// Get the details of the change.
        open func library(_ library: Library, change: Change, fetch source: Source) -> SourceChangeDetails? {
            return nil
        }
        
        /// Apply the change details to UI.
        open func library(_ library: Library, change: Change, source newSource: Source, apply changeDetails: SourceChangeDetails) {
            logger.trace?.write(changeDetails)
            
            // The collectionView must be set
            guard let collectionView = collectionView else {
                return
            }

            // Keep the new fetch result for future use.
            let oldSouce = self.source
            source = newSource

            //  The new data source has no any items.
            guard source.numberOfAssets != 0 else {
                // Emptying all the data & display empty data pages.
                collectionView.reloadData()
                ub_execption(with: container, source: source, error: Exception.notData, animated: true)
                return
            }

            // The library is prepared
            if !prepared {
                prepared = true
            }

            ub_execption(with: container, source: source, error: nil, animated: true)

            // If the old data has no any items, forced update all data.
            guard oldSouce.numberOfAssets != 0 else {
                collectionView.reloadData()
                return
            }

            // If items does no any change, ignore.
            guard changeDetails.hasItemChanges else {
                return
            }

            // If the source does not support incremental changes, must be forced updated all the data.
            guard changeDetails.hasIncrementalChanges else {
                collectionView.reloadData()
                return
            }

            // update collection
            collectionView.performBatchUpdates({

                // For indexes to make sense, updates must be in this order:
                // delete, insert, reload, move

                changeDetails.deleteSections.map { collectionView.deleteSections($0) }
                changeDetails.insertSections.map { collectionView.insertSections($0) }
                changeDetails.reloadSections.map { collectionView.reloadSections($0) }

                changeDetails.moveSections?.forEach { from, to in
                    collectionView.moveSection(from, toSection: to)
                }

                changeDetails.removeItems.map { collectionView.deleteItems(at: $0) }
                changeDetails.insertItems.map { collectionView.insertItems(at: $0) }
                changeDetails.reloadItems.map { collectionView.reloadItems(at: $0) }

                changeDetails.moveItems?.forEach { from, to in
                    collectionView.moveItem(at: from, to: to)
                }

            }, completion: nil)
        }
        
        // MARK: Private Method & Property
        
        // cache configure
        internal private(set) var targetContentOffset: CGPoint = .zero
        internal private(set) var previousPreheatRect: CGRect = .zero
        internal private(set) var previousTargetPreheatRect: CGRect = .zero

        // default configure
        private var _title: String?
    }
}

/// Get the chnage rect
private func _diff(_ new: [CGRect], _ old: [CGRect]) -> (added: [CGRect], removed: [CGRect]) {
    // step1: merge
    let newRects = _union(new)
    let oldRects = _union(old)
    
    // step2: split
    return (
        newRects.flatMap { new in
            _intersection(oldRects.flatMap { old in
                _subtract(new, old)
            })
        },
        oldRects.flatMap { old in
            _intersection(newRects.flatMap { new in
                _subtract(old, new)
            })
        }
    )
}

/// Calculates the area after subtracting the two rect
private func _subtract(_ r1: CGRect, _ r2: CGRect) -> [CGRect] {
    // if not intersect, do not calculate
    guard r1.intersects(r2) else {
        return [r1]
    }
    var result = [CGRect]()

    if r2.minY > r1.minY {
        result.append(.init(x: r1.minX, y: r1.minY, width: r1.width, height: r2.minY - r1.minY))
    }
    if r1.maxY > r2.maxY {
        result.append(.init(x: r1.minX, y: r2.maxY, width: r1.width, height: r1.maxY - r2.maxY))
    }

    return result
}

/// Union all rectangles
private func _union(_ rects: [CGRect]) -> [CGRect] {

    var result = [CGRect]()
    // must sort, otherwise there will be break rect
    rects.sorted(by: { $0.minY < $1.minY }).forEach { rect in
        // is intersects?
        guard let last = result.last, last.intersects(rect) else {
            result.append(rect)
            return
        }
        result[result.count - 1] = last.union(rect)
    }

    return result
}

/// Intersection all rectangles
private func _intersection(_ rects: [CGRect]) -> [CGRect] {

    var result = [CGRect]()
    // must sort, otherwise there will be break rect
    rects.sorted(by: { $0.minY < $1.minY }).forEach { rect in
        // is intersects?
        guard let last = result.last, last.intersects(rect) else {
            result.append(rect)
            return
        }
        result[result.count - 1] = last.intersection(rect)
    }

    return result
}
