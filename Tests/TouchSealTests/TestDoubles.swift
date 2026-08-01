import Foundation
@testable import TouchSeal

/// Records every interaction so tests can assert on ordering, which is how the
/// "Touch ID is never skipped" guarantees are verified.
final class MockSecretStore: SecretStore {
    enum Call: Equatable {
        case set(String)
        case get(String)
        case delete(String)
        case exists(String)
    }

    private(set) var calls: [Call] = []
    private(set) var authenticationReasons: [String] = []
    var storage: [String: Data] = [:]

    var existsError: TouchSealError?
    var getError: TouchSealError?
    var deleteError: TouchSealError?
    /// Consumed one per `set` call; `nil` entries succeed. Exhausting the queue
    /// also succeeds.
    var setErrors: [TouchSealError?] = []

    init(storage: [String: Data] = [:]) {
        self.storage = storage
    }

    func set(name: String, value: Data) throws {
        calls.append(.set(name))
        if !setErrors.isEmpty, let error = setErrors.removeFirst() { throw error }
        guard storage[name] == nil else { throw TouchSealError.secretAlreadyExists(name: name) }
        storage[name] = value
    }

    func get(name: String, reason: String) throws -> Data {
        calls.append(.get(name))
        authenticationReasons.append(reason)
        if let getError { throw getError }
        guard let value = storage[name] else { throw TouchSealError.secretNotFound(name: name) }
        return value
    }

    func delete(name: String) throws {
        calls.append(.delete(name))
        if let deleteError { throw deleteError }
        guard storage.removeValue(forKey: name) != nil else {
            throw TouchSealError.secretNotFound(name: name)
        }
    }

    func exists(name: String) throws -> Bool {
        calls.append(.exists(name))
        if let existsError { throw existsError }
        return storage[name] != nil
    }
}

final class MockSecretInput: SecretInput {
    private(set) var prompts: [String] = []
    var entries: [Data]
    var error: TouchSealError?

    init(entries: [Data] = [], error: TouchSealError? = nil) {
        self.entries = entries
        self.error = error
    }

    convenience init(text: String...) {
        self.init(entries: text.map { Data($0.utf8) })
    }

    func readSecret(prompt: String) throws -> Data {
        prompts.append(prompt)
        if let error { throw error }
        guard !entries.isEmpty else { return Data() }
        return entries.removeFirst()
    }
}

final class MockConfirmation: ConfirmationPrompting {
    private(set) var questions: [String] = []
    var answers: [Bool]
    var error: TouchSealError?

    init(answers: [Bool] = [], error: TouchSealError? = nil) {
        self.answers = answers
        self.error = error
    }

    func confirm(_ question: String) throws -> Bool {
        questions.append(question)
        if let error { throw error }
        // Anything unscripted keeps the documented default: no.
        guard !answers.isEmpty else { return false }
        return answers.removeFirst()
    }
}

final class RecordingOutput: OutputWriter {
    private(set) var standardOutput = Data()
    private(set) var standardErrorLines: [String] = []

    var standardErrorText: String { standardErrorLines.joined(separator: "\n") }
    var standardOutputText: String { String(decoding: standardOutput, as: UTF8.self) }

    func writeStandardOutput(_ data: Data) throws {
        standardOutput.append(data)
    }

    func writeStandardError(_ text: String) {
        standardErrorLines.append(text)
    }
}

/// Builds a CLI wired to test doubles, and hands back the doubles for assertions.
struct TestHarness {
    let store: MockSecretStore
    let input: MockSecretInput
    let confirmation: MockConfirmation
    let output: RecordingOutput
    let cli: CLI

    init(
        storage: [String: Data] = [:],
        entries: [String] = [],
        answers: [Bool] = []
    ) {
        store = MockSecretStore(storage: storage)
        input = MockSecretInput(entries: entries.map { Data($0.utf8) })
        confirmation = MockConfirmation(answers: answers)
        output = RecordingOutput()
        cli = CLI(store: store, input: input, confirmation: confirmation, output: output)
    }

    func run(_ arguments: String...) -> ExitCode {
        cli.run(arguments: arguments)
    }
}
