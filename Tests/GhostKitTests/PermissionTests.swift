import Testing
@testable import GhostKit

@Suite("Permission System Tests")
struct PermissionTests {

    // MARK: - Rule Parsing

    @Test("Parse simple action rule")
    func parseSimple() {
        let rule = PermissionRule.parse("Press", effect: .allow)
        #expect(rule?.action == "press")
        #expect(rule?.specifier == nil)
        #expect(rule?.effect == .allow)
    }

    @Test("Parse rule with specifier")
    func parseWithSpecifier() {
        let rule = PermissionRule.parse("Press(System Settings > content > *)", effect: .deny)
        #expect(rule?.action == "press")
        #expect(rule?.specifier == "System Settings > content > *")
        #expect(rule?.effect == .deny)
    }

    @Test("Parse rule with wildcard action")
    func parseKeyShortcut() {
        let rule = PermissionRule.parse("Key(* cmd+s)", effect: .allow)
        #expect(rule?.action == "key")
        #expect(rule?.specifier == "* cmd+s")
    }

    // MARK: - Rule Matching

    @Test("Simple action rule matches any app/target")
    func simpleMatch() {
        let rule = PermissionRule(action: "press", effect: .allow)
        #expect(rule.matches(action: "press", app: "Finder", target: "button > OK"))
        #expect(!rule.matches(action: "type", app: "Finder", target: "field"))
    }

    @Test("Specifier with exact app match")
    func specifierExactApp() {
        let rule = PermissionRule(action: "press", specifier: "System Settings > content > *", effect: .allow)
        #expect(rule.matches(action: "press", app: "System Settings", target: "content > toggle > Wi-Fi"))
        #expect(!rule.matches(action: "press", app: "Finder", target: "content > button"))
    }

    @Test("Specifier with wildcard app")
    func specifierWildcardApp() {
        let rule = PermissionRule(action: "press", specifier: "* > * > Save", effect: .allow)
        #expect(rule.matches(action: "press", app: "Keynote", target: "toolbar > Save"))
        #expect(rule.matches(action: "press", app: "TextEdit", target: "menu > Save"))
    }

    @Test("Specifier with name wildcard")
    func specifierNameWildcard() {
        let rule = PermissionRule(action: "press", specifier: "* > * > Erase *", effect: .deny)
        #expect(rule.matches(action: "press", app: "System Settings", target: "content > Erase All Content"))
        #expect(!rule.matches(action: "press", app: "System Settings", target: "content > Save"))
    }

    // MARK: - Permission Engine

    @Test("Open mode allows everything")
    func openMode() {
        let engine = PermissionEngine(rules: [], mode: .open)
        let decision = engine.evaluate(action: "press", app: "Finder", target: "button")
        if case .allowed = decision { } else {
            Issue.record("Expected allowed in open mode")
        }
    }

    @Test("Plan mode denies all interactions")
    func planMode() {
        let engine = PermissionEngine(rules: [], mode: .plan)
        let decision = engine.evaluate(action: "press", app: "Finder", target: "button")
        if case .denied = decision { } else {
            Issue.record("Expected denied in plan mode")
        }
    }

    @Test("Observe is always allowed")
    func observeAlwaysAllowed() {
        let engine = PermissionEngine(rules: [], mode: .allowlist)
        let decision = engine.evaluate(action: "observe", app: "Finder", target: "")
        if case .allowed = decision { } else {
            Issue.record("Expected observe to be allowed in any mode")
        }
    }

    @Test("Deny overrides allow")
    func denyOverridesAllow() {
        let rules = [
            PermissionRule(action: "press", effect: .allow),
            PermissionRule(action: "press", specifier: "* > * > Delete", effect: .deny),
        ]
        let engine = PermissionEngine(rules: rules, mode: .default)

        // Regular press is allowed
        let allowed = engine.evaluate(action: "press", app: "Finder", target: "button > OK")
        if case .allowed = allowed { } else {
            Issue.record("Expected press to be allowed")
        }

        // Delete press is denied
        let denied = engine.evaluate(action: "press", app: "Finder", target: "menu > Delete")
        if case .denied = denied { } else {
            Issue.record("Expected Delete press to be denied")
        }
    }

    @Test("Default mode prompts for unmatched actions")
    func defaultModePrompts() {
        let engine = PermissionEngine(rules: [], mode: .default)
        let decision = engine.evaluate(action: "press", app: "Finder", target: "button")
        if case .prompt = decision { } else {
            Issue.record("Expected prompt for unmatched action in default mode")
        }
    }

    @Test("Allowlist mode denies unmatched actions")
    func allowlistModeDenies() {
        let engine = PermissionEngine(rules: [], mode: .allowlist)
        let decision = engine.evaluate(action: "press", app: "Finder", target: "button")
        if case .denied = decision { } else {
            Issue.record("Expected denied for unmatched action in allowlist mode")
        }
    }

    @Test("Session rules work")
    func sessionRules() {
        let engine = PermissionEngine(rules: [], mode: .default)
        engine.addSessionRule(PermissionRule(action: "press", specifier: "Finder > *", effect: .allow, source: .session))

        let decision = engine.evaluate(action: "press", app: "Finder", target: "button > OK")
        if case .allowed = decision { } else {
            Issue.record("Expected session rule to allow press")
        }
    }

    // MARK: - Default Rules

    @Test("Default rules allow observe and navigate")
    func defaultRulesAllowRead() {
        let engine = PermissionEngine()
        let obs = engine.evaluate(action: "observe", app: "Finder", target: "")
        let nav = engine.evaluate(action: "navigate", app: "Finder", target: "Finder")
        if case .allowed = obs { } else { Issue.record("observe should be allowed") }
        if case .allowed = nav { } else { Issue.record("navigate should be allowed") }
    }

    @Test("Default rules deny dangerous patterns")
    func defaultRulesDenyDangerous() {
        let engine = PermissionEngine()
        let erase = engine.evaluate(action: "press", app: "System Settings", target: "content > Erase All Content")
        if case .denied = erase { } else { Issue.record("Erase should be denied") }
    }
}
