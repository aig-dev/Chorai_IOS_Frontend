import CoreFlow
import SwiftUI

struct ChoraChatHistorySection: View {
    let humanActorID: String
    let visibility: ChatHistoryVisibilityDependency
    let now: @Sendable () -> Date
    @State private var showsConfirmation = false
    @State private var didClear = false

    var body: some View {
        ChoraSectionSurface(title: "Chat History", identifier: "chora.chat.section") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Previous messages are hidden on this device.")
                    .font(.subheadline).foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) { showsConfirmation = true } label: {
                    HStack(spacing: 12) {
                        Image("trash").resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
                        Text(didClear ? "Chat History Hidden" : "Clear Chat History").font(.body.weight(.medium))
                        Spacer()
                    }
                    .foregroundColor(Color(red: 1, green: 0.46, blue: 0.5)).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Chat History")
                .accessibilityValue("Hides previous messages on this device")
                .accessibilityIdentifier("chora.chat.clear")
            }
        }
        .alert("Clear Chat History?", isPresented: $showsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Hide Previous Messages", role: .destructive) {
                visibility.clear(actorID: humanActorID, at: now())
                didClear = true
            }
        } message: {
            Text("Previous messages will be hidden on this device. They are not deleted from Chorai.")
        }
    }
}
