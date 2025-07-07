import SwiftUI

final class MainViewController: NSHostingController<AnyView> {
    init(rootViewProvider:() -> some View) {
        super.init(rootView: .init(rootViewProvider()))
        sizingOptions = .preferredContentSize
    }

    @available(*, unavailable)
    @MainActor @preconcurrency dynamic required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
