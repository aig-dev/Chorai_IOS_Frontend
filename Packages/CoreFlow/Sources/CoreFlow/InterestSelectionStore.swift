import Combine
import Foundation

@MainActor
public final class InterestSelectionStore: ObservableObject {
    public static let maximumSelectionCount = 9

    @Published public private(set) var options: [InterestSelectionOption] = []
    @Published public private(set) var phase: InterestSelectionPhase = .idle

    public var selectedDomains: [String] {
        options.filter(\.isSelected).map(\.value)
    }

    public var canSave: Bool {
        !isSaving
            && (1...Self.maximumSelectionCount).contains(selectedDomains.count)
    }

    public var isSaving: Bool {
        phase == .saving
    }

    private let service: any CoreInterestSelectionServing
    private var operationTask: Task<Void, Never>?
    private var requestID = UUID()
    private var actorID: String?

    public init(service: any CoreInterestSelectionServing) {
        self.service = service
    }

    public func load(actorID: String) {
        operationTask?.cancel()
        let currentRequest = UUID()
        requestID = currentRequest

        let normalizedActor = actorID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedActor.isEmpty else {
            self.actorID = nil
            options = []
            phase = .failed(.load, .invalidActor)
            return
        }

        self.actorID = normalizedActor
        options = []
        phase = .loading
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let optionValues = service.fetchOptions()
                async let selectedValues = service.fetchSelection()
                let loaded = try await (optionValues, selectedValues)
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      self.actorID == normalizedActor else {
                    return
                }
                options = Self.merge(
                    options: loaded.0,
                    selected: loaded.1
                )
                phase = .ready
            } catch {
                guard !Task.isCancelled, requestID == currentRequest else {
                    return
                }
                phase = .failed(.load, Self.map(error))
            }
        }
    }

    public func toggle(_ value: String) {
        guard !isSaving,
              let index = options.firstIndex(where: {
                  $0.value.caseInsensitiveCompare(value) == .orderedSame
              }) else {
            return
        }

        let item = options[index]
        guard item.isSelected
                || selectedDomains.count < Self.maximumSelectionCount else {
            return
        }
        options[index] = InterestSelectionOption(
            value: item.value,
            isSelected: !item.isSelected
        )
    }

    public func reset() {
        guard !isSaving else { return }
        options = options.map {
            InterestSelectionOption(value: $0.value, isSelected: false)
        }
    }

    public func skip() {
        guard !isSaving else { return }
        operationTask?.cancel()
        requestID = UUID()
        phase = .skipped
    }

    public func save() {
        guard canSave else { return }
        operationTask?.cancel()
        let values = selectedDomains
        let currentRequest = UUID()
        requestID = currentRequest
        phase = .saving
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await service.save(domains: values)
                guard !Task.isCancelled, requestID == currentRequest else {
                    return
                }
                options = Self.merge(
                    options: options.map(\.value),
                    selected: saved
                )
                phase = .saved
            } catch {
                guard !Task.isCancelled, requestID == currentRequest else {
                    return
                }
                phase = .failed(.save, Self.map(error))
            }
        }
    }

    private static func merge(
        options: [String],
        selected: [String]
    ) -> [InterestSelectionOption] {
        let normalizedSelected = Set(
            normalize(selected)
                .prefix(maximumSelectionCount)
                .map { $0.lowercased() }
        )
        return normalize(options).map {
            InterestSelectionOption(
                value: $0,
                isSelected: normalizedSelected.contains($0.lowercased())
            )
        }
    }

    private static func normalize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = value.lowercased()
            guard !value.isEmpty, seen.insert(key).inserted else {
                return nil
            }
            return value
        }
    }

    private static func map(_ error: Error) -> InterestSelectionError {
        (error as? InterestSelectionError)
            ?? .transport(code: "interest_request_failed")
    }
}
