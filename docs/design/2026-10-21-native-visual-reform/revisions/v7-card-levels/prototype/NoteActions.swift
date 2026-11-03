import SwiftUI

/// Routes review actions without importing or contacting the production services.
struct NoteActionRequest: Identifiable {
    let id = UUID()
    let note: SampleNote
    let action: String
}

struct NoteActionSheet: View {
    let request: NoteActionRequest
    let notes: [SampleNote]
    let palette: Palette
    var collectedIDs: Set<UUID> = []

    @Environment(\.dismiss) private var dismiss
    @State private var reportReason = SampleReportReason.spam
    @State private var reportDetail = ""
    @State private var reportDraftSaved = false
    @State private var selectedLinkID: UUID?
    @State private var linkPreviewCreated = false

    private var secondaryInk: Color {
        palette.ink.opacity(palette.dark ? 0.72 : 0.90)
    }

    private var linkCandidates: [SampleNote] {
        notes.filter { note in
            note.id != request.note.id
                && (note.isOwned || (request.note.isOwned && collectedIDs.contains(note.id)))
        }
    }

    private var selectedLinkNote: SampleNote? {
        linkCandidates.first { $0.id == selectedLinkID }
    }

    private var sampleShareText: String {
        [
            "Chorai · Local design sample",
            request.note.body,
            request.note.richContent?.searchableText ?? "",
            "Sample author: \(request.note.author)",
            "Illustrative content from an offline prototype. This is not a published note."
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(request.note.author)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(secondaryInk)
                        Text(request.note.excerpt)
                            .font(.system(.body, design: .serif))
                            .lineLimit(4)
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(palette.surface)

                switch request.action {
                case "Report": reportContent
                case "Link": linkContent
                case "Share": shareContent
                case "Spark": sparkContent
                default: unavailableContent
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .foregroundStyle(palette.ink)
            .tint(palette.ink)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(request.action)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("prototype.note-action.close")
                }
            }
        }
        .presentationDetents(request.action == "Spark" ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("prototype.note-action.sheet")
    }

