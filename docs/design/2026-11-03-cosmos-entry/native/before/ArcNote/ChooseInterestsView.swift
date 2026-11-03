import SwiftUI
import CoreFlow

/// The store remains the only selection owner. Layout never changes a choice.
struct ChooseInterestsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showTabBar = false
    @StateObject private var store: InterestSelectionStore
    @StateObject private var authManager = AuthManager.shared

    init(service: any CoreInterestSelectionServing = NetworkCoreInterestSelectionService()) {
        _store = StateObject(wrappedValue: InterestSelectionStore(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text("Your starting points")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ChoraiTheme.gold)
                    Spacer()
                    Button("Skip", action: store.skip)
                        .font(.body.weight(.medium))
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(store.isSaving)
                        .accessibilityIdentifier("interests.skip")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose Your Interests")
                        .font(.system(.largeTitle, design: .serif).weight(.medium))
                        .foregroundStyle(ChoraiTheme.ink)
                    Text("Find ideas and people you’ll want to return to. Choose up to \(InterestSelectionStore.maximumSelectionCount).")
                        .font(.body)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if store.phase == .idle || store.phase == .loading {
                    ProgressView("Loading interests…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let error = loadErrorMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Couldn’t load interests", systemImage: "wifi.exclamationmark")
                            .font(.headline)
                        Text(error).foregroundStyle(ChoraiTheme.secondaryInk)
                        Button("Retry", action: loadInterests)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("interests.retry")
                    }
                    .accessibilityIdentifier("interests.load-error")
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(Array(store.options.enumerated()), id: \.element.value) { index, option in
                            Button {
                                store.toggle(option.value)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(option.value)
                                        .font(.body.weight(.medium))
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 4)
                                    Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(option.isSelected ? ChoraiTheme.accent : ChoraiTheme.tertiaryInk)
                                }
                                .foregroundStyle(ChoraiTheme.ink)
                                .padding(16)
                                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                                .background(option.isSelected ? ChoraiTheme.accent.opacity(0.10) : ChoraiTheme.surface,
                                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(option.isSelected ? ChoraiTheme.accent : ChoraiTheme.separator, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isSaving)
                            .accessibilityIdentifier("interests.option.\(index)")
                            .accessibilityValue(option.isSelected ? "selected" : "not selected")
                            .accessibilityAddTraits(option.isSelected ? .isSelected : [])
                        }
                    }
                }
                if let error = saveErrorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("interests.save-error")
                }
            }
            .adaptiveContentGutter()
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 18) {
                Button("Reset", action: store.reset)
                    .frame(minHeight: 44)
                    .disabled(store.isSaving || store.selectedDomains.isEmpty)
                Spacer()
                Text("\(store.selectedDomains.count) / \(InterestSelectionStore.maximumSelectionCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                Button(action: store.save) {
                    HStack(spacing: 8) {
                        if store.isSaving { ProgressView().tint(ChoraiTheme.onAccent) }
                        Text("Next").fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(ChoraiTheme.accent)
                .disabled(!store.canSave)
                .accessibilityIdentifier("interests.next")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .choraiGlassSurface(cornerRadius: 24)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .choraiPageBackground()
        .tint(ChoraiTheme.accent)
        .accessibilityIdentifier("screen.interests")
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showTabBar) { TabBarView() }
        .onAppear(perform: loadInterests)
        .onChange(of: store.phase) { phase in
            if phase == .saved || phase == .skipped { showTabBar = true }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private func loadInterests() {
        store.load(actorID: authManager.currentUser?.id ?? "")
    }

    private var loadErrorMessage: String? {
        guard case .failed(.load, let error) = store.phase else { return nil }
        return message(for: error)
    }

    private var saveErrorMessage: String? {
        guard case .failed(.save, let error) = store.phase else { return nil }
        return "Couldn’t save interests. \(message(for: error))"
    }

    private func message(for error: InterestSelectionError) -> String {
        switch error {
        case .invalidActor: return "Your session is missing. Please sign in again."
        case .transport: return "Check your connection and try again."
        }
    }
}
