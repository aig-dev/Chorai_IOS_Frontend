import CoreFlow
import SwiftUI

struct CoreTabBar: View {
    @Binding var selectedTab: CoreTab
    let onRecord: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onRecord) {
                Label("Record", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    .background(recordBackground)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityIdentifier("record.open")

            HStack(spacing: 0) {
                tab(.flow, label: "Flow", image: "rectangle.stack", identifier: "flow")
                tab(.library, label: "Library", image: "books.vertical", identifier: "library")
                tab(.chat, label: "Chat", image: "bubble.left.and.bubble.right", identifier: "chat")
            }
            .frame(height: ZenVisualTokens.tabHeight)
            .background(tabBackground)
        }
        .padding(.horizontal, ZenVisualTokens.pageInset)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [Color.clear, ZenVisualTokens.background.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var recordBackground: some View {
        Capsule()
            .fill(ZenVisualTokens.accent.opacity(0.22))
            .overlay(
                Capsule()
                    .stroke(
                        Color.white.opacity(contrast == .increased ? 0.42 : 0.16),
                        lineWidth: 1
                    )
            )
    }

    private var tabBackground: some View {
        ZStack {
            if reduceTransparency {
                Capsule().fill(Color(red: 0.07, green: 0.055, blue: 0.12))
            } else {
                Capsule().fill(.ultraThinMaterial.opacity(0.55))
            }
            Capsule()
                .stroke(
                    Color.white.opacity(contrast == .increased ? 0.42 : 0.14),
                    lineWidth: 1
                )
        }
    }

    private func tab(
        _ tab: CoreTab,
        label: String,
        image: String,
        identifier: String
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: image)
                    .font(.system(size: 17, weight: selectedTab == tab ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
            }
            .foregroundStyle(.white.opacity(selectedTab == tab ? 1 : 0.55))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(identifier)")
    }
}

struct QuickCaptureSheet: View {
    @ObservedObject var store: QuickCaptureStore
    let actorID: String
    let onCreated: (CreatedCard) -> Void
    let onDismiss: () -> Void

    @FocusState private var isInputFocused: Bool
    @State private var isDiscardConfirmationPresented = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Private by default", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.58))

                ZStack(alignment: .topLeading) {
                    if store.text.isEmpty {
                        Text("What caught you?")
                            .font(.system(size: 20, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.38))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $store.text)
                        .font(.system(size: 20, design: .rounded))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .focused($isInputFocused)
                        .disabled(store.phase == .saving)
                        .accessibilityIdentifier("record.input")
                }
                .frame(minHeight: 180)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )

                if case .failed(let message) = store.phase {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Color(red: 1, green: 0.54, blue: 0.58))
                        .accessibilityIdentifier("record.error")
                }

                if !store.text.isEmpty {
                    Button(role: .destructive) {
                        isDiscardConfirmationPresented = true
                    } label: {
                        Label("Discard draft", systemImage: "trash")
                            .frame(minHeight: 44)
                    }
                    .disabled(store.phase == .saving)
                    .accessibilityIdentifier("record.discard")
                }

                Spacer(minLength: 0)
            }
            .padding(ZenVisualTokens.pageInset)
            .background(ZenVisualTokens.background.ignoresSafeArea())
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .disabled(store.phase == .saving)
                        .accessibilityIdentifier("record.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        store.save(onCreated: onCreated)
                    } label: {
                        if store.phase == .saving {
                            ProgressView()
                        } else if case .failed = store.phase {
                            Text("Retry")
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!store.canSave)
                    .accessibilityIdentifier("record.save")
                }
            }
        }
        .tint(ZenVisualTokens.accent)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("record.sheet")
        .interactiveDismissDisabled(store.phase == .saving)
        .onAppear {
            store.load(actorID: actorID)
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
        .alert("Discard this draft?", isPresented: $isDiscardConfirmationPresented) {
            Button("Keep", role: .cancel) {}
            Button("Discard", role: .destructive) {
                store.discard()
                onDismiss()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
}
