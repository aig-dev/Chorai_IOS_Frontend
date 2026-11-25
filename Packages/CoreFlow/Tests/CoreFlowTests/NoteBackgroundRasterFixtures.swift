import Foundation

// Frozen descriptor_v1_test.go vectors from Go 27e5295f.
enum NoteBackgroundRasterFixtures {
    struct Vector {
        let name: String
        let bytes: String
        let width: Int
        let height: Int
    }

    static let vectors: [Vector] = [
        .init(name: "BigEndianEXIFAndEntropyMarkers", bytes: "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f/8A/9D/2Q==", width: 2, height: 3),
        .init(name: "BigEndianEXIFAndEntropyMarkers", bytes: "/9j/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 3, height: 2),
        .init(name: "FrozenPNGAndGIFVectors_exact_34-byte_Gate_D_GIF", bytes: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==", width: 1, height: 1),
        .init(name: "FrozenPNGAndGIFVectors_exact_68-byte_Gate_D_PNG", bytes: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", width: 1, height: 1),
        .init(name: "GIFHeadersAndLogicalCanvas_GIF87a", bytes: "R0lGODdhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==", width: 1, height: 1),
        .init(name: "GIFHeadersAndLogicalCanvas_GIF89a_multi-frame_logical_canvas", bytes: "R0lGODlhAgABAIAAAAAAAP///ywAAAAAAQABAAACAUwALAEAAAABAAEAAAIBTAA7", width: 2, height: 1),
        .init(name: "JPEGEXIFOrientations_absent", bytes: "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 2, height: 3),
        .init(name: "JPEGEXIFOrientations_orientation_1", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAAAQAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 2, height: 3),
        .init(name: "JPEGEXIFOrientations_orientation_2", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAAAgAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 2, height: 3),
        .init(name: "JPEGEXIFOrientations_orientation_3", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAAAwAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 2, height: 3),
        .init(name: "JPEGEXIFOrientations_orientation_4", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAABAAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 2, height: 3),
        .init(name: "JPEGEXIFOrientations_orientation_5", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAABQAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 3, height: 2),
        .init(name: "JPEGEXIFOrientations_orientation_6", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAABgAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 3, height: 2),
        .init(name: "JPEGEXIFOrientations_orientation_7", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAABwAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 3, height: 2),
        .init(name: "JPEGEXIFOrientations_orientation_8", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAACAAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 3, height: 2),
        .init(name: "RejectsMalformedFormatEnvelopes_BMP_alias", bytes: "Qk0AAAAA", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_GIF_frame_outside_logical_canvas", bytes: "R0lGODlhAgABAIAAAAAAAP///ywAAAAAAQABAAACAUwALAIAAAABAAEAAAIBTAA7", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_GIF_no_active_color_table", bytes: "R0lGODlhAQABAAAAAAAAAP///ywAAAAAAQABAAACAUwAOw==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_GIF_no_image", bytes: "R0lGODlhAQABAIAAAAAAAP///zs=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_GIF_trailing_garbage", bytes: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOwA=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_GIF_truncated_data_sub-block", bytes: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAkwAOw==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_GIF_truncated_trailer", bytes: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwA", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_GIF_unused_graphic_control_extension", bytes: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAIfkEAAAAAAA7", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_JPEG_bad_segment_length", bytes: "/9j/4AABSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_JPEG_conflicting_EXIF_authorities", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAABgAAAAAAAAD/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAAAQAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_JPEG_malformed_EXIF", bytes: "/9j/4QAiRXhpZgAAWkkqAAgAAAABABIBAwABAAAABgAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_JPEG_nested_SOI_in_scan", bytes: "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Y/9k=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_JPEG_orientation_nine", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAACQAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_JPEG_orientation_zero", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAAAAAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_JPEG_trailing_garbage", bytes: "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//ZAA==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_JPEG_truncated_EOI", bytes: "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f/8=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_JPEG_truncated_next_IFD", bytes: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAABgAAABgAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_PNG_bad_CRC", bytes: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC0HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_PNG_duplicate_IHDR", bytes: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAADUlIRFIAAAABAAAAAQgEAAAAtRwMAgAAAAtJREFUeNpjZPgPAAEFAQEnGONmAAAAAElFTkSuQmCC", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_PNG_missing_IDAT", bytes: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAAElFTkSuQmCC", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_PNG_only_zero-length_IDAT", bytes: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAAElEQVQ1rwYeAAAAAElFTkSuQmCC", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_PNG_oversized_chunk_length", bytes: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC/////0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_PNG_trailing_garbage", bytes: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYIIA", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_PNG_truncated", bytes: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYA==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_PNG_unknown_critical_chunk", bytes: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0pEQVR42mNk+A8AAQUBATZliR8AAAAASUVORK5CYII=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_ICCP_after_alpha", bytes: "UklGRmgAAABXRUJQVlA4WAoAAAAwAAAAAQAAAgAAQUxQSAcAAAAAf39/f39/AElDQ1ABAAAAAABWUDggMAAAANABAJ0BKgIAAwABQCYloAJ0ugH4AAOwAP7y63/82BXNc+/3/9Lg/S4P0uD/0pAAAA==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_RIFF_size_mismatch", bytes: "UklGRj0AAABXRUJQVlA4IDIAAADwAQCdASoCAAMAAUAmJaACdLoB+AAETAAA/vNpl/5glfkG7UP/0uD9Lg/S4P/SkAAAAA==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_VP8L_signature_mismatch", bytes: "UklGRhwAAABXRUJQVlA4TA8AAAAuAYAAAAcQ5Y/+ByKi/wEA", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_VP8_reserved_version", bytes: "UklGRj4AAABXRUJQVlA4IDIAAAD4AQCdASoCAAMAAUAmJaACdLoB+AAETAAA/vNpl/5glfkG7UP/0uD9Lg/S4P/SkAAAAA==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_VP8_signature_mismatch", bytes: "UklGRj4AAABXRUJQVlA4IDIAAADwAQCcASoCAAMAAUAmJaACdLoB+AAETAAA/vNpl/5glfkG7UP/0uD9Lg/S4P/SkAAAAA==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_alpha_flag_mismatch", bytes: "UklGRl4AAABXRUJQVlA4WAoAAAAAAAAAAQAAAgAAQUxQSAcAAAAAf39/f39/AFZQOCAwAAAA0AEAnQEqAgADAAFAJiWgAnS6AfgAA7AA/vLrf/zYFc1z7/f/0uD9Lg/S4P/SkAAA", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_animation_flag_mismatch", bytes: "UklGRoQAAABXRUJQVlA4WAoAAAAAAAAAAQAAAgAAQU5JTQYAAAD/////AABBTk1GKAAAAAAAAAAAAAEAAAIAAGQAAAJWUDhMDwAAAC8BgAAABxDlj/4HIqL/AQBBTk1GKAAAAAAAAAAAAAEAAAIAAGQAAABWUDhMDwAAAC8BgAAABxDR/v4HIqL/AQA=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_chunk_size_overflow", bytes: "UklGRj4AAABXRUJQVlA4IEYAAADwAQCdASoCAAMAAUAmJaACdLoB+AAETAAA/vNpl/5glfkG7UP/0uD9Lg/S4P/SkAAAAA==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_frame_outside_canvas", bytes: "UklGRoQAAABXRUJQVlA4WAoAAAACAAAAAQAAAgAAQU5JTQYAAAD/////AABBTk1GKAAAAAEAAAAAAAEAAAIAAGQAAAJWUDhMDwAAAC8BgAAABxDlj/4HIqL/AQBBTk1GKAAAAAAAAAAAAAEAAAIAAGQAAABWUDhMDwAAAC8BgAAABxDR/v4HIqL/AQA=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_nonzero_RIFF_padding", bytes: "UklGRhwAAABXRUJQVlA4TA8AAAAvAYAAAAcQ5Y/+ByKi/wEB", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_raw_alpha_payload_truncated", bytes: "UklGRlwAAABXRUJQVlA4WAoAAAAQAAAAAQAAAgAAQUxQSAYAAAAAAAAAAABWUDggMAAAANABAJ0BKgIAAwABQCYloAJ0ugH4AAOwAP7y63/82BXNc+/3/9Lg/S4P0uD/0pAAAA==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_static_canvas_mismatch", bytes: "UklGRl4AAABXRUJQVlA4WAoAAAAQAAAAAgAAAgAAQUxQSAcAAAAAf39/f39/AFZQOCAwAAAA0AEAnQEqAgADAAFAJiWgAnS6AfgAA7AA/vLrf/zYFc1z7/f/0uD9Lg/S4P/SkAAA", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_trailing_garbage", bytes: "UklGRj4AAABXRUJQVlA4IDIAAADwAQCdASoCAAMAAUAmJaACdLoB+AAETAAA/vNpl/5glfkG7UP/0uD9Lg/S4P/SkAAAAAA=", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_WebP_truncated", bytes: "UklGRj4AAABXRUJQVlA4IDIAAADwAQCdASoCAAMAAUAmJaACdLoB+AAETAAA/vNpl/5glfkG7UP/0uD9Lg/S4P/SkAAA", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_big-endian_TIFF_alias", bytes: "TU0AKg==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_empty", bytes: "", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_little-endian_TIFF_alias", bytes: "SUkqAA==", width: 0, height: 0),
        .init(name: "RejectsMalformedFormatEnvelopes_unknown_magic_with_authored_content", bytes: "YXV0aG9yZWQtc2VjcmV0LWltYWdlLWJ5dGVz", width: 0, height: 0),
        .init(name: "WebPVariants_VP8L", bytes: "UklGRhwAAABXRUJQVlA4TA8AAAAvAYAAAAcQ5Y/+ByKi/wEA", width: 2, height: 3),
        .init(name: "WebPVariants_VP8X_animated", bytes: "UklGRoQAAABXRUJQVlA4WAoAAAACAAAAAQAAAgAAQU5JTQYAAAD/////AABBTk1GKAAAAAAAAAAAAAEAAAIAAGQAAAJWUDhMDwAAAC8BgAAABxDlj/4HIqL/AQBBTk1GKAAAAAAAAAAAAAEAAAIAAGQAAABWUDhMDwAAAC8BgAAABxDR/v4HIqL/AQA=", width: 2, height: 3),
        .init(name: "WebPVariants_VP8X_static_alpha", bytes: "UklGRl4AAABXRUJQVlA4WAoAAAAQAAAAAQAAAgAAQUxQSAcAAAAAf39/f39/AFZQOCAwAAAA0AEAnQEqAgADAAFAJiWgAnS6AfgAA7AA/vLrf/zYFc1z7/f/0uD9Lg/S4P/SkAAA", width: 2, height: 3),
        .init(name: "WebPVariants_VP8X_static_compressed_alpha", bytes: "UklGRpIAAABXRUJQVlA4WAoAAAAQAAAAYwAAYwAAQUxQSBEAAAABB9C/iAgDkBD+75ci+p9KBABWUDggWgAAABAGAJ0BKmQAZAA+bTaZSaQjIqEgqACADYlpbuFz6XAfgAABja6m9xF5YBrqb3EXlgGupvcReWAaeAD+/lF9//+QXLC65Gv//yA/5Af8gP/4+KZGlSp0IAAAAA==", width: 100, height: 100),
        .init(name: "WebPVariants_VP8", bytes: "UklGRj4AAABXRUJQVlA4IDIAAADwAQCdASoCAAMAAUAmJaACdLoB+AAETAAA/vNpl/5glfkG7UP/0uD9Lg/S4P/SkAAAAA==", width: 2, height: 3),
        .init(name: "WebPVariants_VP8_scaling_hints_do_not_author_dimensions", bytes: "UklGRj4AAABXRUJQVlA4IDIAAADwAQCdASoCwAOAAUAmJaACdLoB+AAETAAA/vNpl/5glfkG7UP/0uD9Lg/S4P/SkAAAAA==", width: 2, height: 3),
    ]


    // Fixed header controls checked against visualcontract.DeriveImageDescriptorV1 at 27e5295f.
    // Each range changes only the indicated field in one small reference file.
    static let headerControls: [(name: String, image: Data, accepted: Bool)] = {
        let jpeg = Data(base64Encoded: "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z")!
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let indexed = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADAQMAAACDJEzCAAAABlBMVEUAAABvIQEddBCnAAAAAXRSTlMAQObYZgAAAAtJREFUeJxjYAABAAAGAAH+jGfIAAAAAElFTkSuQmCC")!
        func replacing(_ image: Data, _ range: Range<Int>, with bytes: [UInt8]) -> Data {
            var result = image
            result.replaceSubrange(range, with: bytes)
            return result
        }
        return [
            ("DQT-unused-8bit", replacing(jpeg, 205..<205, with: Array(Data(base64Encoded: "2wBDAwYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgb/")!)), true),
            ("DQT-unused-16bit", replacing(jpeg, 205..<205, with: Array(Data(base64Encoded: "2wCDEwYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYG/w==")!)), true),
            ("DQT-incomplete-second", replacing(jpeg, 205..<205, with: Array(Data(base64Encoded: "2wBEAwYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYD/w==")!)), false),
            ("DQT-invalid-precision", replacing(jpeg, 205..<205, with: Array(Data(base64Encoded: "2wBDIwYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgb/")!)), false),
            ("DHT-unused", replacing(jpeg, 205..<205, with: Array(Data(base64Encoded: "xAAUAwEAAAAAAAAAAAAAAAAAAAAA/w==")!)), true),
            ("DHT-empty-symbols", replacing(jpeg, 205..<205, with: Array(Data(base64Encoded: "xAATAAAAAAAAAAAAAAAAAAAAAAD/")!)), false),
            ("DHT-short-symbol-list", replacing(jpeg, 205..<205, with: Array(Data(base64Encoded: "xAAUAwIAAAAAAAAAAAAAAAAAAAAA/w==")!)), false),
            ("DHT-invalid-slot", replacing(jpeg, 205..<205, with: Array(Data(base64Encoded: "xAAUBAEAAAAAAAAAAAAAAAAAAAAA/w==")!)), false),
            ("DAC-unused-pair", replacing(jpeg, 205..<205, with: [0xcc, 0x00, 0x04, 0x03, 0x00, 0xff]), true),
            ("DAC-incomplete-pair", replacing(jpeg, 205..<205, with: [0xcc, 0x00, 0x03, 0x03, 0xff]), false),
            ("DAC-invalid-class", replacing(jpeg, 205..<205, with: [0xcc, 0x00, 0x04, 0x23, 0x00, 0xff]), false),
            ("DRI-zero", replacing(jpeg, 205..<205, with: [0xdd, 0x00, 0x04, 0x00, 0x00, 0xff]), true),
            ("DRI-short", replacing(jpeg, 205..<205, with: [0xdd, 0x00, 0x03, 0x00, 0xff]), false),
            ("SOF-precision", replacing(jpeg, 189..<190, with: [0x0c]), false),
            ("SOF-count", replacing(jpeg, 194..<195, with: [0x02]), false),
            ("SOF-duplicate-id", replacing(jpeg, 198..<199, with: [0x01]), false),
            ("SOF-sampling-three", replacing(jpeg, 196..<197, with: [0x31]), false),
            ("SOF-quant-slot", replacing(jpeg, 197..<198, with: [0x04]), false),
            ("SOS-unknown-id", replacing(jpeg, 209..<210, with: [0x0e]), false),
            ("SOS-selector", replacing(jpeg, 210..<211, with: [0x40]), false),
            ("SOS-sequential-end", replacing(jpeg, 216..<217, with: [0x3e]), false),
            ("SOS-progressive-invalid-DC", replacing(jpeg, 186..<187, with: [0xc2]), false),
            ("PNG-color", replacing(png, 25..<33, with: [0x07, 0x00, 0x00, 0x00, 0xa7, 0xa9, 0xa3, 0xec]), false),
            ("PNG-depth", replacing(png, 24..<33, with: [0x06, 0x04, 0x00, 0x00, 0x00, 0x0a, 0x2c, 0xb2, 0x63]), false),
            ("PNG-compression", replacing(png, 26..<33, with: [0x01, 0x00, 0x00, 0xb4, 0xde, 0x66, 0x35]), false),
            ("PNG-filter", replacing(png, 27..<33, with: [0x01, 0x00, 0xac, 0x07, 0x3d, 0x43]), false),
            ("PNG-interlace", replacing(png, 28..<33, with: [0x02, 0x5b, 0x12, 0x6d, 0x2e]), false),
            ("JPEG-progressive", Data(base64Encoded: "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wgARCAADAAIDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUAQEAAAAAAAAAAAAAAAAAAAAE/9oADAMBAAIQAxAAAAGdAy//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAEFAn//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/AX//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/AX//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/An//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/IX//2gAMAwEAAgADAAAAEPf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==")!, true),
            ("JPEG-gray", Data(base64Encoded: "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAADAAIBAREA/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/9oACAEBAAA/AHV//9k=")!, true),
            ("JPEG-CMYK", Data(base64Encoded: "/9j/7gAOQWRvYmUAZAAAAAAA/9sAQwAIBgYHBgUIBwcHCQkICgwUDQwLCwwZEhMPFB0aHx4dGhwcICQuJyAiLCMcHCg3KSwwMTQ0NB8nOT04MjwuMzQy/8AAFAgAAwACBEMRAE0RAFkRAEsRAP/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/aAA4EQwBNAFkASwAAPwD2uulr3ivea//Z")!, true),
            ("PNG-indexed-transparency", indexed, true),
            ("PNG-indexed-before-palette", replacing(indexed, 36..<64, with: Array(Data(base64Encoded: "AXRSTlMAQObYZgAAAAZQTFRFAAAAbyEBHXQQpw==")!)), false),
            ("PNG-indexed-long-transparency", replacing(indexed, 53..<64, with: Array(Data(base64Encoded: "AQF0Uk5TAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAjW8YK")!)), false),
        ]
    }()
}