    @ViewBuilder private var reportContent: some View {
        if request.note.isOwned {
            Section {
                Label("Reports apply to other authors’ content.", systemImage: "person.crop.circle")
                    .foregroundStyle(secondaryInk)
            }
            .listRowBackground(palette.surface)
        } else {
            Section {
                Picker("Reason", selection: $reportReason) {
                    ForEach(SampleReportReason.allCases) { reason in
                        Text(reason.rawValue).tag(reason)
                    }
                }
                .accessibilityIdentifier("prototype.report.reason")
                .onChange(of: reportReason) { _, _ in reportDraftSaved = false }
                TextField("Optional context", text: $reportDetail, axis: .vertical)
                    .lineLimit(4...7)
                    .accessibilityLabel("Optional report context")
                    .accessibilityIdentifier("prototype.report.detail")
                    .onChange(of: reportDetail) { _, _ in reportDraftSaved = false }
            } header: {
                Text("Report draft")
            } footer: {
                Text("Local sample. No report will be sent or reviewed. Closing this sheet clears the draft.")
                    .foregroundStyle(secondaryInk)
            }
            .listRowBackground(palette.surface)

            Section {
                Button {
                    reportDraftSaved = true
                } label: {
                    Label("Preview report", systemImage: "eye")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("prototype.report.save-draft")
                if reportDraftSaved {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Draft preview · not submitted", systemImage: "eye")
                            .font(.subheadline.weight(.medium))
                        Text("Nothing was submitted. You can still edit your reason and context.")
                            .font(.footnote)
                            .foregroundStyle(secondaryInk)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("prototype.report.saved")
                }
            }
            .listRowBackground(palette.surface)
        }
    }

    private var linkContent: some View {
        Group {
            Section {
                if linkCandidates.isEmpty {
                    ContentUnavailableView("No notes to link", systemImage: "link", description: Text("Create a note in Home first."))
                } else {
                    ForEach(linkCandidates) { note in
                        Button {
                            selectedLinkID = note.id
                            linkPreviewCreated = false
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(note.excerpt)
                                        .font(.body)
                                        .foregroundStyle(palette.ink)
                                        .lineLimit(3)
                                    Text(note.isOwned ? "Your note" : "Collected · \(note.author)")
                                        .font(.caption)
                                        .foregroundStyle(secondaryInk)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: selectedLinkID == note.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedLinkID == note.id ? palette.accent : secondaryInk)
                                    .font(.title3)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(note.excerpt)
                        .accessibilityValue(selectedLinkID == note.id ? "Selected" : "Not selected")
                        .accessibilityIdentifier("prototype.link.choice")
                    }
                }
            } header: {
                Text(request.note.isOwned ? "Your notes and collections" : "Choose one of your notes")
            } footer: {
                Text(request.note.isOwned
                    ? "Link this note to one of your notes or a collected note."
                    : "The connection belongs to your selected note; the other author’s note stays unchanged.")
                    .foregroundStyle(secondaryInk)
            }
            .listRowBackground(palette.surface)

            Section {
                Button {
                    guard selectedLinkNote != nil else { return }
                    linkPreviewCreated = true
                } label: {
                    Label("Preview connection", systemImage: "link")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(selectedLinkNote == nil)
                .accessibilityIdentifier("prototype.link.create")

                if linkPreviewCreated, let selected = selectedLinkNote {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Connection preview", systemImage: "link")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.accent)
                        Text(request.note.isOwned ? request.note.excerpt : selected.excerpt)
                            .font(.system(.body, design: .serif))
                        Label("connects to", systemImage: "arrow.down")
                            .font(.caption)
                            .foregroundStyle(secondaryInk)
                        Text(request.note.isOwned ? selected.excerpt : request.note.excerpt)
                            .font(.system(.body, design: .serif))
                        Text("Only visible in this sheet. No note or relationship has been saved.")
                            .font(.footnote)
                            .foregroundStyle(secondaryInk)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("prototype.link.preview")
                }
            } footer: {
                Text("Local sample · this preview clears when you close it.")
                    .foregroundStyle(secondaryInk)
            }
            .listRowBackground(palette.surface)
        }
    }

    private var shareContent: some View {
        Group {
            Section {
                Text("Share the sample text using the iOS share sheet.")
                    .font(.body)
                Text("This sends only the fictional content shown here. It does not publish a note or change its privacy.")
                    .font(.footnote)
                    .foregroundStyle(secondaryInk)
                ShareLink(item: sampleShareText, subject: Text("Chorai design sample")) {
                    Label("Share sample text", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("prototype.share.open")
            } footer: {
                Text("Local design preview · sample text only.")
                    .foregroundStyle(secondaryInk)
            }
            .listRowBackground(palette.surface)

            Section("Text to share") {
                Text(sampleShareText)
                    .font(.footnote)
                    .foregroundStyle(secondaryInk)
                    .textSelection(.enabled)
            }
            .listRowBackground(palette.surface)
        }
    }

    private var sparkContent: some View {
        Section {
            Label("Follow the next idea", systemImage: "sparkles")
                .font(.title3.weight(.medium))
                .foregroundStyle(palette.accent)
                .padding(.vertical, 6)
            Text("Spark’s full journey is the next design step: related ideas, your response, and a clear path back to this note.")
                .font(.body)
            Text("This preview preserves the entry. It has no connected AI service and does not generate results.")
                .font(.footnote)
                .foregroundStyle(secondaryInk)
        } footer: {
            Text("Local sample · no generation started.")
                .foregroundStyle(secondaryInk)
        }
        .listRowBackground(palette.surface)
        .accessibilityIdentifier("prototype.spark.placeholder")
    }

    private var unavailableContent: some View {
        Section {
            Text("This action is not part of the local sample yet.")
                .foregroundStyle(secondaryInk)
        }
        .listRowBackground(palette.surface)
    }
}

/// Matches production ContentReportReason labels without importing its network layer.
private enum SampleReportReason: String, CaseIterable, Identifiable {
    case spam = "Spam"
    case harassment = "Harassment"
    case misinformation = "Misinformation"
    case copyright = "Copyright"
    case other = "Other"
    var id: String { rawValue }
}
