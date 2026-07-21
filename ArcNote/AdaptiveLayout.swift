import Combine
import SwiftUI
import UIKit

@MainActor
final class KeyboardLayoutObserver: ObservableObject {
    @Published private(set) var endFrame: CGRect = .null
    @Published private(set) var isVisible = false

    private var cancellables = Set<AnyCancellable>()

    init(notificationCenter: NotificationCenter = .default) {
        notificationCenter.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            self?.handleKeyboardFrameChange(notification)
        }
        .store(in: &cancellables)

        notificationCenter.publisher(
            for: UIResponder.keyboardWillHideNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.endFrame = .null
            self?.isVisible = false
        }
        .store(in: &cancellables)
    }

    func overlap(in containerFrame: CGRect) -> CGFloat {
        guard isVisible, !endFrame.isNull else { return 0 }
        return max(0, containerFrame.intersection(endFrame).height)
    }

    private func handleKeyboardFrameChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[
            UIResponder.keyboardFrameEndUserInfoKey
        ] as? CGRect else {
            endFrame = .null
            isVisible = false
            return
        }

        endFrame = frame
        guard let windowFrame = Self.keyWindowFrame else {
            isVisible = frame.height > 1
            return
        }
        isVisible = windowFrame.intersection(frame).height > 1
    }

    private static var keyWindowFrame: CGRect? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            .map { $0.convert($0.bounds, to: nil) }
    }
}

struct KeyboardStableViewport<Content: View>: View {
    @StateObject private var keyboardLayout = KeyboardLayoutObserver()
    @State private var restingMinY: CGFloat?
    @State private var currentMinY: CGFloat?

    private let isFocused: Bool
    private let content: (GeometryProxy) -> Content

    init(
        isFocused: Bool,
        @ViewBuilder content: @escaping (GeometryProxy) -> Content
    ) {
        self.isFocused = isFocused
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                content(geometry)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .top
                    )
                    .offset(y: verticalCorrection)

                KeyboardViewportTopReader { minY in
                    currentMinY = minY
                    if restingMinY == nil {
                        restingMinY = max(0, minY)
                    }
                }
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private var verticalCorrection: CGFloat {
        guard let restingMinY, let currentMinY else { return 0 }
        let displacement = restingMinY - currentMinY
        guard isFocused
                || keyboardLayout.isVisible
                || abs(displacement) > 0.5 else {
            return 0
        }
        return displacement
    }
}

private struct KeyboardViewportTopReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ReportingView, context: Context) {
        uiView.onChange = onChange
        uiView.reportAfterLayout()
    }

    final class ReportingView: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var lastMinY: CGFloat?
        private var keyboardObservers = [NSObjectProtocol]()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            observeKeyboardChanges()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            keyboardObservers.forEach(NotificationCenter.default.removeObserver)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportAfterLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportScreenMinY()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            reportAfterLayout()
        }

        func reportAfterLayout() {
            DispatchQueue.main.async { [weak self] in
                self?.reportScreenMinY()
            }
        }

        private func observeKeyboardChanges() {
            let center = NotificationCenter.default
            let names = [
                UIResponder.keyboardWillChangeFrameNotification,
                UIResponder.keyboardWillHideNotification,
            ]
            keyboardObservers = names.map { name in
                center.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.reportAfterLayout()
                    let duration = notification.userInfo?[
                        UIResponder.keyboardAnimationDurationUserInfoKey
                    ] as? Double ?? 0.25
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + duration
                    ) { [weak self] in
                        self?.reportScreenMinY()
                    }
                }
            }
        }

        private func reportScreenMinY() {
            guard window != nil else { return }
            let minY = convert(bounds, to: nil).minY
            guard minY.isFinite,
                  lastMinY.map({ abs($0 - minY) > 0.25 }) ?? true else {
                return
            }
            lastMinY = minY
            let callback = onChange
            DispatchQueue.main.async {
                callback?(minY)
            }
        }
    }
}

