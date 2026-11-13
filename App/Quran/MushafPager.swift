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
        // Right to left, as a mushaf is read.
        controller.view.semanticContentAttribute = .forceRightToLeft
        controller.setViewControllers([context.coordinator.controller(for: page)], direction: .forward, animated: false)
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
        controller.setViewControllers([coordinator.controller(for: page)],
                                      direction: page > current ? .forward : .reverse, animated: curl)
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

        /// The page before in reading order: the one with the lower number.
        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let number = (viewController as? PageController)?.number, number > 1 else { return nil }
            return controller(for: number - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let number = (viewController as? PageController)?.number, number < Quran.pageCount else { return nil }
            return controller(for: number + 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let number = (pageViewController.viewControllers?.first as? PageController)?.number,
                  number != parent.page else { return }
            parent.page = number
        }
    }
}
