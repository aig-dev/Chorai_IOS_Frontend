import CoreFlow
import SwiftUI

struct NotificationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: NotificationInboxStore
    @State private var showFilterTags = false
    @State private var selectedFilter: NotificationFilter = .all
    @State private var selectedActorID: String?
    @State private var selectedAssetID: String?
    @State private var selectedLegacyID: String?
    @State private var pendingNotificationID: String?
    @State private var hasLoaded = false

    private let actorID: String?
    private let usesFixtureDestinations: Bool

    init(
        service: any CoreNotificationServing = NetworkNotificationService(),
        actorID: String? = nil,
        usesFixtureDestinations: Bool = false
    ) {
        _store = StateObject(
            wrappedValue: NotificationInboxStore(service: service)
        )
        self.actorID = actorID
        self.usesFixtureDestinations = usesFixtureDestinations
    }

    var body: some View {
        ZStack {
            ChoraiBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if showFilterTags { filterStrip }
                content
            }

            if store.actionFailure != nil {
                actionError
            }
        }
        .accessibilityIdentifier("screen.notification-inbox")
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        showFilterTags.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Notification filters")
                .accessibilityValue(showFilterTags ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("notification.filter-toggle")
            }
        }
        .navigationDestination(isPresented: actorDestinationPresented) {
            let actorID = selectedActorID ?? ""
            if usesFixtureDestinations {
                fixtureDestination(
                    title: "Profile",
                    value: actorID,
                    identifier: "notification.fixture.actor-destination"
                )
            } else {
                UserProfileView(actorId: actorID)
            }
        }
        .navigationDestination(isPresented: assetDestinationPresented) {
            let assetID = selectedAssetID ?? ""
            if usesFixtureDestinations {
                fixtureDestination(
                    title: "Card",
                    value: assetID,
                    identifier: "notification.fixture.asset-destination"
                )
            } else {
                DetailView(cardId: assetID)
            }
        }
        .navigationDestination(isPresented: legacyDestinationPresented) {
            let notificationID = selectedLegacyID ?? ""
            if let notification = store.items.first(where: {
                $0.id == notificationID
            }) {
                NotificationDetailView(notification: notification)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            store.load(
                actorID: actorID ?? AuthManager.shared.currentUser?.id ?? ""
            )
        }
        .onChange(of: store.mutatingIDs) { mutatingIDs in
            guard let pendingNotificationID,
                  !mutatingIDs.contains(pendingNotificationID) else {
                return
            }
            Task { @MainActor in
                await Task.yield()
                completePendingNavigation()
            }
        }
    }

    private var actorDestinationPresented: Binding<Bool> {
        Binding(
            get: { selectedActorID != nil },
            set: { if !$0 { selectedActorID = nil } }
        )
    }

    private var assetDestinationPresented: Binding<Bool> {
        Binding(
            get: { selectedAssetID != nil },
            set: { if !$0 { selectedAssetID = nil } }
        )
    }

    private var legacyDestinationPresented: Binding<Bool> {
        Binding(
            get: { selectedLegacyID != nil },
            set: { if !$0 { selectedLegacyID = nil } }
        )
    }

    private var filterStrip: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Picker("Notifications", selection: $selectedFilter) {
                Text("All").tag(NotificationFilter.all)
                    .accessibilityIdentifier("notification.filter.all")
                Text("Unread").tag(NotificationFilter.unread)
                    .accessibilityIdentifier("notification.filter.unread")
                Text("Activity").tag(NotificationFilter.activity)
                    .accessibilityIdentifier("notification.filter.activity")
                Text("System").tag(NotificationFilter.system)
                    .accessibilityIdentifier("notification.filter.system")
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)

            Button { store.markAllLoadedRead() } label: {
                Text(store.isMarkingAll ? "Reading…" : "Read All")
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 72, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(store.unreadCount == 0 || store.isMarkingAll)
            .opacity(store.unreadCount == 0 ? 0.45 : 1)
            .accessibilityIdentifier("notification.read-all")
        }
        .adaptiveContentGutter()
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            loadingView
        case .failed(let operation, let error):
            if operation == .load {
                loadErrorView(error)
            } else {
                notificationList
            }
        case .empty:
            emptyView
        case .ready, .loadingMore:
            if store.filteredItems(selectedFilter).isEmpty {
                emptyView
            } else {
                notificationList
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView().tint(ChoraiTheme.ink).scaleEffect(1.2)
            Text("Loading…").foregroundColor(ChoraiTheme.ink)
            Spacer()
        }
    }

    private func loadErrorView(_ error: NotificationInboxError) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(ChoraiTheme.secondaryInk)
            Text("Loading Failed")
                .font(.headline.weight(.medium))
                .foregroundColor(ChoraiTheme.ink)
            Text(errorMessage(error))
                .font(.subheadline)
                .foregroundColor(ChoraiTheme.secondaryInk)
            Button("Retry") { store.retryLastFailure() }
                .foregroundColor(ChoraiTheme.ink)
                .frame(minWidth: 88, minHeight: 44)
                .padding(.top, 10)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.largeTitle.weight(.light))
                .foregroundColor(ChoraiTheme.secondaryInk)
            Text("No notifications")
                .font(.body.weight(.medium))
                .foregroundColor(ChoraiTheme.secondaryInk)
                .accessibilityIdentifier("notification.list.empty")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var notificationList: some View {
        List {
            ForEach(groupedNotifications, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { notification in
                        Button { open(notification) } label: {
                            NotificationItemView(notification: notification)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notification.row.\(notification.id)")
                        .accessibilityValue(notification.isRead ? "Read" : "Unread")
                        .listRowBackground(ChoraiTheme.surface)
                        .onAppear {
                            if notification.id == store.filteredItems(selectedFilter).last?.id {
                                store.loadMore()
                            }
                        }
                    }
                }
            }
            if store.phase == .loadingMore {
                ProgressView()
                    .tint(ChoraiTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .listRowBackground(ChoraiTheme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
            Text("Loaded")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("notification.list.loaded")
        }
    }

    private var groupedNotifications: [(title: String, items: [CommunityNotification])] {
        let order = ["Today", "Yesterday", "This Week", "Earlier"]
        let grouped = Dictionary(grouping: store.filteredItems(selectedFilter)) {
            sectionTitle(for: $0.createdAt)
        }
        return order.compactMap { title in
            guard let items = grouped[title], !items.isEmpty else { return nil }
            return (title, items.sorted { $0.createdAt > $1.createdAt })
        }
    }

    private var actionError: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                Text("Couldn’t update notification. Try again.")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(ChoraiTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 34)
            .accessibilityIdentifier("notification.action-error")
        }
    }

    private func open(_ notification: CommunityNotification) {
        guard !store.mutatingIDs.contains(notification.id) else { return }
        if !notification.isRead {
            pendingNotificationID = notification.id
            store.markRead(notificationID: notification.id)
            return
        }
        route(notification)
    }

    private func completePendingNavigation() {
        guard let pendingNotificationID else { return }
        defer { self.pendingNotificationID = nil }
        guard store.actionFailure == nil,
              let notification = store.items.first(where: {
                  $0.id == pendingNotificationID
              }), notification.isRead else {
            return
        }
        route(notification)
    }

    private func route(_ notification: CommunityNotification) {
        store.markRead(notificationID: notification.id)
        switch notification.target {
        case .actor(let actorID):
            selectedActorID = actorID
        case .asset(let assetID):
            selectedAssetID = assetID
        case .legacy:
            selectedLegacyID = notification.id
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        }
        return "Earlier"
    }

    private func errorMessage(_ error: NotificationInboxError) -> String {
        switch error {
        case .invalidActor: return "Sign in to view notifications."
        case .unauthorized: return "Your session has expired."
        case .forbidden: return "Notifications are unavailable."
        case .notFound: return "Notifications could not be found."
        case .contract, .transport: return "Check your connection and retry."
        }
    }

    private func fixtureDestination(
        title: String,
        value: String,
        identifier: String
    ) -> some View {
        ZStack {
            ChoraiBackground().ignoresSafeArea()
            VStack(spacing: 12) {
                Text(title).font(.title2).foregroundColor(ChoraiTheme.ink)
                Text(value)
                    .foregroundColor(ChoraiTheme.ink)
                    .accessibilityIdentifier(identifier)
            }
        }
    }
}

struct NotificationItemView: View {
    let notification: CommunityNotification

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if !notification.isRead {
                    Circle()
                        .fill(ChoraiTheme.gold)
                        .accessibilityIdentifier("notification.unread-dot.\(notification.id)")
                } else {
                    Color.clear
                }
            }
            .frame(width: 6, height: 6)
            .padding(.top, 6)

            sourceImage

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.displayText)
                    .font(.body.weight(.regular))
                    .foregroundColor(ChoraiTheme.ink)
                    .lineLimit(3)
                Text(relativeTime(notification.createdAt))
                    .font(.subheadline)
                    .foregroundColor(ChoraiTheme.secondaryInk)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var sourceImage: some View {
        if notification.kind.category == .system {
            ZStack {
                Circle().fill(Color.gray.opacity(0.3))
                Image(systemName: "bell")
                    .font(.headline.weight(.medium))
                    .foregroundColor(ChoraiTheme.ink)
            }
            .frame(width: 40, height: 40)
        } else if let avatarURL = notification.sourceActor?.avatarURL,
                  let url = URL(string: APIConfiguration.resourceURLString(avatarURL)) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image("avatar").resizable().aspectRatio(contentMode: .fill)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            Image("avatar")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack { NotificationView() }
}
