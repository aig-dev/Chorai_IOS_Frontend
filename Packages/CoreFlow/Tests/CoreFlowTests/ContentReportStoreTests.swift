import XCTest
@testable import CoreFlow

@MainActor
final class ContentReportStoreTests: XCTestCase {
    func testSubmitUsesSelectedReasonAndTrimmedOptionalDetail() async {
        let service = MockContentReportService()
        service.result = .success(
            ContentReportReceipt(
                reportID: "rpt_1",
                status: "OPEN",
                updatedAt: "2026-07-11T00:00:00Z"
            )
        )
        let store = ContentReportStore(
            targetType: .asset,
            targetID: "ast_1",
            service: service
        )

        store.selectReason(.copyright)
        store.updateDetail("  Source URL and context  ")
        store.submit()
        await waitForReportStore { store.phase.isSubmitted }

        XCTAssertEqual(
            service.requests,
            [
                ContentReportRequest(
                    targetType: "ASSET",
                    targetID: "ast_1",
                    reasonCode: "COPYRIGHT",
                    detail: "Source URL and context"
                )
            ]
        )
        XCTAssertEqual(store.phase.receipt?.reportID, "rpt_1")
    }

    func testSubmitOmitsWhitespaceOnlyDetail() async {
        let service = MockContentReportService()
        service.result = .success(
            ContentReportReceipt(
                reportID: "rpt_2",
                status: "OPEN",
                updatedAt: "2026-07-11T00:00:00Z"
            )
        )
        let store = ContentReportStore(
            targetType: .asset,
            targetID: "ast_2",
            service: service
        )

        store.updateDetail("  \n ")
        store.submit()
        await waitForReportStore { store.phase.isSubmitted }

        XCTAssertNil(service.requests.first?.detail)
    }

    func testActorTargetUsesCanonicalActorType() async {
        let service = MockContentReportService()
        service.result = .success(
            ContentReportReceipt(
                reportID: "rpt_actor",
                status: "OPEN",
                updatedAt: "2026-07-11T00:00:00Z"
            )
        )
        let store = ContentReportStore(
            targetType: .actor,
            targetID: "act_1",
            service: service
        )

        store.submit()
        await waitForReportStore { store.phase.isSubmitted }

        XCTAssertEqual(service.requests.first?.targetType, "ACTOR")
        XCTAssertEqual(service.requests.first?.targetID, "act_1")
    }

    func testCommentTargetUsesCanonicalCommentType() async {
        let service = MockContentReportService()
        service.result = .success(
            ContentReportReceipt(
                reportID: "rpt_comment",
                status: "OPEN",
                updatedAt: "2026-07-22T00:00:00Z"
            )
        )
        let store = ContentReportStore(
            targetType: .comment,
            targetID: "cmt_1",
            service: service
        )

        store.submit()
        await waitForReportStore { store.phase.isSubmitted }

        XCTAssertEqual(service.requests.first?.targetType, "COMMENT")
        XCTAssertEqual(service.requests.first?.targetID, "cmt_1")
    }

    func testRetryPreservesDraftAndResubmitsExactRequest() async {
        let service = MockContentReportService()
        service.results = [
            .failure(.transport(code: "report_offline")),
            .success(
                ContentReportReceipt(
                    reportID: "rpt_3",
                    status: "OPEN",
                    updatedAt: "2026-07-11T00:00:00Z"
                )
            )
        ]
        let store = ContentReportStore(
            targetType: .asset,
            targetID: "ast_3",
            service: service
        )

        store.selectReason(.misinformation)
        store.updateDetail("Evidence")
        store.submit()
        await waitForReportStore {
            store.phase == .failed(.transport(code: "report_offline"))
        }

        XCTAssertEqual(store.reason, .misinformation)
        XCTAssertEqual(store.detail, "Evidence")
        store.retry()
        await waitForReportStore { store.phase.isSubmitted }

        XCTAssertEqual(service.requests.count, 2)
        XCTAssertEqual(service.requests[0], service.requests[1])
    }

    private func waitForReportStore(
        timeoutIterations: Int = 500,
        _ predicate: @escaping () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for report store state")
    }
}

private final class MockContentReportService: ContentReportServing, @unchecked Sendable {
    var result: Result<ContentReportReceipt, ContentReportError> =
        .failure(.transport(code: "missing_report_fixture"))
    var results: [Result<ContentReportReceipt, ContentReportError>] = []
    private(set) var requests: [ContentReportRequest] = []

    func createReport(
        _ request: ContentReportRequest
    ) async throws -> ContentReportReceipt {
        requests.append(request)
        if !results.isEmpty {
            return try results.removeFirst().get()
        }
        return try result.get()
    }
}
