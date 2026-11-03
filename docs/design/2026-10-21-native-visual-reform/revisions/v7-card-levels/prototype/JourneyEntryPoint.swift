import SwiftUI

struct JourneyEntryPoint: View {
    @State private var state = PrototypeState()
    @State private var request: JourneyRequest?
    @State private var workspace = false
    @State private var openedInitial = false
    @State private var appearance: String
    private let initialJourney: String?
    private let initialStep: String?
    private let opensWorkspace: Bool
    @Environment(\.colorScheme) private var scheme
    init() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? {
            guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        initialJourney = value("--journey")
        initialStep = value("--step")
        opensWorkspace = args.contains("--screen") && initialJourney == nil
        _appearance = State(initialValue: value("--appearance") ?? "system")
    }
    var body: some View {
        Group {
            if opensWorkspace { PrototypeRoot(state: $state) }
            else { lab }
        }
        .environment(\.prototypeTheme, .forestGold)
        .tint(PrototypeTheme.forestGold.dynamicTint)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }
    private var lab: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Follow an idea.").font(.system(size: 30, design: .serif))
                        Text("Explore the complete journey, one native interaction at a time.").font(.subheadline).foregroundStyle(.secondary)
                        Label("Offline sample · nothing sent", systemImage: "lock").font(.caption)
                    }.padding(.vertical, 10)
                }.listRowBackground(Color.clear)
                Section("Try a journey") {
                    Button { request = JourneyRequest(kind: "spark", step: "results") } label: {
                        Label { VStack(alignment: .leading, spacing: 5) { Text("Spark"); Text("Find, read, collect, go deeper").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "sparkles") }
                    }.accessibilityIdentifier("journey.lab.spark")
                    Button { request = JourneyRequest(kind: "merge", step: "selection") } label: {
                        Label { VStack(alignment: .leading, spacing: 5) { Text("Merge"); Text("Choose, combine, edit, accept").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "arrow.triangle.merge") }
                    }.accessibilityIdentifier("journey.lab.merge")
                    Button { request = JourneyRequest(kind: "levels", step: "guide") } label: {
                        Label { VStack(alignment: .leading, spacing: 5) { Text("Card levels & Chora"); Text("Six editions, quiet companions, separate growth").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "square.stack.3d.up") }
                    }.accessibilityIdentifier("journey.lab.levels")
                    Button { workspace = true } label: { Label("Explore, Home & writing", systemImage: "square.stack") }
                        .accessibilityIdentifier("journey.lab.workspace")
                }
                Section("This sample session") {
                    LabeledContent("Your notes", value: "\(state.notes.filter(\.isOwned).count)")
                        .accessibilityIdentifier("journey.lab.notes")
                    LabeledContent("Collected", value: "\(state.collected.count)")
                        .accessibilityIdentifier("journey.lab.collected")
                    Text("Open Home to see notes you explicitly accepted. Relaunching resets this sample.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette(dark: scheme == .dark, theme: .forestGold).background)
            .navigationTitle("Feature journeys")
            .sheet(item: $request) { item in
                if item.kind == "spark" {
                    SparkJourney(state: $state, source: state.notes.first { !$0.isOwned }!, initialStep: item.step)
                } else if item.kind == "levels" {
                    CardLevelJourney(state: $state, initialStep: item.step)
                } else {
                    MergeJourney(state: $state, source: state.notes.first { $0.isOwned && $0.sampleKey != "merge-result" }!, initialStep: item.step)
                }
            }
            .sheet(isPresented: $workspace) {
                PrototypeRoot(state: $state).presentationDragIndicator(.visible)
            }
            .task {
                guard !openedInitial else { return }; openedInitial = true
                if let initialJourney, ["spark", "merge", "levels"].contains(initialJourney) {
                    request = JourneyRequest(kind: initialJourney, step: initialStep ?? (initialJourney == "spark" ? "results" : initialJourney == "levels" ? "guide" : "selection"))
                }
            }
        }
    }
}

private struct JourneyRequest: Identifiable {
    let id = UUID()
    let kind: String
    let step: String
}

struct JourneyActionSheet: View {
    let request: NoteActionRequest
    @Binding var state: PrototypeState
    let palette: Palette
    var body: some View {
        switch request.action {
        case "Spark": SparkJourney(state: $state, source: request.note)
        case "Merge": MergeJourney(state: $state, source: request.note)
        default: NoteActionSheet(request: request, notes: state.notes, palette: palette, collectedIDs: state.collected)
        }
    }
}