struct AdaptiveLayoutMetrics {
    static let compactMaximumWidth: CGFloat = 375
    static let standardMaximumWidth: CGFloat = 402
    static let compactGutter: CGFloat = 16
    static let standardGutter: CGFloat = 20
    static let wideGutter: CGFloat = 24
    static let compactSpacing: CGFloat = 12
    static let regularSpacing: CGFloat = 16
    static let surfaceCornerRadius: CGFloat = 24
    static let minimumHitTarget: CGFloat = 44

    let size: CGSize
    let safeAreaInsets: EdgeInsets

    init(size: CGSize, safeAreaInsets: EdgeInsets) {
        self.size = size
        self.safeAreaInsets = safeAreaInsets
    }

    var horizontalGutter: CGFloat {
        switch size.width {
        case ...Self.compactMaximumWidth:
            Self.compactGutter
        case ...Self.standardMaximumWidth:
            Self.standardGutter
        default:
            Self.wideGutter
        }
    }

    var contentWidth: CGFloat {
        max(0, size.width - (horizontalGutter * 2))
    }

    var drawerWidth: CGFloat {
        guard size.width > 0 else { return 0 }
        return min(
            max(size.width * 0.78, 280),
            min(360, max(0, size.width - horizontalGutter))
        )
    }
}

private struct AdaptiveLayoutMetricsKey: EnvironmentKey {
    static let defaultValue = AdaptiveLayoutMetrics(
        size: .zero,
        safeAreaInsets: EdgeInsets()
    )
}

extension EnvironmentValues {
    var adaptiveLayoutMetrics: AdaptiveLayoutMetrics {
        get { self[AdaptiveLayoutMetricsKey.self] }
        set { self[AdaptiveLayoutMetricsKey.self] = newValue }
    }
}

struct AdaptiveLayoutReader<Content: View>: View {
    private let content: (AdaptiveLayoutMetrics) -> Content

    init(@ViewBuilder content: @escaping (AdaptiveLayoutMetrics) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = AdaptiveLayoutMetrics(
                size: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets
            )

            content(metrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.adaptiveLayoutMetrics, metrics)
        }
    }
}

struct AdaptiveScreen<Background: View, Content: View>: View {
    private let background: Background
    private let content: (AdaptiveLayoutMetrics) -> Content

    init(
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: @escaping (AdaptiveLayoutMetrics) -> Content
    ) {
        self.background = background()
        self.content = content
    }

    var body: some View {
        AdaptiveLayoutReader { metrics in
            ZStack {
                background.ignoresSafeArea()
                content(metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct AdaptiveSurface<Content: View>: View {
    private let contentInsets: CGFloat
    private let content: Content

    init(
        contentInsets: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.contentInsets = contentInsets
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentInsets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: AdaptiveLayoutMetrics.surfaceCornerRadius,
                    style: .continuous
                )
                .fill(.ultraThinMaterial.opacity(0.72))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: AdaptiveLayoutMetrics.surfaceCornerRadius,
                        style: .continuous
                    )
                    .stroke(.white.opacity(0.16), lineWidth: 1)
                }
            }
    }
}

private struct AdaptiveContentGutter: ViewModifier {
    @Environment(\.adaptiveLayoutMetrics) private var metrics

    func body(content: Content) -> some View {
        content.padding(.horizontal, metrics.horizontalGutter)
    }
}

extension View {
    func adaptiveContentGutter() -> some View {
        modifier(AdaptiveContentGutter())
    }
}

#if DEBUG
struct AdaptiveLayoutFixtureScreen: View {
    @Environment(\.adaptiveLayoutMetrics) private var metrics

    var body: some View {
        AdaptiveScreen {
            Color(red: 0.05, green: 0.04, blue: 0.09)
        } content: { _ in
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: AdaptiveLayoutMetrics.regularSpacing
                ) {
                    Text("Adaptive layout")
                        .font(.title.bold())

                    AdaptiveSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Shared inset surface")
                            Text(
                                "\(Int(metrics.horizontalGutter)) pt horizontal gutter"
                            )
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.64))
                        }
                    }
                    .foregroundStyle(.white)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("adaptive-layout.surface")
                }
                .foregroundStyle(.white)
                .adaptiveContentGutter()
                .padding(.vertical, max(metrics.safeAreaInsets.top, 24))
            }
        }
        .accessibilityIdentifier("adaptive-layout.root")
    }
}
#endif
