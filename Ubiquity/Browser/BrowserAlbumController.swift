//
//  BrowserCollectionController.swift
//  Ubiquity
//
//  Created by sagesse on 16/03/2017.
//  Copyright © 2017 SAGESSE. All rights reserved.
//

import UIKit

/// the asset list in album
internal class BrowserAlbumController: UICollectionViewController, Controller {
    
    required init(container: Container, factory: Factory, source: Source, sender: Any) {
        // setup init data
        _source = source
        _factory = factory
        _container = container
        
        // continue init the UI
        super.init(collectionViewLayout: BrowserAlbumLayout())
        
        // config other
        title = _source.title
        
        // listen albums any change
        _container.library.addChangeObserver(self)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        // clear all cache request when destroyed
        _resetCachedAssets()
        
        // cancel listen change
        _container.library.removeChangeObserver(self)
    }
    
    var container: Container {
        return _container
    }
    
    var factory: Factory {
        return _factory
    }
    
    var source: Source {
        return _source
    }
    
    override func loadView() {
        super.loadView()
        
        // setup controller
        view.backgroundColor = .white
        
        // setup subclass
        object_setClass(collectionView, BrowserAlbumView.self)
        
        // generate header view
        _headerView = {
            // display header only in moment
            guard _source.collectionType == .moment else {
                return nil
            }
            
            let headerView = BrowserAlbumHeader(frame: .init(x: 0, y: 0, width: view.frame.width, height: 48))
            
            // config
            headerView.effect = UIBlurEffect(style: .extraLight)
            headerView.layer.zPosition = -0.5
            
            return headerView
        }()
        
        // generate footer view
        _footerView = {
            let footerView = BrowserAlbumFooter()
            
            // config
            footerView.frame = .init(x: 0, y: 0, width: collectionView?.frame.width ?? 0, height: 48)
            footerView.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
            
            // add to view
            collectionView?.addSubview(footerView)
            
            return footerView
        }()
        
        // setup colleciton view
        collectionView?.backgroundColor = .white
        collectionView?.alwaysBounceVertical = true
        collectionView?.register(BrowserAlbumHeader.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: "HEADER")
        
        // register colleciton cell
        _factory.contents.forEach {
            collectionView?.register($1, forCellWithReuseIdentifier: $0)
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // update with authorization status
        _authorized = false
        _container.library.requestAuthorization { status in
            DispatchQueue.main.async {
                self.reloadData(with: status)
            }
        }
        
        // hi
        collectionView?.alpha = 0
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.t_viewWillAppear(animated)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        // check
        let size = collectionViewLayout.collectionViewContentSize
        guard size != _cachedSize else {
            return
        }
        
        // bounds is change?
        if _cachedSize?.width != size.width {
            _updateHeaderCaches()
        }
        
        // update view
        _updateFooterView()
        _updateHeaderView()
        
        // update cache
        _cachedSize = size
    }
    
    fileprivate var _container: Container
    fileprivate var _factory: Factory
    fileprivate var _source: Source {
        willSet {
            title = newValue.title ?? title
        }
    }
    
    fileprivate var _prepared: Bool = false
    fileprivate var _authorized: Bool = false
    
    fileprivate var _cachedSize: CGSize?
    fileprivate var _cachedHeaderes: Dictionary<Int, CGRect> = [:]
    
    fileprivate var _transitioning: Bool = false
    fileprivate var _targetContentOffset: CGPoint = .zero
    
    fileprivate var _previousPreheatRect: CGRect = .zero
    fileprivate var _previousTargetPreheatRect: CGRect = .zero
    
    fileprivate var _infoView: ErrorView?
    
    fileprivate var _footerView: BrowserAlbumFooter?
    fileprivate var _footerContentInsets: UIEdgeInsets = .zero {
        willSet {
            // get current collection view
            let oldValue = _footerContentInsets
            guard let collectionView = collectionView, newValue != oldValue else {
                return
            }
            
            var edg = collectionView.contentInset
            edg.top += newValue.top - oldValue.top
            edg.left += newValue.left - oldValue.left
            edg.right += newValue.right - oldValue.right
            edg.bottom += newValue.bottom - oldValue.bottom
            collectionView.contentInset = edg
        }
    }
    
    // header
    fileprivate var _headerView: BrowserAlbumHeader?
    fileprivate var _headerInSection: Int = 0
    fileprivate var _headerAllLayoutAttributes: [UICollectionViewLayoutAttributes?]?
}

/// Add header & footer support
extension BrowserAlbumController {
    
