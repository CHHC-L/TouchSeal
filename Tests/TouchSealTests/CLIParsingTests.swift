import Testing
@testable import TouchSeal

@Suite("CLI parsing")
struct CLIParsingTests {
    // MARK: No arguments

    @Test("no arguments is an argument error")
    func noArguments() {
        expectParseFailure([], exitCode: .invalidArguments)
    }

    // MARK: help and version

    @Test("help spellings", arguments: ["help", "--help", "-h"])
    func helpSpellings(_ spelling: String) throws {
        #expect(try CLI.parse([spelling]) == .help)
    }

    @Test("version spellings", arguments: ["version", "--version", "-V"])
    func versionSpellings(_ spelling: String) throws {
        #expect(try CLI.parse([spelling]) == .version)
    }

    @Test("help text leaks no internals")
    func helpHidesInternals() {
        let usage = CLI.usage
        for forbidden in ["kSec", "SecItem", "LAContext", "sk-ant"] {
            #expect(!usage.contains(forbidden), "help must not mention \(forbidden)")
        }
        // v0.1 has no `list` command: secret names are metadata worth withholding.
        #expect(!usage.contains("list "))
    }

    // MARK: Commands

    @Test("set, get, and exists parse to their commands")
    func simpleCommands() throws {
        #expect(try CLI.parse(["set", "api-key"]) == .set(name: "api-key"))
        #expect(try CLI.parse(["get", "api-key"]) == .get(name: "api-key"))
        #expect(try CLI.parse(["exists", "api-key"]) == .exists(name: "api-key"))
    }

    @Test("delete requires confirmation by default")
    func deleteDefaults() throws {
        #expect(try CLI.parse(["delete", "api-key"]) == .delete(name: "api-key", skipConfirmation: false))
    }

    @Test("delete accepts --yes and -y", arguments: ["--yes", "-y"])
    func deleteYesFlag(_ spelling: String) throws {
        #expect(try CLI.parse(["delete", "api-key", spelling]) == .delete(name: "api-key", skipConfirmation: true))
    }

    @Test("--yes is rejected on commands other than delete", arguments: ["set", "get", "exists"])
    func yesFlagIsDeleteOnly(_ command: String) {
        expectParseFailure([command, "api-key", "--yes"], exitCode: .invalidArguments)
    }

    // MARK: Errors

    @Test("unknown command")
    func unknownCommand() {
        expectParseFailure(["frobnicate"], exitCode: .invalidArguments)
    }

    @Test("unknown option")
    func unknownOption() {
        expectParseFailure(["--frobnicate"], exitCode: .invalidArguments)
        expectParseFailure(["delete", "api-key", "--force"], exitCode: .invalidArguments)
    }

    @Test("--force exists nowhere", arguments: ["set", "get", "delete", "exists"])
    func forceIsNeverAccepted(_ command: String) {
        expectParseFailure([command, "api-key", "--force"], exitCode: .invalidArguments)
    }

    @Test("missing name", arguments: ["set", "get", "delete", "exists"])
    func missingName(_ command: String) {
        expectParseFailure([command], exitCode: .invalidArguments)
    }

    @Test("too many names", arguments: ["set", "get", "delete", "exists"])
    func tooManyNames(_ command: String) {
        expectParseFailure([command, "a", "b"], exitCode: .invalidArguments)
    }

    @Test("invalid names are rejected while parsing", arguments: ["", " leading", "trailing ", "two\nlines", "nul\0byte"])
    func invalidNames(_ name: String) {
        expectParseFailure(["get", name], exitCode: .invalidArguments)
    }

    // MARK: Operand separator

    @Test("-- allows names that start with a dash")
    func doubleDashSeparator() throws {
        #expect(try CLI.parse(["get", "--", "-weird-name"]) == .get(name: "-weird-name"))
        #expect(
            try CLI.parse(["delete", "--yes", "--", "-weird-name"])
                == .delete(name: "-weird-name", skipConfirmation: true)
        )
    }

    @Test("a lone dash is an operand, not an option")
    func loneDashIsAName() throws {
        #expect(try CLI.parse(["get", "-"]) == .get(name: "-"))
    }

    // MARK: Helpers

    private func expectParseFailure(
        _ arguments: [String],
        exitCode expected: ExitCode,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let error = #expect(throws: TouchSealError.self, sourceLocation: sourceLocation) {
            try CLI.parse(arguments)
        }
        #expect(error?.exitCode == expected, sourceLocation: sourceLocation)
    }
}
