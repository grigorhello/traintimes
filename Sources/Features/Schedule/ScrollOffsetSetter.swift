import SwiftUI
import UIKit

/// One ask to move the timeline: each ask has a new `token`, so the setter acts once per ask however often the view updates.
struct ScrollOrder: Equatable {
    var token = 0
    var animated = false
}

/// Moves the vertical scroll view it sits in to an offset, straight on the `UIScrollView` (TT-159, D52). `ScrollViewProxy.scrollTo`
/// stayed at the top of a timeline as long as a real day's (opening at 5:24 AM at 5:47 PM, on CI and on a device), so Now is
/// placed by setting the offset itself, which can be checked: `report` says what was set and where the scroll view ended up.
/// Put it in the scroll view's content, as a background.
struct ScrollOffsetSetter: UIViewRepresentable {
    /// Points of content to scroll past, from the top of the timeline; 0 shows its start. Read when the move happens, so
    /// it is the layout of that moment.
    let offset: CGFloat
    let order: ScrollOrder
    var report: (@MainActor (String) -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.offset = offset
        coordinator.report = report
        guard order.token != coordinator.token else { return }
        coordinator.token = order.token
        guard order.token > 0 else { return }
        let animated = order.animated
        Task { @MainActor [weak view] in
            guard let view else { return }
            coordinator.move(from: view, animated: animated)
        }
    }

    @MainActor
    final class Coordinator {
        var offset: CGFloat = 0
        var token = 0
        var report: (@MainActor (String) -> Void)?
        private var moves = 0

        func move(from view: UIView, animated: Bool) {
            moves += 1
            guard let scrollView = view.enclosingScrollView else {
                report?("move \(moves): no scroll view above the setter")
                return
            }
            let inset = scrollView.adjustedContentInset
            let top = -inset.top
            let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
            let y = min(max(top, top + offset), bottom)
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: animated)
            report?("move \(moves) animated=\(animated): offset \(Int(offset)) top \(Int(top)) bottom \(Int(bottom)) -> y \(Int(y)); "
                + "content \(Int(scrollView.contentSize.height)) in \(Int(scrollView.bounds.height)); now at \(Int(scrollView.contentOffset.y))")
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView { return scrollView }
            current = view.superview
        }
        return nil
    }
}