    fileprivate func _updateHeaderView() {
        // collection view must be set
        guard let collectionView = collectionView, let headerView = _headerView else {
            return
        }
        // fetch current section
        let offset = collectionView.contentOffset.y + collectionView.contentInset.top
        guard let (section, distance) = _indexForHeader(at: offset) else {
            headerView.section = nil
            headerView.removeFromSuperview()
            return
        }
        // if layout attributes is nil, no header view
        guard let layoutAttributes = _headerAllLayoutAttributes?[section] else {
            headerView.section = nil
            headerView.removeFromSuperview()
            return
        }
        
        // update position
        var frame = layoutAttributes.frame
        frame.origin.y = offset + min(distance - frame.height, 0)
        headerView.frame = frame
        
        // show header view
        if headerView.superview == nil {
            collectionView.insertSubview(headerView, at: 0)
        }
        
        // section is change?
        guard section != headerView.section else {
            return
        }
        
        // update data
        headerView.section = section
        //headerView.contents = _source.collection(at: section)
    }
    
    fileprivate func _updateFooterView() {
        // collection view must be set
        guard let collectionView = collectionView, let footerView = _footerView else {
            return
        }
        
        // the content size is change?
        let contentSize = collectionViewLayout.collectionViewContentSize
        
        var nframe = footerView.frame
        nframe.origin.y = contentSize.height + 0
        nframe.size.width = view.bounds.width
        footerView.frame = nframe
        
        // calculates the height of the current minimum display
        let top = collectionView.contentInset.top - _footerContentInsets.top
        let bottom = collectionView.contentInset.bottom - _footerContentInsets.bottom
        let visableHeight = view.frame.height - top - bottom
        guard visableHeight < contentSize.height else {
            // too small to hide footer view
            _footerView?.alpha = 0
            _footerContentInsets.bottom = 0
            return
        }
        
        // if status has change
        if footerView.alpha != 1 {
            // too large to show footer view & update content insets
            _footerView?.alpha = 1
            _footerContentInsets.bottom = footerView.frame.height
        }
    }
    
    fileprivate func _indexForHeader(at offset: CGFloat) -> (Int, CGFloat)? {
        // header layout attributes must be set
        guard let allLayoutAttributes = _headerAllLayoutAttributes, !allLayoutAttributes.isEmpty else {
            return nil
        }
        
        // the distance from the next setion
        var distance = CGFloat.greatestFiniteMagnitude
        
        // backward: fetch first -n or 0
        var start = min(_headerInSection, allLayoutAttributes.count - 1)
        while start >= 0 {
            // the section has header view?
            guard let layoutAttributes = allLayoutAttributes[start] else {
                start -= 1
                continue
            }
            // is -n or 0?
            guard (layoutAttributes.frame.minY - offset) < 0 else {
                start -= 1
                continue
            }
            break
        }
        
        // is over hide
        guard start >= 0 else {
            return nil
        }
        
        // forward: fetch first +n or inf
        var end = start
        while end < allLayoutAttributes.count {
            // the section has header view?
            guard let layoutAttributes = allLayoutAttributes[end] else {
                end += 1
                continue
            }
            // is +n
            guard (layoutAttributes.frame.minY - offset) > 0 else {
                start = end
                end += 1
                continue
            }
            distance = (layoutAttributes.frame.minY - offset)
            break
        }
        
        // optimize search speed
        _headerInSection = start
        
        // success
        return (start, distance)
    }
    
    fileprivate func _updateHeaderCaches() {
        // collection view must be set
        guard let collectionView = collectionView, _headerView != nil else {
            return
        }
        
        logger.debug?.write()
        
        // fetch all header layout attributes
        _headerAllLayoutAttributes = (0 ..< collectionView.numberOfSections).map {
            collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionElementKindSectionHeader, at: .init(item: 0, section: $0))
        }
    }
}

