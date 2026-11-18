import Foundation
import XCTest

final class AdaptiveLayoutSourceContractTests: XCTestCase {
    private let responsiveRoots = [
        "ArcNote/ContentView.swift",
        "ArcNote/HomeView.swift",
        "ArcNote/ExploreView.swift",
        "ArcNote/ChatView.swift",
        "ArcNote/ChatDetailView.swift",
        "ArcNote/DetailView.swift",
        "ArcNote/RootView.swift",
        "ArcNote/SearchView.swift",
        "ArcNote/UserProfileView.swift",
        "ArcNote/MyProfileView.swift",
        "ArcNote/SettingsView.swift",
        "ArcNote/ChoraProfileView.swift",
        "ArcNote/NotificationView.swift",
        "ArcNote/TrashView.swift",
        "ArcNote/PreferencesView.swift",
        "ArcNote/AccountDetailsView.swift",
        "ArcNote/EditProfileView.swift",
        "ArcNote/APIAndPluginsView.swift",
        "ArcNote/InvitationCreditView.swift",
        "ArcNote/InvitationCreditDetailViews.swift",
        "ArcNote/FollowListView.swift",
        "ArcNote/BlockedActorsView.swift",
        "ArcNote/ChooseInterestsView.swift",
        // NewNoteView delegates its visible root to this shared editor shell.
        "ArcNote/CardEditor/CardEditorShell.swift",
        "ArcNote/CoreFlow/SparkContinuationViews.swift",
        "ArcNote/CoreFlow/MergeLifecycleViews.swift",
        "ArcNote/CoreFlow/ShareCardView.swift",
        "ArcNote/CoreFlow/ContentReportView.swift",
    ]

    func testAppOwnsSharedAdaptiveLayout() throws {
        let layout = try source(at: "ArcNote/AdaptiveLayout.swift")
        let project = try source(at: "ArcNote.xcodeproj/project.pbxproj")

        XCTAssertTrue(layout.contains("struct AdaptiveLayoutMetrics"))
        XCTAssertTrue(layout.contains("static let compactGutter: CGFloat = 16"))
        XCTAssertTrue(layout.contains("static let standardGutter: CGFloat = 20"))
        XCTAssertTrue(layout.contains("static let wideGutter: CGFloat = 24"))
        XCTAssertTrue(
            layout.contains("struct AdaptiveLayoutReader<Content: View>")
        )
        XCTAssertTrue(
            layout.contains(
                "struct AdaptiveScreen<Background: View, Content: View>"
            )
        )
        XCTAssertTrue(
            layout.contains("struct AdaptiveSurface<Content: View>")
        )
        XCTAssertTrue(project.contains("/* AdaptiveLayout.swift in Sources */"))
    }

    func testEveryResponsiveRootUsesTheSharedGutter() throws {
        let systemFormRoots: Set<String> = [
            "ArcNote/CoreFlow/ShareCardView.swift",
            "ArcNote/CoreFlow/ContentReportView.swift",
        ]
        for path in responsiveRoots {
            let contents = try source(at: path)
            if systemFormRoots.contains(path) {
                XCTAssertTrue(contents.contains("Form {"), "\(path) uses the system adaptive Form insets")
                XCTAssertTrue(contents.contains("NavigationStack {"))
            } else if ["ArcNote/TrashView.swift", "ArcNote/SettingsView.swift", "ArcNote/BlockedActorsView.swift", "ArcNote/InvitationCreditView.swift", "ArcNote/InvitationCreditDetailViews.swift"].contains(path) {
                XCTAssertTrue(contents.contains("Form {") || contents.contains("List {"), "System containers own the adaptive row insets")
                XCTAssertTrue(contents.contains(".navigationTitle("), "The existing parent navigation stack owns these destinations")
            } else if path == "ArcNote/DetailView.swift" {
                XCTAssertTrue(contents.contains(".padding(.horizontal, 24)"), "Full reading retains the V9 document gutter")
                XCTAssertTrue(contents.contains("ScrollView {"))
            } else if path == "ArcNote/CoreFlow/SparkContinuationViews.swift" {
                XCTAssertTrue(contents.contains(".padding(.horizontal, 22)"), "Spark uses the approved V6 reading gutter")
                XCTAssertTrue(contents.contains("ScrollView {"))
                XCTAssertTrue(contents.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
            } else {
                XCTAssertTrue(
                    contents.contains(".adaptiveContentGutter()"),
                    "\(path) must use the shared responsive content gutter"
                )
            }
        }
    }

    func testNativeLayoutSourcesDoNotReadGlobalScreenBounds() throws {
        let appDirectory = Self.repositoryRoot.appendingPathComponent("ArcNote")
        guard let files = FileManager.default.enumerator(
            at: appDirectory,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail("Unable to enumerate ArcNote source files")
            return
        }

        for case let url as URL in files where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                contents.contains("UIScreen.main.bounds"),
                "\(url.lastPathComponent) must use parent geometry instead"
            )
        }
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
