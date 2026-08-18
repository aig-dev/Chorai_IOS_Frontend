import XCTest
@testable import BlockNoteEditor

final class BlockNoteEditorCommandTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func testInitializeEncodesExactVersionedEnvelopeIncludingNullDocument() throws {
        let command = BlockNoteEditorCommand.initialize(
            protocolVersion: 3,
            documentJSON: nil,
            fallbackMarkdown: "Fallback",
            editable: false,
            profile: .standard
        )

        XCTAssertEqual(
            String(decoding: try encoder.encode(command), as: UTF8.self),
            #"{"documentJSON":null,"editable":false,"fallbackMarkdown":"Fallback","profile":"standard","protocolVersion":3,"type":"initialize"}"#
        )
    }

    func testInitializeCarriesExplicitMergeArtifactProfileAndLegacyWireDefaultsStandard() throws {
        let command = BlockNoteEditorCommand.initialize(
            protocolVersion: 3,
            documentJSON: "[]",
            fallbackMarkdown: "",
            editable: true,
            profile: .mergeArtifact
        )
        XCTAssertEqual(
            String(decoding: try encoder.encode(command), as: UTF8.self),
            #"{"documentJSON":"[]","editable":true,"fallbackMarkdown":"","profile":"mergeArtifact","protocolVersion":3,"type":"initialize"}"#
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                BlockNoteEditorCommand.self,
                from: Data(
                    #"{"documentJSON":null,"editable":false,"fallbackMarkdown":"Legacy","protocolVersion":3,"type":"initialize"}"#.utf8
                )
            ),
            .initialize(
                protocolVersion: 3,
                documentJSON: nil,
                fallbackMarkdown: "Legacy",
                editable: false,
                profile: .standard
            )
        )
    }

    func testCommandsUseWebRuntimeKeysAndEnumValues() throws {
        let cases: [(BlockNoteEditorCommand, String)] = [
            (.applyFormat(.bold), #"{"format":"bold","type":"applyFormat"}"#),
            (.applyFormat(.strike), #"{"format":"strike","type":"applyFormat"}"#),
            (.setBlockType(.paragraph), #"{"blockType":"paragraph","type":"setBlockType"}"#),
            (.setBlockType(.heading2), #"{"blockType":"heading2","type":"setBlockType"}"#),
            (.setBlockType(.heading3), #"{"blockType":"heading3","type":"setBlockType"}"#),
            (.toggleList(.bullet), #"{"listType":"bullet","type":"toggleList"}"#),
            (.toggleList(.numbered), #"{"listType":"numbered","type":"toggleList"}"#),
            (.toggleList(.checklist), #"{"listType":"checklist","type":"toggleList"}"#),
            (.insertLink(url: "https://example.com", text: "Example"), #"{"text":"Example","type":"insertLink","url":"https:\/\/example.com"}"#),
            (.insertImage(url: "https://example.com/image.png", alt: "Image"), #"{"alt":"Image","type":"insertImage","url":"https:\/\/example.com\/image.png"}"#),
            (.undo, #"{"type":"undo"}"#),
            (.redo, #"{"type":"redo"}"#),
            (.focus, #"{"type":"focus"}"#),
            (.blur, #"{"type":"blur"}"#),
            (.requestSnapshot(requestID: "save-1"), #"{"requestID":"save-1","type":"requestSnapshot"}"#),
        ]

        for (command, expectedJSON) in cases {
            let data = try encoder.encode(command)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), expectedJSON)
            XCTAssertEqual(try JSONDecoder().decode(BlockNoteEditorCommand.self, from: data), command)
        }
    }

    func testCommandEnumsRejectUnsupportedWireValues() {
        let invalidCommands = [
            #"{"type":"applyFormat","format":"rainbow"}"#,
            #"{"type":"setBlockType","blockType":"heading1"}"#,
            #"{"type":"toggleList","listType":"outline"}"#,
            #"{"type":"requestSnapshot","requestID":""}"#,
            #"{"type":"futureCommand"}"#,
        ]

        for json in invalidCommands {
            XCTAssertThrowsError(
                try JSONDecoder().decode(BlockNoteEditorCommand.self, from: Data(json.utf8)),
                "Expected rejection for \(json)"
            )
        }
    }
}