/// Add asset cache support
extension BrowserAlbumController {
    
    fileprivate func _resetCachedAssets() {
        // clean all cache
        _container.stopCachingImagesForAllAssets()
        _previousPreheatRect = .zero
    }

    fileprivate func _updateCachedAssets() {
        // Update only if the view is visible.
        guard let collectionView = collectionView, _prepared else {
            return
        }
        
        // The preheat window is twice the height of the visible rect.
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let targetVisibleRect = CGRect(origin: _targetContentOffset, size: collectionView.bounds.size)
        
        let preheatRect = visibleRect.insetBy(dx: 0, dy: -0.5 * visibleRect.height)
        let targetPreheatRect = targetVisibleRect.insetBy(dx: 0, dy: -0.5 * targetVisibleRect.height)

        var changes = [(new: CGRect, old: CGRect)]()
        
        // Update only if the visible area is significantly different from the last preheated area.
        let delta = abs(preheatRect.midY - _previousPreheatRect.midY)
        if delta > view.bounds.height / 3 {
            // need change
            changes.append((preheatRect, _previousPreheatRect))
            // Store the preheat rect to compare against in the future.
            _previousPreheatRect = preheatRect
        }
        // Update only if the taget visible area is significantly different from the last preheated area.
        let targetDelta = abs(targetPreheatRect.midY - _previousTargetPreheatRect.midY)
        if targetDelta > view.bounds.height / 3 {
            // need change
            changes.append((targetPreheatRect, _previousTargetPreheatRect))
            // Store the preheat rect to compare against in the future.
            _previousTargetPreheatRect = targetPreheatRect
        }
        // is change?
        guard !changes.isEmpty else {
            return
        }
        //logger.debug?.write("preheatRect is change: \(changes)")
        
        // Compute the assets to start caching and to stop caching.
        let result = _different(changes.map { $0.new }, changes.map { $0.old })
        
        let addedAssets = result.added
            .flatMap { _indexPathsForElements(in: $0) }
            .flatMap { _source.asset(at: $0) }
        
        let removedAssets = result.removed
            .flatMap { _indexPathsForElements(in: $0) }
            .flatMap { _source.asset(at: $0) }
            .filter { asset in !addedAssets.contains(where: { $0 === asset } ) }
        
        // Update the assets the PHCachingImageManager is caching.
        _container.startCachingImages(for: addedAssets, size: BrowserAlbumLayout.thumbnailItemSize, mode: .aspectFill, options: nil)
        _container.stopCachingImages(for: removedAssets, size: BrowserAlbumLayout.thumbnailItemSize, mode: .aspectFill, options: nil)
    }
    
