import SwiftUI
import UIKit

/// The approved warm paper / forest / college gold palette. Every semantic color
/// resolves from the current trait collection, including presented UIKit surfaces.
enum ChoraiTheme {
    static let background = color(light: 0xFAF9F6, dark: 0x242329)
    static let surface = color(light: 0xFFFFFC, dark: 0x2C2C31)
    static let raisedSurface = color(light: 0xF0F0EA, dark: 0x35363B)
    static let ink = color(light: 0x153B37, dark: 0xBFDBCF)
    static let secondaryInk = color(light: 0x586D64, dark: 0xA2B5AC)
    static let tertiaryInk = color(light: 0x69786F, dark: 0x94A49C)
    static let accent = ink
    static let gold = color(light: 0x846838, dark: 0xD6B378)
    static let separator = color(light: 0xD9DFD7, dark: 0x4C514F)
    static let onAccent = color(light: 0xFFFFFF, dark: 0x153B37)
    static let selection = color(light: 0xE4EDE5, dark: 0x35473F)
    // The existing white logo needs the same dark backing in both appearances.
    static let brandAvatarBackground = Color(uiColor: uiColor(0x153B37))

    static func color(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: adaptiveUIColor(light: light, dark: dark))
    }

    static func adaptiveUIColor(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in uiColor(traits.userInterfaceStyle == .dark ? dark : light) }
    }

    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

/// Used only when no profile photo is available; uploaded photos keep their colors.
struct ChoraiDefaultAvatar: View {
    var body: some View {
        Image("logo")
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .background(ChoraiTheme.brandAvatarBackground, in: Circle())
            .clipShape(Circle())
    }
}

struct ChoraiBackground: View {
    var body: some View {
        ChoraiTheme.background.ignoresSafeArea().allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Glass belongs to controls and secondary surfaces; readable content stays opaque.
private struct ChoraiGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency || contrast == .increased {
            content.background(ChoraiTheme.surface, in: shape)
                .overlay(shape.stroke(ChoraiTheme.separator, lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(ChoraiTheme.separator.opacity(0.55), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 16, y: 5)
        }
    }
}

extension View {
    @ViewBuilder
    func choraiGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    func choraiGlassSurface(cornerRadius: CGFloat = 24) -> some View {
        modifier(ChoraiGlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    func choraiPageBackground() -> some View {
        background(ChoraiTheme.background.ignoresSafeArea())
            .tint(ChoraiTheme.accent)
    }
}

extension Notification.Name {
    /// Posted only after the existing service confirms an explicit favorite change.
    static let choraiFavoriteChanged = Notification.Name("chorai.favorite.changed")
}

/// A single app-root attachment presents a native sheet from this scene's visible
/// controller, including when the originating screen is already inside a sheet.
struct ChoraiNativeSheetPresenter<SheetContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let detents: [UISheetPresentationController.Detent]
    let initialDetent: UISheetPresentationController.Detent.Identifier
    let content: (@escaping () -> Void) -> SheetContent

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, detents: detents, initialDetent: initialDetent, content: content)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.content = content
        context.coordinator.reconcile(from: controller)
    }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isPresented: Binding<Bool>
        var content: (@escaping () -> Void) -> SheetContent
        private let detents: [UISheetPresentationController.Detent]
        private let initialDetent: UISheetPresentationController.Detent.Identifier
        private weak var attachment: UIViewController?
        private var sheet: ChoraiSheetHostingController<SheetContent>?
        private var pendingPresentation: DispatchWorkItem?
        private var isDismissing = false

        init(
            isPresented: Binding<Bool>,
            detents: [UISheetPresentationController.Detent],
            initialDetent: UISheetPresentationController.Detent.Identifier,
            content: @escaping (@escaping () -> Void) -> SheetContent
        ) {
            self.isPresented = isPresented
            self.detents = detents
            self.initialDetent = initialDetent
            self.content = content
        }

        func reconcile(from attachment: UIViewController) {
            self.attachment = attachment
            pendingPresentation?.cancel()
            pendingPresentation = nil
            guard isPresented.wrappedValue else {
                dismissOwnSheet()
                return
            }
            guard sheet == nil, !isDismissing else { return }
            guard let root = attachment.view.window?.rootViewController else {
                retryWhenPresentationSettles()
                return
            }
            var presenter = root
            while let presented = presenter.presentedViewController {
                guard !presented.isBeingDismissed else {
                    retryWhenPresentationSettles()
                    return
                }
                presenter = presented
            }
            // Never attach a sheet to a temporary alert or transition.
            guard !(presenter is UIAlertController),
                  !presenter.isBeingPresented, !presenter.isBeingDismissed,
                  presenter.viewIfLoaded?.window != nil else {
                retryWhenPresentationSettles()
                return
            }

            let controller = ChoraiSheetHostingController(
                rootView: content { [weak self] in self?.expandForInput() }
            )
            controller.modalPresentationStyle = .pageSheet
            controller.view.backgroundColor = .clear
            if let nativeSheet = controller.sheetPresentationController {
                nativeSheet.detents = detents
                nativeSheet.selectedDetentIdentifier = initialDetent
                nativeSheet.prefersGrabberVisible = true
                nativeSheet.prefersScrollingExpandsWhenScrolledToEdge = true
            }
            controller.presentationController?.delegate = self
            controller.onRemoval = { [weak self, weak controller] in
                guard let self, let controller, self.sheet === controller else { return }
                self.finishDismissal()
            }
            sheet = controller
            presenter.present(controller, animated: true)
        }

        private func expandForInput() {
            guard let nativeSheet = sheet?.sheetPresentationController else { return }
            nativeSheet.animateChanges { nativeSheet.selectedDetentIdentifier = .large }
        }

        private func retryWhenPresentationSettles() {
            let work = DispatchWorkItem { [weak self] in
                guard let self, let attachment = self.attachment else { return }
                self.reconcile(from: attachment)
            }
            pendingPresentation = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        private func dismissOwnSheet() {
            guard let sheet, !isDismissing else { return }
            isDismissing = true
            // Dismiss only the controller we own; its originating sheet stays open.
            sheet.dismiss(animated: true) { [weak self, weak sheet] in
                guard let self, let sheet, self.sheet === sheet else { return }
                self.finishDismissal()
            }
        }

        private func finishDismissal() {
            sheet?.onRemoval = nil
            sheet = nil
            isDismissing = false
            if isPresented.wrappedValue { isPresented.wrappedValue = false }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finishDismissal()
        }

        func tearDown() {
            pendingPresentation?.cancel()
            pendingPresentation = nil
            sheet?.onRemoval = nil
            sheet?.dismiss(animated: false)
            sheet = nil
            if isPresented.wrappedValue { isPresented.wrappedValue = false }
        }
    }
}

private final class ChoraiSheetHostingController<Content: View>: UIHostingController<Content> {
    var onRemoval: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // A parent sheet can also be dismissed by navigation. Do not leave its
        // content marked as open after the presenting controller has gone away.
        if presentingViewController == nil { onRemoval?() }
    }
}
