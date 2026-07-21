import CoreFlow
import SwiftUI

struct ContentReportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: ContentReportStore
    private let subject: String

    init(targetType: ContentReportTargetType, targetID: String) {
        subject = targetType == .actor ? "profile" : "card"
        _store = StateObject(
            wrappedValue: ContentReportStore(
                targetType: targetType,
                targetID: targetID,
                service: NetworkContentReportService()
            )
        )
    }

    var body: some View {
        ZStack {
            Image("home_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, minHeight: 360)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .adaptiveContentGutter()
            .padding(.top, 72)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .topLeading) {
            Text("Report \(subject)")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("screen.content-report")
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("content-report.close")

            Spacer()

            Text("Report")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 8)
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reason")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))

                Picker("Reason", selection: reasonBinding) {
                    ForEach(ContentReportReason.allCases) { reason in
                        Text(reason.label).tag(reason)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                )
                .disabled(store.isSubmitting)
                .accessibilityIdentifier("content-report.reason")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Optional context")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))

                TextEditor(text: detailBinding)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .frame(minHeight: 120, maxHeight: 180)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.08))
                    )
                    .disabled(store.isSubmitting)
                    .accessibilityIdentifier("content-report.detail")
            }

            if case .failed(let error) = store.phase {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Report not submitted")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Your reason and context are unchanged. Try again.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
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
                .accessibilityElement(children: .contain)
            }

            Spacer(minLength: 0)

            Button {
                if case .failed = store.phase {
                    store.retry()
                } else {
                    store.submit()
                }
            } label: {
                Group {
                    if store.isSubmitting {
                        ProgressView().tint(.white)
                    } else if case .failed = store.phase {
                        Text("Try Again")
                    } else {
                        Text("Submit")
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(store.isSubmitting)
            .accessibilityIdentifier(
                store.phase.isFailed
                    ? "content-report.retry"
                    : "content-report.submit"
            )
        }
        .padding(.top, 18)
    }

    private func submitted(_ receipt: ContentReportReceipt) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Report submitted")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("We’ll review this \(subject). No other action is needed.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
            Text("Case \(receipt.reportID)")
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.48))
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
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var reasonBinding: Binding<ContentReportReason> {
        Binding(
            get: { store.reason },
            set: store.selectReason
        )
    }

    private var detailBinding: Binding<String> {
        Binding(
            get: { store.detail },
            set: store.updateDetail
        )
    }
}

private extension ContentReportPhase {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