    fileprivate func _different(_ new: [CGRect], _ old: [CGRect]) -> (added: [CGRect], removed: [CGRect]) {
        // calculates the area after subtracting the two rect
        func _subtract(_ r1: CGRect, _ r2: CGRect) -> [CGRect] {
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
        // union all rectangles
        func _union(_ rects: [CGRect]) -> [CGRect] {
            
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
        // intersection all rectangles
        func _intersection(_ rects: [CGRect]) -> [CGRect] {
            
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
    
    fileprivate func _indexPathsForElements(in rect: CGRect) -> [IndexPath] {
        return collectionViewLayout.layoutAttributesForElements(in: rect)?.map {
            $0.indexPath
        } ?? []
    }
}

/// Add library error info display support
extension BrowserAlbumController {
    
    /// Show error info in view controller
    func showError(with title: String, subtitle: String) {
        logger.trace?.write(title, subtitle)
        
        // clear view
        _infoView?.removeFromSuperview()
        _infoView = nil
        
        let infoView = ErrorView(frame: view.bounds)
        
        infoView.title = title
        infoView.subtitle = subtitle
        infoView.backgroundColor = .white
        infoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // show view
        view.addSubview(infoView)
        _infoView = infoView
        
        // disable scroll
        collectionView?.isScrollEnabled = false
        collectionView?.reloadData()
    }
    
    /// Hiden all error info
    func clearError() {
        logger.trace?.write()
        
        // clear view
        _infoView?.removeFromSuperview()
        _infoView = nil
        
        // get current collectio nview
        guard let collectionView = collectionView else {
            return
        }
        
        // enable scroll
        collectionView.isScrollEnabled = true
        
        // need appear animation?
        guard collectionView.alpha <= 0 else {
            return
        }
        UIView.animate(withDuration: 0.25) {
            collectionView.alpha = 1
        }
    }
    
    /// Reload data with authorization info
    func reloadData(with auth: AuthorizationStatus) {
        
        // check for authorization status
        guard auth == .authorized else {
            // no permission
            showError(with: "No Access Permissions", subtitle: "") // 此应用程序没有权限访问您的照片\n在\"设置-隐私-图片\"中开启后即可查看
            return
        }
        _authorized = true
        
        // load source with container
        _source.load(with: _container)
        
        // update header view & footer view
        _headerView?.source = _source
        _footerView?.source = _source
        
        // check for assets count
        guard _source.count != 0 else {
            // count is zero, no data
            showError(with: "No Photos or Videos", subtitle: "You can sync photos and videos onto your iPhone using iTunes.")
            return
        }
        // clear all error info
        clearError()
        
        // reload all data
        reloadData()
    }
    /// Reload data data and scroll to init position
    func reloadData() {
        
        // reload data
        collectionView?.reloadData()
        
        guard let collectionView = collectionView else {
            return
        }
        
        // scroll after update footer
        _updateFooterView()
        _updateHeaderCaches()
        
        // scroll to init position if needed
        if _source.collectionSubtype == .smartAlbumUserLibrary {
            // if the contentOffset over boundary
            // reset vaild contentOffset in collectionView internal
            let size = collectionViewLayout.collectionViewContentSize
            let bottom = collectionView.contentInset.bottom - _footerContentInsets.bottom
            collectionView.contentOffset.y = size.height - (collectionView.frame.height - bottom)
        }
        
        // content is loaded
        _prepared = true
        _targetContentOffset = collectionView.contentOffset 
        
        // update content offset
        scrollViewDidScroll(collectionView)
    }
    
}

/// Add collection view display support
extension BrowserAlbumController: UICollectionViewDelegateFlowLayout {
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // if there is prepared, continue to wait
        guard _prepared else {
            return
        }
        
        // if isTracking is true, is a draging
        if scrollView.isTracking {
            // on draging, update target content offset
           _targetContentOffset = scrollView.contentOffset
        }
        
        // update all for content offset did change
        _updateHeaderView()
        _updateCachedAssets()
    }
    
    override func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        // update target content offset
        _targetContentOffset = .init(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        
        // if transitions animation is started, can't scroll
        return !_transitioning
    }
    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // update target content offset
        _targetContentOffset = scrollView.contentOffset
    }
    override func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // update target content offset
        _targetContentOffset = targetContentOffset.move()
    }
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        // without authorization, shows blank
        guard _authorized else {
            return 0
        }
        return _source.numberOfSections
    }
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // without authorization, shows blank
        guard _authorized else {
            return 0
        }
        return _source.numberOfItems(inSection: section)
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // generate the reuse identifier
        let type = _source.asset(at: indexPath)?.mediaType ?? .unknown
        
