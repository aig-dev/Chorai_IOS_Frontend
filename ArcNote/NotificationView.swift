import CoreFlow
import SwiftUI

struct NotificationView: View {
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
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if showFilterTags { filterStrip }
                content
            }

            if store.actionFailure != nil {
                actionError
            }
        }
        .accessibilityIdentifier("screen.notification-inbox")
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
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

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showFilterTags.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Notification")
                        .font(.system(size: 22, weight: .semibold))
                    Image(systemName: showFilterTags ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Notification filters")
                .accessibilityIdentifier("notification.filter-toggle")
            }
            .accessibilityIdentifier("notification.filter-toggle")

            Spacer()
            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 20)
    }

    private var filterStrip: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    filterTag(.all, title: "All")
                    filterTag(.unread, title: "Unread")
                    filterTag(.activity, title: "Activity")
                    filterTag(.system, title: "System")
                }
                .padding(.horizontal, 20)
            }

            Button {
                store.markAllLoadedRead()
            } label: {
                Text(store.isMarkingAll ? "Reading…" : "Read All")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 72)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.purple.opacity(0.45))
                    )
            }
            .disabled(store.unreadCount == 0 || store.isMarkingAll)
            .opacity(store.unreadCount == 0 ? 0.45 : 1)
            .accessibilityIdentifier("notification.read-all")
            .padding(.trailing, 20)
        }
        .padding(.bottom, 10)
    }

    private func filterTag(
        _ filter: NotificationFilter,
        title: String
    ) -> some View {
        NotificationFilterTag(
            title: title,
            isSelected: selectedFilter == filter
        ) {
            selectedFilter = filter
        }
        .frame(width: 95)
        .accessibilityIdentifier("notification.filter.\(filter.rawValue)")
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
            ProgressView().tint(.white).scaleEffect(1.2)
            Text("Loading…").foregroundColor(.white.opacity(0.8))
            Spacer()
        }
    }

    private func loadErrorView(_ error: NotificationInboxError) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.6))
            Text("Loading Failed")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
            Text(errorMessage(error))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
            Button("Retry") { store.retryLastFailure() }
                .foregroundColor(.white)
                .padding(.top, 10)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.white.opacity(0.55))
            Text("No notifications")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .accessibilityIdentifier("notification.list.empty")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var notificationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text("Loaded")
                    .font(.system(size: 1))
                    .foregroundColor(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("notification.list.loaded")

                ForEach(groupedNotifications, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(group.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)

                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) {
                                index, notification in
                                Button { open(notification) } label: {
                                    NotificationItemView(notification: notification)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("notification.row.\(notification.id)")
                                .onAppear {
                                    if notification.id == store
                                        .filteredItems(selectedFilter).last?.id {
                                        store.loadMore()
                                    }
                                }

                                if index < group.items.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                        .padding(.leading, 60)
                                }
                            }
                        }
                        .padding(.vertical, 15)
                        .background(notificationCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                    }
                }

                if store.phase == .loadingMore {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 100)
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

    private var notificationCard: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.17), lineWidth: 1)
            )
    }

    private var actionError: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                Text("Couldn’t update notification. Try again.")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
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
            Image("home_bg").resizable().scaledToFill().ignoresSafeArea()
            VStack(spacing: 12) {
                Text(title).font(.title2).foregroundColor(.white)
                Text(value)
                    .foregroundColor(.white.opacity(0.8))
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
                        .fill(Color.purple)
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
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(3)
                Text(relativeTime(notification.createdAt))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var sourceImage: some View {
        if notification.kind.category == .system {
            ZStack {
                Circle().fill(Color.gray.opacity(0.3))
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
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

struct NotificationFilterTag: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            isSelected
                                ? Color.white.opacity(0.3)
                                : Color.white.opacity(0.1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                )
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    NavigationStack { NotificationView() }
}
