import SwiftUI
import UIKit

/// The mushaf's pages, turned like paper (a curl) as in a printed mushaf: the spine on the right, so the next page comes
/// from the left and a swipe to the right turns forward. With Reduce Motion the pages slide instead, still right to
/// left. Only the pages on screen and beside it are made.
struct MushafPager: UIViewControllerRepresentable {
    @Binding var page: Int
    /// A page curl; otherwise a slide.
    let curl: Bool
    /// Lets the reader share the page on screen as it is shown.
    var handle: PagerHandle?
    let makePage: (Int) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = curl
            ? UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                   options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.max.rawValue)])
            : UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        handle?.controller = controller
        // Right to left, as a mushaf is read. A slide takes that from a right-to-left layout. A curl ignores the layout
        // (in CI a right swipe asked for the page "before" with either one forced), so its data source swaps before and
        // after instead (Coordinator.neighbour); its layout stays fixed so that no language can change that.
        controller.view.semanticContentAttribute = curl ? .forceLeftToRight : .forceRightToLeft
        // A stored page out of range (an old or damaged value) opens the nearest real one.
        let first = min(max(page, 1), Quran.pageCount)
        controller.setViewControllers([context.coordinator.controller(for: first)], direction: .forward, animated: false)
        // A curl also turns on a tap at the page's edge, where a tap should open the verse instead.
        for gesture in controller.gestureRecognizers where gesture is UITapGestureRecognizer {
            gesture.isEnabled = false
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // The pages on screen take the new style, text size or marked verse.
        for case let shown as PageController in controller.viewControllers ?? [] {
            shown.rootView = makePage(shown.number)
        }
        guard let current = (controller.viewControllers?.first as? PageController)?.number, current != page,
              (1...Quran.pageCount).contains(page) else { return }
        // A curl turns to a later page the way a right swipe does, which UIKit calls "reverse".
        controller.setViewControllers([coordinator.controller(for: page)],
                                      direction: (page > current) != curl ? .forward : .reverse, animated: curl)
    }

    /// One page of the mushaf.
    final class PageController: UIHostingController<AnyView> {
        let number: Int

        init(number: Int, page: AnyView) {
            self.number = number
            super.init(rootView: page)
            view.backgroundColor = .clear
            // The pager sits between the toolbar and the page bar: no insets of its own.
            safeAreaRegions = []
        }

        @available(*, unavailable)
        @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: MushafPager

        init(_ parent: MushafPager) {
            self.parent = parent
        }

        func controller(for number: Int) -> PageController {
            PageController(number: number, page: parent.makePage(number))
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            neighbour(of: viewController, after: false)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            neighbour(of: viewController, after: true)
        }

        /// The next page (one higher) is UIKit's "after" in a slide but its "before" in a curl: with the spine on the
        /// right, UIKit asks for the page "before" when the reader swipes right.
        private func neighbour(of viewController: UIViewController, after: Bool) -> UIViewController? {
            guard let number = (viewController as? PageController)?.number else { return nil }
            let other = number + (after != parent.curl ? 1 : -1)
            return (1...Quran.pageCount).contains(other) ? controller(for: other) : nil
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let number = (pageViewController.viewControllers?.first as? PageController)?.number,
                  number != parent.page else { return }
            parent.page = number
        }
    }
}