        // generate cell for media type
        return collectionView.dequeueReusableCell(withReuseIdentifier: ub_identifier(with: type), for: indexPath)
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        // generate the view for kind
        return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "HEADER", for: indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // collectionViewLayout must king of `UICollectionViewFlowLayout`
        guard let collectionViewLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return .zero
        }
        
        return collectionViewLayout.itemSize
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        // show header view?
        guard _headerView != nil else {
            return .zero
        }
        return .init(width: 0, height: 48)
    }
    
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // cell must king of `Displayable`
        guard let displayer = cell as? Displayable, let asset = _source.asset(at: indexPath), _prepared else {
            return
        }
        
        // show asset with container and orientation
        cell.layer.zPosition = -1
        displayer.willDisplay(with: asset, container: _container, orientation: .up)
    }
    
    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // cell must king of `Displayable`
        guard let displayer = cell as? Displayable, _prepared else {
            return
        }
        
        displayer.endDisplay(with: _container)
    }
    
    override func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView, forElementKind elementKind: String, at indexPath: IndexPath) {
        // view must king of `BrowserAlbumHeader`
        guard let view = view as? BrowserAlbumHeader else {
            return
        }
        
        // update data
        view.parent = _headerView
        view.section = indexPath.section
        view.layer.zPosition = -0.75
    }
    override func collectionView(_ collectionView: UICollectionView, didEndDisplayingSupplementaryView view: UICollectionReusableView, forElementOfKind elementKind: String, at indexPath: IndexPath) {
        // view must king of `BrowserAlbumHeader`
        guard let view = view as? BrowserAlbumHeader else {
            return
        }
        
        // clear data
        view.parent = nil
        view.section = nil
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        logger.trace?.write(indexPath)
        logger.debug?.write("show detail with: \(indexPath)")
        
        // create detail controller
        guard let controller = _container.viewController(wit: .detail, source: _source, sender: indexPath) else {
            return
        }
        
        // can't use animator
        if let controller = controller as? BrowserDetailController {
            
            controller.animator = Animator(source: self, destination: controller)
            controller.updateDelegate = self
        }
        
        // show next page
        show(controller, sender: indexPath)
    }
}

/// Add animatable transitioning support
extension BrowserAlbumController: TransitioningDataSource {
    
    func ub_transitionView(using animator: Animator, for operation: Animator.Operation) -> TransitioningView? {
        logger.trace?.write()
        
        guard let indexPath = animator.indexPath else {
            return nil
        }
        // get at current index path the cell
        return collectionView?.cellForItem(at: indexPath) as? TransitioningView
    }
    
    func ub_transitionShouldStart(using animator: Animator, for operation: Animator.Operation) -> Bool {
        logger.trace?.write()
        
        return true
    }
    func ub_transitionShouldStartInteractive(using animator: Animator, for operation: Animator.Operation) -> Bool {
        logger.trace?.write()
        return false
    }
    
    func ub_transitionDidPrepare(using animator: Animator, context: TransitioningContext) {
        logger.trace?.write()
        
        // must be attached to the collection view
        guard let collectionView = collectionView, let indexPath = animator.indexPath  else {
            return
        }
        // check the index path is displaying
        if !collectionView.indexPathsForVisibleItems.contains(indexPath) {
            // no, scroll to the cell at index path
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            // must call the layoutIfNeeded method, otherwise cell may not create
            collectionView.layoutIfNeeded()
        }
        // fetch cell at index path, if is displayed
        guard let cell = collectionView.cellForItem(at: indexPath) else {
            return
        }
        // if it is to, reset cell boundary
        if context.ub_operation == .pop || context.ub_operation == .dismiss {
            let frame = cell.convert(cell.bounds, to: view)
            let height = view.frame.height - topLayoutGuide.length - bottomLayoutGuide.length
            
            let y1 = -topLayoutGuide.length + frame.minY - (_headerView?.frame.height ?? 0)
            let y2 = -topLayoutGuide.length + frame.maxY
            
            // reset content offset if needed
            if y2 > height {
                // bottom over boundary, reset to y2(bottom)
                collectionView.contentOffset.y += y2 - height
            } else if y1 < 0 {
                // top over boundary, rest to y1(top)
                collectionView.contentOffset.y += y1
            }
        }
        cell.isHidden = true
        
        // current transitions animation is started
        _transitioning = true
    }
    func ub_transitionWillEnd(using animator: Animator, context: TransitioningContext, transitionCompleted: Bool) {
        logger.trace?.write(transitionCompleted)
        // if the disappear operation and indexPath is exists
        guard let indexPath = animator.indexPath, context.ub_operation.disappear else {
            return
        }
        // fetch cell at index path, if is displayed
        guard let cell = collectionView?.cellForItem(at: indexPath) else {
            return
        }
        guard let snapshotView = context.ub_snapshotView, let newSnapshotView = snapshotView.snapshotView(afterScreenUpdates: false) else {
            return
        }
        newSnapshotView.transform = snapshotView.transform
        newSnapshotView.bounds = .init(origin: .zero, size: snapshotView.bounds.size)
        newSnapshotView.center = .init(x: snapshotView.bounds.midX, y: snapshotView.bounds.midY)
        cell.addSubview(newSnapshotView)
        
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
            newSnapshotView.alpha = 0
        }, completion: { finished in
            newSnapshotView.removeFromSuperview()
        })
    }
    func ub_transitionDidEnd(using animator: Animator, transitionCompleted: Bool) {
        logger.trace?.write(transitionCompleted)
        // fetch cell at index path, if index path is nil ignore
        guard let indexPath = animator.indexPath, let cell = collectionView?.cellForItem(at: indexPath) else {
            return
        }
        cell.isHidden = false
        
        // current transitions animation is end
        _transitioning = false
    }
}

