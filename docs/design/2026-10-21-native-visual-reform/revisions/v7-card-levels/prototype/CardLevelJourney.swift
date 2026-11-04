import SwiftUI
import UIKit

/// Static source-faithful editions. Sample ratings here never mutate a note or growth.
enum NativeCardLevel: String, CaseIterable, Identifiable {
    case basic, notable, valuable, significant, exceptional, definitive
    var id: String { rawValue }
    var index: Int { Self.allCases.firstIndex(of: self)! }
    var roman: String { ["I", "II", "III", "IV", "V", "VI"][index] }
    var name: String { rawValue.capitalized }
    var hex: UInt32 { [0x9BA7AE, 0x57A781, 0x5294D9, 0xA881D4, 0xB39A55, 0xD66C61][index] }
    var sampleRate: Double { [0, 3, 9, 27, 81, 243][index] }
    var range: String { ["0–<3", "3–<9", "9–<27", "27–<81", "81–<243", "243+"][index] }
    var crop: CGRect {
        let values: [[CGFloat]] = [[48,188,441,300], [592,52,371,427], [1040,71,483,402], [50,496,446,465], [514,666,509,299], [1040,496,489,476]]
        let rect = values[index]
        return CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
    }
    var color: Color { Color(uiColor: PrototypeTheme.uiColor(hex)) }
    func ink(dark: Bool) -> Color {
        let factor: CGFloat = dark ? 1 : 0.63
        return Color(red: Double(CGFloat((hex >> 16) & 255) / 255 * factor),
                     green: Double(CGFloat((hex >> 8) & 255) / 255 * factor),
                     blue: Double(CGFloat(hex & 255) / 255 * factor))
    }
    var baseHeight: CGFloat { 60 * crop.height / crop.width }
    var spriteWidth: CGFloat { self == .definitive ? 67.2 : 60 }
    var spriteHeight: CGFloat { spriteWidth * crop.height / crop.width }
    var lift: CGFloat {
        if self == .significant { return baseHeight * 0.48 }
        if self == .definitive { return baseHeight * 0.64 }
        return max(0, baseHeight - 7)
    }
    func spriteX(cardWidth: CGFloat) -> CGFloat {
        if self == .significant { return -8 }
        let inset: CGFloat = self == .definitive ? -2 : self == .notable ? 8 : self == .exceptional ? 17 : 13
        return cardWidth - spriteWidth - inset
    }
    static func resolve(rate: Double?) -> Self? {
        guard let rate, rate.isFinite, rate >= 0 else { return nil }
        if rate < 3 { return .basic }; if rate < 9 { return .notable }
        if rate < 27 { return .valuable }; if rate < 81 { return .significant }
        if rate < 243 { return .exceptional }; return .definitive
    }
}

private enum CardLevelArtwork {
    /// Decode/crop only bundled approved atlases; preserve their original alpha and colors.
    static let sprites: [NativeCardLevel: UIImage] = {
        var result: [NativeCardLevel: UIImage] = [:]
        for level in NativeCardLevel.allCases {
            let name = level == .exceptional ? "exceptional-green-gold" : "perches"
            guard let path = Bundle.main.path(forResource: name, ofType: "png"),
                  let atlas = UIImage(contentsOfFile: path)?.cgImage,
                  let cropped = atlas.cropping(to: level.crop) else { continue }
            result[level] = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        }
        return result
    }()
}

private struct NativeLevelSprite: View {
    let level: NativeCardLevel
    var body: some View {
        Group {
            if let image = CardLevelArtwork.sprites[level] {
                Image(uiImage: image).renderingMode(.original).resizable().interpolation(.high).scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: level.spriteWidth, height: level.spriteHeight)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct NativeLevelLabel: View {
    let level: NativeCardLevel
    let dark: Bool
    var compact = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(level.roman).font(.system(size: compact ? 20 : 24, weight: .medium, design: .serif))
            Text(level.name).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.medium))
        }
        .foregroundStyle(level.ink(dark: dark))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Card level \(level.roman), \(level.name)")
        .accessibilityIdentifier("journey.levels.grade.\(level.rawValue)")
    }
}

struct CardLevelJourney: View {
    @Binding var state: PrototypeState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.prototypeTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scenario: String
    @State private var showsGuide = false
    @State private var reader: SampleNote?
    @State private var showsActions = false
    @State private var actionNote: SampleNote?
    @State private var actionMessage: String?

