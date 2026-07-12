import CoreFlow
import SwiftUI

@MainActor
struct ChoraProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var profileStore: ChoraProfileStore
    @StateObject private var noteImportStore: NoteImportStore
    @StateObject private var notionStore: NotionSourceStore
    @StateObject private var notionOAuthHolder: NotionOAuthCoordinatorHolder
    @EnvironmentObject private var chatHistoryDependency:
        ChatHistoryVisibilityDependency
    @State private var hasAppeared = false

    private let humanActorID: String
    private let now: @Sendable () -> Date
    private let initialNoteImportFiles: [NoteImportFile]
    private let automaticallyStartNoteImport: Bool
    private let automaticallyCancelNoteImport: Bool

    init(
        humanActorID: String,
        profileService: any CoreChoraProfileServing,
        noteImportService: any CoreNoteImportServing,
        notionService: any CoreNotionSourceServing,
        noteImportPersistence: any NoteImportRequestIDPersisting =
            UserDefaultsNoteImportRequestIDStore(),
        noteImportSleeper: any NoteImportSleeping = SystemNoteImportSleeper(),
        notionSleeper: any NotionSourceSleeping = SystemNotionSourceSleeper(),
        notionOAuthCoordinator: any NotionOAuthCoordinating,
        now: @escaping @Sendable () -> Date = { Date() },
        initialNoteImportFiles: [NoteImportFile] = [],
        automaticallyStartNoteImport: Bool = false,
        automaticallyCancelNoteImport: Bool = false
    ) {
        self.humanActorID = humanActorID
        self.now = now
        self.initialNoteImportFiles = initialNoteImportFiles
        self.automaticallyStartNoteImport = automaticallyStartNoteImport
        self.automaticallyCancelNoteImport = automaticallyCancelNoteImport
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
        _notionOAuthHolder = StateObject(
            wrappedValue: NotionOAuthCoordinatorHolder(
                notionOAuthCoordinator
            )
        )
    }

    static func production(humanActorID: String) -> ChoraProfileView {
        ChoraProfileView(
            humanActorID: humanActorID,
            profileService: NetworkChoraProfileService(),
            noteImportService: NetworkNoteImportService(),
            notionService: NetworkNotionSourceService(),
            notionOAuthCoordinator: NotionOAuthCoordinator()
        )
    }

    var body: some View {
        ZStack {
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsDestinationHeader(title: "Chora Profile") { dismiss() }

                ScrollView {
                    VStack(spacing: 24) {
                        ChoraIdentitySection(
                            store: profileStore,
                            humanActorID: humanActorID
                        )

                        ChoraGrowthSection(
                            store: profileStore,
                            humanActorID: humanActorID
                        )

                        ChoraSoulSourcesSection(
                            noteImportStore: noteImportStore,
                            notionStore: notionStore,
                            notionOAuthCoordinator:
                                notionOAuthHolder.coordinator
                        )

                        ChoraChatHistorySection(
                            humanActorID: humanActorID,
                            visibility: chatHistoryDependency,
                            now: now
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 8)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Chora Profile sections")
                    .accessibilityValue(
                        "Identity, Growth, Soul Sources, Chat History"
                    )
                    .accessibilityIdentifier(
                        "chora.profile.section-order"
                    )
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
            notionOAuthHolder.coordinator.cancel()
        }
    }

    private func load() async {
        await profileStore.load(humanActorID: humanActorID)
        guard !Task.isCancelled, profileStore.identity != nil else { return }
        async let imports: Void = noteImportStore.load(actorID: humanActorID)
        notionStore.load(actorID: humanActorID)
        await imports
        if !initialNoteImportFiles.isEmpty {
            noteImportStore.select(initialNoteImportFiles)
            if automaticallyStartNoteImport { noteImportStore.start() }
            if automaticallyCancelNoteImport {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    noteImportStore.cancel()
                }
            }
        }
    }
}
