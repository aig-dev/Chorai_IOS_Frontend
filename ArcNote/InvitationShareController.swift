import SwiftUI
import UIKit

struct InvitationSharePayload: Identifiable, Equatable {
    let id = UUID()
    let value: String
}

struct InvitationShareController: UIViewControllerRepresentable {
    let value: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [value],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
