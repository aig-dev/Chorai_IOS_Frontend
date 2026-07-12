import CoreFlow
import SwiftUI

@MainActor
struct ChoraProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var profileStore: ChoraProfileStore
    @StateObject private var noteImportStore: NoteImportStore
    @StateObject private var notionStore: NotionSourceStore
    @State private var hasAppeared = false

    private let humanActorID: String
    private let chatVisibility: ChatHistoryVisibility
    private let now: @Sendable () -> Date

    init(
        humanActorID: String,
        profileService: any CoreChoraProfileServing,
        noteImportService: any CoreNoteImportServing,
        notionService: any CoreNotionSourceServing,
        noteImportPersistence: any NoteImportRequestIDPersisting =
            UserDefaultsNoteImportRequestIDStore(),
        noteImportSleeper: any NoteImportSleeping = SystemNoteImportSleeper(),
        notionSleeper: any NotionSourceSleeping = SystemNotionSourceSleeper(),
        chatVisibility: ChatHistoryVisibility = ChatHistoryVisibility(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.humanActorID = humanActorID
        self.chatVisibility = chatVisibility
        self.now = now
        _profileStore = StateObject(
            wrappedValue: ChoraProfileStore(service: profileService)
        )
        _noteImportStore = StateObject(
            wrappedValue: NoteImportStore(
                service: noteImportService,
                persistence: noteImportPersistence,
                sleeper: noteImportSleeper
            )
        )
        _notionStore = StateObject(
            wrappedValue: NotionSourceStore(
                service: notionService,
                sleeper: notionSleeper
            )
        )
    }

    static func production(humanActorID: String) -> ChoraProfileView {
        ChoraProfileView(
            humanActorID: humanActorID,
            profileService: NetworkChoraProfileService(),
            noteImportService: NetworkNoteImportService(),
            notionService: NetworkNotionSourceService()
        )
    }

    var body: some View {
        ZStack {
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 24) {
                        orderMarker("1", identifier: "chora.order.identity")
                        ChoraIdentitySection(
                            store: profileStore,
                            humanActorID: humanActorID
                        )

                        orderMarker("2", identifier: "chora.order.growth")
                        ChoraGrowthSection(
                            store: profileStore,
                            humanActorID: humanActorID
                        )

                        orderMarker("3", identifier: "chora.order.sources")
                        ChoraSoulSourcesSection(
                            noteImportStore: noteImportStore,
                            notionStore: notionStore
                        )

                        orderMarker("4", identifier: "chora.order.chat")
                        ChoraChatHistorySection(
                            humanActorID: humanActorID,
                            visibility: chatVisibility,
                            now: now
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 8)
                }
            }
        }
        .navigationBarHidden(true)
        .accessibilityIdentifier("screen.choraProfile")
        .onAppear {
            withAnimation(.easeOut(duration: 0.24)) {
                hasAppeared = true
            }
        }
        .task(id: humanActorID) {
            await load()
        }
        .onDisappear {
            noteImportStore.stop()
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Back")

            Spacer()

            Text("Chora Profile")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.85)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.top, 44)
        .padding(.bottom, 20)
    }

    private func orderMarker(
        _ value: String,
        identifier: String
    ) -> some View {
        Text(value)
            .font(.system(size: 1))
            .foregroundColor(.white.opacity(0.01))
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }

    private func load() async {
        await profileStore.load(humanActorID: humanActorID)
        guard !Task.isCancelled, profileStore.identity != nil else { return }
        async let imports: Void = noteImportStore.load(actorID: humanActorID)
        notionStore.load(actorID: humanActorID)
        await imports
    }
}
