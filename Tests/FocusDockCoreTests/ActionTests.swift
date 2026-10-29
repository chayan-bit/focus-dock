import Testing
@testable import FocusDockCore

struct ActionTests {
    // MARK: Parsing

    @Test func parsesAnIdAndWhitespaceSeparatedArguments() throws {
        let parsed = try ActionInvocation.parse("  mode.set \t focus  ")
        #expect(parsed == ActionInvocation(id: "mode.set", arguments: ["focus"]))
    }

    @Test func parsesAnIdWithNoArguments() throws {
        #expect(try ActionInvocation.parse("app.quit") == ActionInvocation(id: "app.quit", arguments: []))
    }

    @Test func quotedArgumentsKeepSpacesAndEmptyStrings() throws {
        let parsed = try ActionInvocation.parse(#"theme.set "tokyo night" """#)
        #expect(parsed.arguments == ["tokyo night", ""])
    }

    @Test func backslashEscapesQuotesBackslashesAndSpaces() throws {
        let parsed = try ActionInvocation.parse(#"x "say \"hi\"" a\ b c\\d"#)
        #expect(parsed.arguments == [#"say "hi""#, "a b", #"c\d"#])
    }

    @Test func quoteInsideAWordJoinsIt() throws {
        #expect(try ActionInvocation.parse(#"x pre"fix ed"post"#).arguments == ["prefix edpost"])
    }

    @Test(arguments: ["", "   ", "\t\n"])
    func emptyInputIsAProblem(_ text: String) {
        #expect(throws: ConfigProblem.self) { try ActionInvocation.parse(text) }
    }

    @Test(arguments: [#"x "open"#, #"x trailing\"#])
    func unterminatedQuoteOrEscapeIsAProblem(_ text: String) {
        #expect(throws: ConfigProblem.self) { try ActionInvocation.parse(text) }
    }

    // MARK: Catalog

    @Test func catalogIdsAreUnique() {
        let ids = ActionCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyNonReadActionMutates() {
        let readVerbs: Set<String> = ["list", "current", "get"]
        for action in ActionCatalog.all where !readVerbs.contains(String(action.id.split(separator: ".").last ?? "")) {
            #expect(action.mutates, "\(action.id) must declare mutates")
        }
    }

    @Test func everyNamedCapabilityExistsInTheCapabilityCatalog() {
        let known = Set(CapabilityRegistry.catalog.map(\.id))
        for action in ActionCatalog.all {
            if let capability = action.capability { #expect(known.contains(capability), "\(action.id) names \(capability)") }
        }
    }

    @Test func validInvocationsHaveNoProblems() {
        #expect(ActionCatalog.problems(ActionInvocation(id: "mode.set", arguments: ["focus"])).isEmpty)
        #expect(ActionCatalog.problems(ActionInvocation(id: "app.quit", arguments: [])).isEmpty)
    }

    @Test func unknownIdIsAProblem() {
        #expect(ActionCatalog.problems(ActionInvocation(id: "nope", arguments: [])) == [#"unknown action "nope""#])
    }

    @Test func wrongArgumentCountsNameTheExpectedArguments() {
        #expect(ActionCatalog.problems(ActionInvocation(id: "mode.set", arguments: [])) == ["mode.set takes 1 argument (mode), got 0"])
        #expect(ActionCatalog.problems(ActionInvocation(id: "app.quit", arguments: ["now"])) == ["app.quit takes no arguments, got 1"])
    }

    // MARK: Validation against capabilities

    private static let gated = [ActionDescriptor(id: "x.go", summary: "", arguments: [], mutates: true, capability: "overview")]

    @Test func validateFailsWhenTheCapabilityNeedsAPermission() {
        let registry = CapabilityRegistry(resolved: [], granted: [])
        let result = ActionCatalog.validate(ActionInvocation(id: "x.go", arguments: []), capabilities: registry, in: Self.gated)
        #expect(result == .failure(.unavailable("overview", .needsPermission([.screenRecording]))))
    }

    @Test func validatePassesWhenTheCapabilityIsAvailable() {
        let registry = CapabilityRegistry(resolved: [], granted: [.screenRecording])
        let result = ActionCatalog.validate(ActionInvocation(id: "x.go", arguments: []), capabilities: registry, in: Self.gated)
        #expect(result.map(\.id) == .success("x.go"))
    }

    @Test func validateReportsArgumentProblemsBeforeCapabilities() {
        let registry = CapabilityRegistry(resolved: [], granted: [])
        let result = ActionCatalog.validate(ActionInvocation(id: "x.go", arguments: ["1"]), capabilities: registry, in: Self.gated)
        #expect(result == .failure(.invalid(["x.go takes no arguments, got 1"])))
    }

    @Test func actionWithoutACapabilityNeedsNoRegistryEntry() {
        let registry = CapabilityRegistry(resolved: [], granted: [])
        let result = ActionCatalog.validate(ActionInvocation(id: "app.quit", arguments: []), capabilities: registry)
        #expect(result.map(\.id) == .success("app.quit"))
    }
}
