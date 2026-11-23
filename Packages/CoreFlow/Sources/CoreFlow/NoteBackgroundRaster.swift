import Foundation

/// ImageIO decodes pixels. This walk verifies that the entire selected file is the
/// described container, including metadata and frames ImageIO need not read for frame zero.
enum NoteBackgroundRaster {
    private static var invalid: NoteBackgroundError { .invalidImage }

    private struct Bytes {
        var rest: ArraySlice<UInt8>

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, count <= rest.count else { throw invalid }
            let result = rest.prefix(count)
            rest = rest.dropFirst(count)
            return result
        }

        mutating func byte() throws -> UInt8 {
            guard let first = rest.popFirst() else { throw invalid }
            return first
        }

        mutating func number(_ count: Int, littleEndian: Bool = true) throws -> Int {
            let bytes = try take(count)
            if littleEndian { return bytes.reversed().reduce(0) { ($0 << 8) | Int($1) } }
            return bytes.reduce(0) { ($0 << 8) | Int($1) }
        }

        mutating func text(_ count: Int) throws -> String {
            String(decoding: try take(count), as: UTF8.self)
        }
    }

    /// Return the verified EXIF orientation for JPEG. Other formats use their logical canvas.
    static func orientation(data: Data, type: String, width: Int, height: Int) throws -> Int {
        var input = Bytes(rest: Array(data)[...])
        switch type {
        case "public.jpeg": return try jpeg(&input)
        case "com.compuserve.gif": try gif(&input, width: width, height: height)
        case "org.webmproject.webp": try webP(&input, width: width, height: height)
        default: throw invalid
        }
        return 1
    }

    private static func jpeg(_ input: inout Bytes) throws -> Int {
        guard try input.number(2, littleEndian: false) == 0xffd8 else { throw invalid }
        var inScan = false
        var scanHasEntropy = false
        var sawScan = false
        var sawFrame = false
        var orientation: Int?
        while !input.rest.isEmpty {
            if inScan {
                guard let marker = input.rest.firstIndex(of: 0xff) else { throw invalid }
                if marker != input.rest.startIndex { scanHasEntropy = true }
                input.rest = input.rest[marker...]
            }
            guard try input.byte() == 0xff else { throw invalid }
            var marker = try input.byte()
            while marker == 0xff { marker = try input.byte() }
            if inScan && marker == 0 { scanHasEntropy = true; continue }
            if marker == 1 || (inScan && (0xd0...0xd7).contains(marker)) { continue }
            guard !inScan || scanHasEntropy else { throw invalid }
            inScan = false
            if marker == 0xd9 {
                guard input.rest.isEmpty, sawScan else { throw invalid }
                return orientation ?? 1
            }
            guard (0xe0...0xef).contains(marker) || [0xc0,0xc1,0xc2,0xc4,0xcc,0xda,0xdb,0xdd,0xfe].contains(marker) else { throw invalid }
            let length = try input.number(2, littleEndian: false)
            let segment = try input.take(length - 2)
            if (0xc0...0xc2).contains(marker) {
                guard !sawFrame else { throw invalid }
                sawFrame = true
            } else if marker == 0xda {
                guard sawFrame else { throw invalid }
                sawScan = true
                inScan = true
                scanHasEntropy = false
            } else if marker == 0xe1, segment.starts(with: [69,120,105,102,0,0]),
                      let value = try exifOrientation(segment.dropFirst(6)) {
                guard orientation == nil || orientation == value else { throw invalid }
                orientation = value
            }
        }
        throw invalid
    }

    private static func exifOrientation(_ tiff: ArraySlice<UInt8>) throws -> Int? {
        var header = Bytes(rest: tiff)
        let order = try header.text(2)
        let little = order == "II"
        guard little || order == "MM", try header.number(2, littleEndian: little) == 42 else { throw invalid }
        var offset = try header.number(4, littleEndian: little)
        guard offset >= 8 else { throw invalid }
        var visited = Set<Int>()
        var orientation: Int?
        let typeSizes = [0,1,1,2,4,8,1,1,2,4,8,4,8]
        while offset != 0 {
            // The Go contract allows the primary IFD and up to 32 linked directories.
            guard offset >= 8, offset <= tiff.count, visited.count < 33, visited.insert(offset).inserted else { throw invalid }
            var directory = Bytes(rest: tiff.dropFirst(offset))
            let entries = try directory.number(2, littleEndian: little)
            for _ in 0..<entries {
                let tag = try directory.number(2, littleEndian: little)
                let type = try directory.number(2, littleEndian: little)
                let count = try directory.number(4, littleEndian: little)
                var value = Bytes(rest: try directory.take(4))
                guard (1..<typeSizes.count).contains(type) else { throw invalid }
                let size = count * typeSizes[type]
                if size > 4 {
                    let location = try value.number(4, littleEndian: little)
                    guard location <= tiff.count, size <= tiff.count - location else { throw invalid }
                }
                if visited.count == 1 && tag == 0x0112 {
                    guard type == 3, count == 1 else { throw invalid }
                    let angle = try value.number(2, littleEndian: little)
                    guard (1...8).contains(angle), orientation == nil || orientation == angle else { throw invalid }
                    orientation = angle
                }
            }
            offset = try directory.number(4, littleEndian: little)
        }
        return orientation
    }

    private static func gif(_ input: inout Bytes, width: Int, height: Int) throws {
        let header = try input.text(6)
        guard ["GIF87a","GIF89a"].contains(header), try input.number(2) == width, try input.number(2) == height else { throw invalid }
        let packed = try input.byte()
        let background = try input.byte()
        _ = try input.byte()
        let globalColors = packed & 0x80 == 0 ? 0 : 1 << (Int(packed & 7) + 1)
        guard globalColors == 0 || background < globalColors else { throw invalid }
        _ = try input.take(3 * globalColors)
        var pendingTransparent: Int?
        var sawImage = false
        while !input.rest.isEmpty {
            switch try input.byte() {
            case 0x3b:
                guard input.rest.isEmpty, pendingTransparent == nil, sawImage else { throw invalid }
                return
            case 0x21:
                switch try input.byte() {
                case 0xf9:
                    guard pendingTransparent == nil, try input.byte() == 4 else { throw invalid }
                    let flags = try input.byte()
                    guard flags & 0xe0 == 0, (flags >> 2) & 7 <= 3 else { throw invalid }
                    _ = try input.take(2)
                    let index = try input.byte()
                    pendingTransparent = flags & 1 == 0 ? 0 : Int(index)
                    guard try input.byte() == 0 else { throw invalid }
                case 0x01:
                    guard globalColors > 0, try input.byte() == 12 else { throw invalid }
                    _ = try input.take(12)
                    try subBlocks(&input)
                    pendingTransparent = nil
                case 0xff:
                    guard try input.byte() == 11 else { throw invalid }
                    _ = try input.take(11)
                    try subBlocks(&input)
                case 0xfe: try subBlocks(&input)
                default: throw invalid
                }
            case 0x2c:
                let left = try input.number(2), top = try input.number(2)
                let w = try input.number(2), h = try input.number(2)
                let flags = try input.byte()
                guard w > 0, h > 0, left + w <= width, top + h <= height, flags & 0x18 == 0 else { throw invalid }
                var colors = globalColors
                if flags & 0x80 != 0 {
                    colors = 1 << (Int(flags & 7) + 1)
                    _ = try input.take(colors * 3)
                }
                guard colors > 0, (pendingTransparent ?? 0) < colors,
                      (2...8).contains(try input.byte()), input.rest.first != 0 else { throw invalid }
                try subBlocks(&input)
                pendingTransparent = nil
                sawImage = true
            default: throw invalid
            }
        }
        throw invalid
    }

    private static func subBlocks(_ input: inout Bytes) throws {
        var length = try input.byte()
        while length != 0 {
            _ = try input.take(Int(length))
            length = try input.byte()
        }
    }

    private struct Chunk {
        let type: String
        var payload: Bytes

        init(_ input: inout Bytes) throws {
            type = try input.text(4)
            let size = try input.number(4)
            payload = Bytes(rest: try input.take(size))
            if !size.isMultiple(of: 2) {
                guard try input.byte() == 0 else { throw invalid }
            }
        }
    }

    private static func webP(_ input: inout Bytes, width: Int, height: Int) throws {
        guard try input.text(4) == "RIFF", try input.number(4) == input.rest.count,
              try input.text(4) == "WEBP" else { throw invalid }
        var first = try Chunk(&input)
        guard first.type == "VP8X" else {
            _ = try webPImage(first, width: width, height: height)
            guard input.rest.isEmpty else { throw invalid }
            return
        }
        let flags = try first.payload.byte()
        guard flags & ~0x3e == 0, try first.payload.number(3) == 0,
              try first.payload.number(3) + 1 == width, try first.payload.number(3) + 1 == height,
              first.payload.rest.isEmpty else { throw invalid }

        // Extended WebP places its optional profile before the image and metadata after it.
        var next = try Chunk(&input)
        if flags & 0x20 != 0 {
            guard next.type == "ICCP", !next.payload.rest.isEmpty else { throw invalid }
            next = try Chunk(&input)
        }
        var hasAlpha = false
        if flags & 2 != 0 {
            guard next.type == "ANIM", next.payload.rest.count == 6 else { throw invalid }
            next = try Chunk(&input)
            guard next.type == "ANMF" else { throw invalid }
            while next.type == "ANMF" {
                let alpha = try webPFrame(&next.payload, width: width, height: height)
                hasAlpha = hasAlpha || alpha
                if input.rest.isEmpty { break }
                next = try Chunk(&input)
            }
            if next.type == "ANMF" {
                guard flags & 0x0c == 0, hasAlpha == (flags & 0x10 != 0) else { throw invalid }
                return
            }
        } else {
            hasAlpha = try webPImageGroup(next, in: &input, width: width, height: height)
            guard hasAlpha == (flags & 0x10 != 0) else { throw invalid }
            if input.rest.isEmpty {
                guard flags & 0x0c == 0 else { throw invalid }
                return
            }
            next = try Chunk(&input)
        }
        guard hasAlpha == (flags & 0x10 != 0) else { throw invalid }
        if flags & 8 != 0 {
            guard next.type == "EXIF", !next.payload.rest.isEmpty else { throw invalid }
            if flags & 4 != 0 { next = try Chunk(&input) }
        } else if flags & 4 == 0 { throw invalid }
        if flags & 4 != 0 {
            guard next.type == "XMP ", !next.payload.rest.isEmpty else { throw invalid }
        }
        guard input.rest.isEmpty else { throw invalid }
    }

    private static func webPFrame(_ frame: inout Bytes, width: Int, height: Int) throws -> Bool {
        let x = try frame.number(3) * 2, y = try frame.number(3) * 2
        let w = try frame.number(3) + 1, h = try frame.number(3) + 1
        _ = try frame.take(3) // duration
        guard x + w <= width, y + h <= height, try frame.byte() & ~3 == 0 else { throw invalid }
        let first = try Chunk(&frame)
        let alpha = try webPImageGroup(first, in: &frame, width: w, height: h)
        guard frame.rest.isEmpty else { throw invalid }
        return alpha
    }

    private static func webPImageGroup(_ first: Chunk, in input: inout Bytes, width: Int, height: Int) throws -> Bool {
        guard first.type == "ALPH" else { return try webPImage(first, width: width, height: height) }
        var alpha = first.payload
        let flags = try alpha.byte()
        guard !alpha.rest.isEmpty, flags & 0xc0 == 0, (flags >> 4) & 3 <= 1, flags & 3 <= 1,
              flags & 3 != 0 || alpha.rest.count == width * height else { throw invalid }
        let primary = try Chunk(&input)
        guard primary.type == "VP8 " else { throw invalid }
        _ = try webPImage(primary, width: width, height: height)
        return true
    }

    private static func webPImage(_ chunk: Chunk, width: Int, height: Int) throws -> Bool {
        var payload = chunk.payload
        switch chunk.type {
        case "VP8L":
            guard try payload.byte() == 0x2f else { throw invalid }
            let descriptor = try payload.number(4)
            guard descriptor >> 29 == 0, !payload.rest.isEmpty,
                  (descriptor & 0x3fff) + 1 == width, ((descriptor >> 14) & 0x3fff) + 1 == height else { throw invalid }
            return descriptor & (1 << 28) != 0
        case "VP8 ":
            let tag = try payload.number(3)
            guard tag & 1 == 0, (tag >> 1) & 7 <= 3, tag & 0x10 != 0,
                  try payload.number(3, littleEndian: false) == 0x9d012a,
                  try payload.number(2) & 0x3fff == width, try payload.number(2) & 0x3fff == height,
                  tag >> 5 > 0, tag >> 5 <= payload.rest.count else { throw invalid }
            return false
        default: throw invalid
        }
    }
}