/// Add change update support
extension BrowserAlbumController: DetailControllerItemUpdateDelegate {
    
    // the item will show
    internal func detailController(_ detailController: Any, willShowItem indexPath: IndexPath) {
        // if is, this suggests that are displaying
        if collectionView?.indexPathsForVisibleItems.contains(indexPath) ?? false {
            return
        }
        logger.debug?.write("over screen, scroll to \(indexPath)")
        
        
        guard indexPath.section < _source.numberOfSections
            && indexPath.item < _source.numberOfItems(inSection: indexPath.section) else {
            return
        }
        
        // no displaying, scroll to item
        collectionView?.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        collectionView?.layoutIfNeeded()
    }
    
    // the item did show
    internal func detailController(_ detailController: Any, didShowItem indexPath: IndexPath) {
    }
    
}

/// Add change update support
extension BrowserAlbumController: ChangeObserver {
    
    /// Tells your observer that a set of changes has occurred in the Photos library.
    internal func library(_ library: Library, didChange change: Change) {
        // if the view controller no authorized, ignore all change
        guard _authorized else {
            return
        }
        
        // get data source change
        guard let details = _source.changeDetails(for: change) else {
            return // no change
        }
        logger.trace?.write()
        
        // change notifications may be made on a background queue.
        // re-dispatch to the main queue to update the UI.
        DispatchQueue.main.async {
            // progressing
            self.library(library, didChange: change, details: details)
        }
    }
    
    /// Tells your observer that a set of changes has occurred in the Photos library.
    internal func library(_ library: Library, didChange change: Change, details: SourceChangeDetails) {
        // get collection view and new data source
        guard let collectionView = collectionView, let source = details.after else {
            return
        }
        // keep the new fetch result for future use.
        _source = source
        
        // update header view & footer view
        _headerView?.source = source
        _footerView?.source = source
        
        // update collection asset count change
        guard source.count != 0 else {
            // count is zero, no data
            showError(with: "No Photos or Videos", subtitle: "You can sync photos and videos onto your iPhone using iTunes.")
            reloadData()
            return
        }
        
        // clear error info if needed
        clearError()
        
        // the content is prepared
        _prepared = true
        
        // the aset has any change?
        guard details.hasAssetChanges else {
            return
        }
        
        // update collection
        collectionView.performBatchUpdates({
            
            // For indexes to make sense, updates must be in this order:
            // delete, insert, reload, move
            details.deleteSections.map { collectionView.deleteSections($0) }
            details.insertSections.map { collectionView.insertSections($0) }
            details.reloadSections.map { collectionView.reloadSections($0) }
            
            details.removeItems.map { collectionView.deleteItems(at: $0) }
            details.insertItems.map { collectionView.insertItems(at: $0) }
            details.reloadItems.map { collectionView.reloadItems(at: $0) }
            
            // move
            details.enumerateMoves { from, to in
                collectionView.moveItem(at: from, to: to)
            }
            
        }, completion: nil)
        
        // source did change, must update header cache
        _updateHeaderCaches()
    }
    
}
