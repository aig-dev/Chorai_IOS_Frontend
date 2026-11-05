import Foundation
import XCTest

final class TrashCardDecodeRuntimeTests: XCTestCase {
    func testActualTrashModelKeepsReadTimeSyncToken() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent("ArcNote/Models/TrashModels.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "struct TrashCard:"))
        let open = try XCTUnwrap(source[start.lowerBound...].firstIndex(of: "{"))
        var depth = 0
        var end = open
        for index in source[open...].indices {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" { depth -= 1 }
            if depth == 0 { end = source.index(after: index); break }
        }
        let model = String(source[start.lowerBound..<end])
        let payload = #"{"id":"note","content":"text","content_hash":"hash","is_public":false,"tags":[],"created_at":"now","updated_at":"now","deleted_at":"now","days_remaining":30,"like_count":0,"is_liked":false,"sync_token":"read-time-baseline"}"#
        let script = "import Foundation\n" + model + "\nlet card = try JSONDecoder().decode(TrashCard.self, from: Data(#\"" + payload + "\"#.utf8))\nprint(card.syncToken ?? \"nil\")\n"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".swift")
        try script.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swift", file.path]
        process.standardOutput = output; process.standardError = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: bytes, as: UTF8.self))
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), "read-time-baseline")
    }
}
