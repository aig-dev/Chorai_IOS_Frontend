import CoreFlow
import SwiftUI

struct ContentReportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: ContentReportStore
    private let subject: String

    init(targetType: ContentReportTargetType, targetID: String) {
        switch targetType {
        case .asset:
            subject = "card"
        case .actor:
            subject = "profile"
        case .comment:
            subject = "comment"
        }
        _store = StateObject(
            wrappedValue: ContentReportStore(
                targetType: targetType,
                targetID: targetID,
                service: NetworkContentReportService()
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Report this \(subject)", systemImage: "flag")
                        .font(.body)
                        .padding(.vertical, 5)
                }
                .listRowBackground(ChoraiTheme.surface)

                content
            }
            .scrollContentBackground(.hidden)
            .background(ChoraiTheme.background)
            .foregroundStyle(ChoraiTheme.ink)
            .tint(ChoraiTheme.ink)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("content-report.close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .overlay(alignment: .topLeading) {
            Text("Report \(subject)")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("screen.content-report")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .submitted(let receipt):
            submitted(receipt)
        case .editing, .submitting, .failed:
            reportForm
        }
    }

    private var reportForm: some View {
        Group {
            Section {
                Picker("Reason", selection: reasonBinding) {
                    ForEach(ContentReportReason.allCases) { reason in
                        Text(reason.label).tag(reason)
                    }
                }
                .pickerStyle(.menu)
                .disabled(store.isSubmitting)
                .accessibilityIdentifier("content-report.reason")

                TextEditor(text: detailBinding)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, maxHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if store.detail.isEmpty {
                            Text("Optional context")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .disabled(store.isSubmitting)
                    .accessibilityLabel("Optional context")
                    .accessibilityIdentifier("content-report.detail")
            } header: {
                Text("Report details")
            }
            .listRowBackground(ChoraiTheme.surface)

            Section {
                Button {
                    if case .failed = store.phase {
                        store.retry()
                    } else {
                        store.submit()
                    }
                } label: {
                    HStack(spacing: 12) {
                        if store.isSubmitting {
                            ProgressView().tint(ChoraiTheme.ink)
                        } else {
                            Image(systemName: "flag")
                        }
                        Text(store.isSubmitting ? "Submitting…" : (store.phase.isFailed ? "Try Again" : "Submit"))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(store.isSubmitting)
                .accessibilityIdentifier(
                    store.phase.isFailed ? "content-report.retry" : "content-report.submit"
                )

                if case .failed(let error) = store.phase {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Report not submitted")
                            .font(.subheadline.weight(.semibold))
                        Text("Your reason and context are unchanged. Try again.")
                            .font(.footnote)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                        Text(error.code)
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("content-report.error-code")
                        Text("Report error")
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("content-report.error")
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                }
            }
            .listRowBackground(ChoraiTheme.surface)
        }
    }

    private func submitted(_ receipt: ContentReportReceipt) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Report submitted")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ChoraiTheme.ink)
                Text("We’ll review this \(subject). No other action is needed.")
                    .font(.footnote)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                    .multilineTextAlignment(.leading)
                Text("Case \(receipt.reportID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                Text(receipt.reportID)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("content-report.report-id")
                Text("Submitted")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("content-report.submitted")
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .contain)
        }
        .listRowBackground(ChoraiTheme.surface)
    }

    private var reasonBinding: Binding<ContentReportReason> {
        Binding(
            get: { store.reason },
            set: { store.selectReason($0) }
        )
    }

    private var detailBinding: Binding<String> {
        Binding(
            get: { store.detail },
            set: { store.updateDetail($0) }
        )
    }
}

private extension ContentReportPhase {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
