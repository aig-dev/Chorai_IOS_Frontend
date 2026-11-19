import Foundation

enum ExecutionFixtures {
    static func blockNoteDocument(blocks count: Int) throws -> String {
        let blocks = (0..<count).map { i in
            ["id": "b-\(i)", "type": "paragraph", "content": [["type": "text", "text": "A deliberate sentence number \(i)"]]] as [String: Any]
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: blocks, options: [.sortedKeys]), as: UTF8.self)
    }

    static func report(_ label: String, samples: [Double]) {
        let sorted = samples.sorted()
        print("EXECUTION_METRIC \(label) samples=\(samples.count) p50_ms=\(sorted[9]) p95_ms=\(sorted[18])")
    }
}
