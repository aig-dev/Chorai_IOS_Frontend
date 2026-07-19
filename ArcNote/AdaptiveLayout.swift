import SwiftUI

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