    init(state: Binding<PrototypeState>, initialStep: String = "guide") {
        _state = state
        let valid = NativeCardLevel.allCases.map(\.rawValue) + ["guide", "grid", "merge", "growth", "unknown"]
        _scenario = State(initialValue: valid.contains(initialStep) ? initialStep : "guide")
    }
    private var palette: Palette { Palette(dark: scheme == .dark, theme: theme) }
    private var currentLevel: NativeCardLevel? { NativeCardLevel(rawValue: scenario) }
    private var sampleNotes: [SampleNote] { state.notes.filter { !$0.isOwned } }
    private func sample(_ level: NativeCardLevel?) -> SampleNote? {
        guard !sampleNotes.isEmpty else { return nil }
        return sampleNotes[(level?.index ?? 0) % sampleNotes.count]
    }
    private var title: String {
        switch scenario {
        case "guide": "Card levels"
        case "grid": "Explore · Grid"
        case "merge": "Merge · Review"
        case "growth": "Your Chora"
        default: "Explore · Flow"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if scenario == "guide" { comparisonList(isSheet: false) }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            previewBadge
                            if scenario == "growth" { growth }
                            else if scenario == "grid" { grid }
                            else if scenario == "merge" { merge }
                            else { singleCard }
                            if let actionMessage {
                                Text(actionMessage).font(.footnote).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("journey.levels.feedback")
                            }
                        }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 28)
                    }.background(palette.background)
                }
            }
            .foregroundStyle(palette.ink)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                        .accessibilityIdentifier("journey.levels.close")
                }
                ToolbarItem(placement: .topBarTrailing) { previewMenu }
            }
            .sheet(isPresented: $showsGuide) {
                NavigationStack {
                    comparisonList(isSheet: true)
                        .navigationTitle("About card levels").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsGuide = false }.accessibilityIdentifier("journey.levels.guide.close")
                        } }
                }.presentationDragIndicator(.visible)
            }
            .sheet(item: $reader) { note in readerView(note) }
            .confirmationDialog("This sample note", isPresented: $showsActions, titleVisibility: .visible) {
                if let note = actionNote {
                    Button("Read full note") { reader = note }
                    Button(state.collected.contains(note.id) ? "Remove from collection" : "Collect") { toggleCollection(note) }
                    Button("About card levels") { showsGuide = true }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var previewBadge: some View {
        Label(scenario == "growth" ? "Preview only · sample growth" : "Preview only · sample ratings", systemImage: "eye")
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .accessibilityIdentifier("journey.levels.demo")
    }
    private var previewMenu: some View {
        Menu {
            Section("Preview only · no rating changes") {
                Button("Six-level guide") { scenario = "guide" }
                ForEach(NativeCardLevel.allCases) { level in
                    Button("\(level.roman) · \(level.name)") { scenario = level.rawValue }
                        .accessibilityIdentifier("journey.levels.preview.\(level.rawValue)")
                }
                Button("Explore Grid") { scenario = "grid" }
                Button("Merge review placement") { scenario = "merge" }
                Button("Rating unavailable") { scenario = "unknown" }
                Button("Chora growth sample") { scenario = "growth" }
            }
        } label: { Label("Preview scenarios", systemImage: "slider.horizontal.3") }
        .accessibilityIdentifier("journey.levels.preview")
    }

    private func comparisonList(isSheet: Bool) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One idea. Its own character.").font(.system(.title2, design: .serif))
                    Text("Six card editions, each with its own color and quiet Chora companion.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    previewBadge
                }.padding(.vertical, 4)
            }.listRowBackground(Color.clear)
            Section {
                ForEach(NativeCardLevel.allCases) { level in
                    Button {
                        scenario = level.rawValue
                        if isSheet { showsGuide = false }
                    } label: {
                        HStack(spacing: 14) {
                            NativeLevelSprite(level: level).frame(width: 72, height: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                NativeLevelLabel(level: level, dark: palette.dark)
                                Text("Sample rate \(level.range)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }.padding(.vertical, 1)
                    }.buttonStyle(.plain).accessibilityIdentifier("journey.levels.select.\(level.rawValue)")
                }
            } header: { Text("Choose a preview") } footer: {
                Text("These choices change this preview only. Card level belongs to the note; Chora growth is a separate system. No level is edited or upgraded here.")
            }
        }.scrollContentBackground(.hidden).background(palette.background)
    }

    private var singleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let note = sample(currentLevel) {
                levelCard(note: note, level: currentLevel, compact: false)
            }
            if currentLevel == nil {
                Text("Rating unavailable").font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("journey.levels.unavailable")
                Text("No rating is available for this sample. A neutral card keeps it readable without assigning Basic.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            aboutButton
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Room for different ideas.").font(.system(.title2, design: .serif))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 18) {
                ForEach(NativeCardLevel.allCases) { level in
                    if let note = sample(level) { levelCard(note: note, level: level, compact: true) }
                }
            }
            aboutButton
        }
    }

    private var merge: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A connection worth keeping.").font(.system(.title2, design: .serif))
            Text("Read-only review placement · existing sample note").font(.footnote).foregroundStyle(.secondary)
            if let note = sample(.exceptional) { levelCard(note: note, level: .exceptional, compact: false) }
            Text("The displayed level is a fixed example. This preview has not generated, accepted, or upgraded a Merge result.")
                .font(.footnote).foregroundStyle(.secondary)
            aboutButton
        }
    }

    private var aboutButton: some View {
        Button { showsGuide = true } label: {
            Label("About card levels", systemImage: "info.circle").frame(minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(palette.ink)
            .accessibilityIdentifier("journey.levels.about")
    }

    private func levelCard(note: SampleNote, level: NativeCardLevel?, compact: Bool) -> some View {
        let key = level?.rawValue ?? "unknown"
        return VStack(alignment: .leading, spacing: compact ? 12 : 20) {
            if let level {
                NativeLevelLabel(level: level, dark: palette.dark, compact: compact)
                    // The left-hugging IV silhouette extends below the border.
                    .padding(.top, level == .significant ? max(0, level.spriteHeight - level.lift - (compact ? 14 : 22)) + 8 : 0)
            }
            Button { reader = note } label: {
                Text(note.body).font(.system(compact ? .subheadline : .title3, design: .serif))
                    .lineSpacing(compact ? 3 : 6).lineLimit(compact ? 7 : 12)
                    .frame(maxWidth: .infinity, minHeight: compact ? 126 : 250, alignment: .topLeading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Read \(note.excerpt)")
                .accessibilityIdentifier("journey.levels.open.\(key)")
            Text(note.author).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: compact ? 0 : 12) {
                Button { toggleCollection(note) } label: {
                    Group {
                        if compact { Image(systemName: state.collected.contains(note.id) ? "bookmark.fill" : "bookmark") }
                        else { Label(state.collected.contains(note.id) ? "Collected" : "Collect", systemImage: state.collected.contains(note.id) ? "bookmark.fill" : "bookmark") }
                    }.font(.subheadline).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel(state.collected.contains(note.id) ? "Collected" : "Collect")
                    .accessibilityIdentifier("journey.levels.collect.\(key)")
                Spacer(minLength: 0)
                Button {
                    actionNote = note; showsActions = true
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Note actions").accessibilityIdentifier("journey.levels.actions.\(key)")
            }.buttonStyle(.plain)
        }
        .padding(compact ? 14 : 22)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(level?.color.opacity(palette.dark ? 0.65 : 0.55) ?? palette.rule, lineWidth: 1) }
        .overlay(alignment: .topLeading) {
            if let level {
                GeometryReader { proxy in
                    NativeLevelSprite(level: level)
                        .offset(x: level.spriteX(cardWidth: proxy.size.width), y: -level.lift)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .padding(.top, (level?.lift ?? 0) + 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journey.levels.card.\(key)")
    }

    private func toggleCollection(_ note: SampleNote) {
        if state.collected.contains(note.id) { state.collected.remove(note.id) }
        else { state.collected.insert(note.id) }
        actionMessage = state.collected.contains(note.id) ? "Collected in this sample session." : "Removed from this sample collection."
    }

    private func readerView(_ note: SampleNote) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(note.author).font(.subheadline).foregroundStyle(.secondary)
                    RichCardContent(note: note, palette: palette, full: true)
                    Button { toggleCollection(note) } label: {
                        Label(state.collected.contains(note.id) ? "Collected" : "Collect", systemImage: state.collected.contains(note.id) ? "bookmark.fill" : "bookmark")
                            .frame(minHeight: 44)
                    }.buttonStyle(.glass).accessibilityIdentifier("journey.levels.reader.collect")
                }.padding(24)
            }.background(palette.background).foregroundStyle(palette.ink)
                .navigationTitle("Read note").navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("journey.levels.reader")
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { reader = nil }.accessibilityIdentifier("journey.levels.reader.close")
                } }
        }
    }

    private var growth: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("A thread of your own.").font(.system(.largeTitle, design: .serif))
            VStack(alignment: .leading, spacing: 12) {
                Label("Stage 2 · Thread", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.title2.weight(.medium))
                    .accessibilityElement(children: .ignore).accessibilityLabel("Stage 2, Thread")
                    .accessibilityIdentifier("journey.levels.growth.stage")
                Text("Committed stage · read-only sample").font(.caption).foregroundStyle(.secondary)
                Text("Your Chora grows across six dimensions. A note’s card level does not set this stage.")
                    .font(.subheadline)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 20))
            VStack(spacing: 20) {
                growthMeter("Curiosity", key: "curiosity", value: 7, color: .orange)
                growthMeter("Insight", key: "insight", value: 5, color: .cyan)
                growthMeter("Creativity", key: "creativity", value: 6, color: .purple)
                growthMeter("Empathy", key: "empathy", value: 4, color: .pink)
                growthMeter("Judgment", key: "judgment", value: 5, color: .indigo)
                growthMeter("Resonance", key: "resonance", value: 3, color: .green)
            }.padding(22).background(palette.surface, in: RoundedRectangle(cornerRadius: 20))
            Text("Fixed sample values out of 12. No Merge activity, points, or growth are being simulated in the background.")
                .font(.footnote).foregroundStyle(.secondary)
            aboutButton
        }.accessibilityElement(children: .contain).accessibilityIdentifier("journey.levels.growth")
    }
    private func growthMeter(_ name: String, key: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(name); Spacer(); Text("\(Int(value)) / 12").monospacedDigit().foregroundStyle(.secondary) }
                .font(.subheadline)
            ProgressView(value: value, total: 12).tint(color)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(name), \(Int(value)) out of 12, sample")
            .accessibilityIdentifier("journey.levels.growth.\(key)")
    }
}
