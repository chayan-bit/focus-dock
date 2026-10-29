import Foundation
import SwiftUI
import Testing
@testable import FocusDockCore

private func resolver(
    speed: Double = 1, reduce: ReduceMotion = .system, system: Bool = false,
    defaults: [String: MotionSpec] = [:], elements: [MotionKey: MotionSpec] = [:]
) -> MotionResolver {
    MotionResolver(
        config: MotionConfig(speed: speed, reduceMotion: reduce, defaults: defaults, elements: elements),
        systemReduceMotion: system
    )
}

struct MotionResolverTests {
    @Test func hasTheTwentyThreeKeysOfSpec6() {
        #expect(MotionKey.allCases.count == 23)
        #expect(MotionKey(rawValue: "dock.reveal") == .dockReveal)
        #expect(MotionKey(rawValue: "agent.panel") == .agentPanel)
    }

    @Test func defaultsEqualTheSpikeFits() {
        let r = resolver()
        #expect(r.spec(.borderFollow) == .spring(response: 0.52, damping: 0.91))
        #expect(r.spec(.overviewClose) == .spring(response: 0.28, damping: 0.99))
        #expect(r.spec(.overviewOpen) == .timed(duration: 0.27, curve: .easeOut))
        #expect(r.spec(.dockMagnify) == .spring(response: 0.12, damping: 0.75))
        #expect(r.spec(.workspaceSwitch) == .dockSwipe(velocity: 1))
        #expect(r.spec(.workspaceJump) == .dockSwipe(velocity: 9999))
        #expect(r.spec(.dockBounce) == .timed(duration: 0.70, curve: .dockBounce))
        #expect(r.spec(.cardEnter) == .spring(response: 0.35, damping: 0.86))
    }

    @Test func pillAndCountdownKeepTodaysSnappy() {
        let snappy = Spring.snappy
        for key in [MotionKey.pillExpand, .countdownTick] {
            guard case .spring(let response, let damping) = resolver().spec(key) else {
                Issue.record("\(key) is not a spring")
                continue
            }
            let spring = Spring(response: response, dampingRatio: damping)
            #expect(abs(spring.response - snappy.response) < 1e-9)
            #expect(abs(spring.dampingRatio - snappy.dampingRatio) < 1e-9)
        }
    }

    @Test func bouncePhasesAddUpToTheDefaultDuration() {
        let period = DockMetrics.bounceRiseSeconds + DockMetrics.bounceHoldSeconds + DockMetrics.bounceFallSeconds
        #expect(abs(period - 0.70) < 1e-9)
    }

    @Test func fittedSpaceSlideSpringMapsToTheMeasuredStiffnessAndDamping() {
        let spring = Spring(response: 0.516, dampingRatio: 0.916)
        #expect(abs(spring.stiffness - 148.5) < 0.5)
        #expect(abs(spring.damping - 22.3) < 0.2)
    }

    @Test func elementOverrideBeatsBuiltInBeatsDefaultsSpring() {
        let custom = MotionSpec.spring(response: 0.4, damping: 0.75)
        let r = resolver(defaults: ["spring": .spring(response: 0.6, damping: 0.5)], elements: [.cardEnter: custom, .dockMagnify: custom])
        #expect(r.spec(.cardEnter) == custom)
        #expect(r.spec(.dockMagnify) == custom)
        #expect(r.spec(.cardExit) == .spring(response: 0.6, damping: 0.5))
        #expect(r.spec(.overviewClose) == .spring(response: 0.28, damping: 0.99))
    }

    @Test func spaceSlideDefaultIsConfigurable() {
        let r = resolver(defaults: ["spaceSlide": .spring(response: 0.7, damping: 0.8)])
        #expect(r.spec(.borderFollow) == .spring(response: 0.7, damping: 0.8))
    }

    @Test func speedZeroIsInstantEverywhere() {
        let r = resolver(speed: 0)
        #expect(MotionKey.allCases.allSatisfy { r.spec($0) == .instant })
    }

    @Test func speedDividesDurationsAndSpringResponses() {
        let r = resolver(speed: 2, elements: [.windowMove: .proxy(duration: 0.22, curve: .easeInOutCos), .barReveal: .crossFade(duration: 0.2)])
        #expect(r.spec(.cardEnter) == .spring(response: 0.175, damping: 0.86))
        #expect(r.spec(.overviewOpen) == .timed(duration: 0.135, curve: .easeOut))
        #expect(r.spec(.dockBounce) == .timed(duration: 0.35, curve: .dockBounce))
        #expect(r.spec(.windowMove) == .proxy(duration: 0.11, curve: .easeInOutCos))
        #expect(r.spec(.barReveal) == .crossFade(duration: 0.1))
        #expect(r.spec(.workspaceSwitch) == .dockSwipe(velocity: 1))
    }

    @Test func speedBelowOneSlowsDown() {
        #expect(resolver(speed: 0.5).spec(.cardEnter) == .spring(response: 0.7, damping: 0.86))
    }

    @Test(arguments: [(ReduceMotion.system, false, false), (.system, true, true), (.always, false, true),
                      (.always, true, true), (.never, false, false), (.never, true, false)])
    func reduceMotionSettingCrossedWithTheSystemFlag(setting: ReduceMotion, system: Bool, reduced: Bool) {
        let r = resolver(reduce: setting, system: system)
        #expect(r.isReduced == reduced)
        #expect(r.spec(.cardEnter) == (reduced ? .crossFade(duration: 0.35) : .spring(response: 0.35, damping: 0.86)))
    }

    @Test func reducedMotionKeepsDockSwipeAndInstantAndKeepsDurations() {
        let r = resolver(system: true, elements: [.windowMove: .proxy(duration: 0.22, curve: .linear), .barReveal: .instant])
        #expect(r.spec(.workspaceSwitch) == .dockSwipe(velocity: 1))
        #expect(r.spec(.workspaceJump) == .dockSwipe(velocity: 9999))
        #expect(r.spec(.barReveal) == .instant)
        #expect(r.spec(.windowMove) == .crossFade(duration: 0.22))
        #expect(r.spec(.dockBounce) == .crossFade(duration: 0.70))
        #expect(r.spec(.overviewOpen) == .crossFade(duration: 0.27))
    }

    @Test func speedAppliesBeforeReduceMotion() {
        #expect(resolver(speed: 2, system: true).spec(.cardEnter) == .crossFade(duration: 0.175))
        #expect(resolver(speed: 0, system: true).spec(.cardEnter) == .instant)
    }

    @Test func nonsensicalSpeedFallsBackSafely() {
        #expect(resolver(speed: -1).spec(.cardEnter) == .instant)
        #expect(resolver(speed: .nan).spec(.cardEnter) == .spring(response: 0.35, damping: 0.86))
    }

    @Test func curveControlPoints() {
        #expect(MotionCurve.easeOut.controlPoints! == (0, 0, 0.58, 1))
        #expect(MotionCurve.bezier(0.1, 0.2, 0.3, 0.4).controlPoints! == (0.1, 0.2, 0.3, 0.4))
        #expect(MotionCurve.dockBounce.controlPoints == nil)
    }
}

struct MotionCodingTests {
    private func decode(_ json: String) throws -> MotionConfig {
        try JSONDecoder().decode(MotionConfig.self, from: Data(json.utf8))
    }

    @Test func decodesTheSpec7MotionExample() throws {
        let config = try decode("""
        { "speed": 1.0, "reduceMotion": "system",
          "defaults": { "spring": { "response": 0.35, "damping": 0.86 },
                        "spaceSlide": { "response": 0.52, "damping": 0.91 } },
          "elements": {
            "workspace.switch": { "via": "dockSwipe", "velocity": 1.0 },
            "workspace.jump":   { "via": "dockSwipe", "velocity": 9999 },
            "overview.open":    { "duration": 0.27, "curve": "easeOut" },
            "dock.magnify":     { "spring": { "response": 0.12, "damping": 0.75 } },
            "window.move":      { "via": "proxy", "duration": 0.22, "curve": "easeInOutCos" },
            "card.enter":       { "spring": { "response": 0.4, "damping": 0.75 } } } }
        """)
        #expect(config.speed == 1)
        #expect(config.reduceMotion == .system)
        #expect(config.defaults["spring"] == .spring(response: 0.35, damping: 0.86))
        #expect(config.defaults["spaceSlide"] == .spring(response: 0.52, damping: 0.91))
        #expect(config.elements[.workspaceSwitch] == .dockSwipe(velocity: 1))
        #expect(config.elements[.workspaceJump] == .dockSwipe(velocity: 9999))
        #expect(config.elements[.overviewOpen] == .timed(duration: 0.27, curve: .easeOut))
        #expect(config.elements[.dockMagnify] == .spring(response: 0.12, damping: 0.75))
        #expect(config.elements[.windowMove] == .proxy(duration: 0.22, curve: .easeInOutCos))
        #expect(config.elements[.cardEnter] == .spring(response: 0.4, damping: 0.75))
    }

    @Test func missingFieldsTakeDefaults() throws {
        #expect(try decode(#"{ "speed": 2 }"#) == MotionConfig(speed: 2))
        #expect(try decode("{}") == MotionConfig())
    }

    @Test func roundTripsEveryShape() throws {
        let config = MotionConfig(speed: 1.5, reduceMotion: .always,
            defaults: ["spring": .spring(response: 0.3, damping: 0.8)],
            elements: [
                .cardEnter: .spring(response: 0.4, damping: 0.75),
                .overviewOpen: .timed(duration: 0.27, curve: .bezier(0.1, 0.2, 0.3, 0.4)),
                .workspaceSwitch: .dockSwipe(velocity: 1),
                .windowMove: .proxy(duration: 0.22, curve: .easeInOutCos),
                .barReveal: .crossFade(duration: 0.15),
                .osdShow: .instant,
                .dockBounce: .timed(duration: 0.7, curve: .dockBounce),
            ])
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(MotionConfig.self, from: data) == config)
    }

    @Test func encodesTheSpec7Shape() throws {
        let data = try JSONEncoder().encode(MotionConfig(defaults: ["spring": .spring(response: 0.35, damping: 0.86)],
                                                         elements: [.windowMove: .proxy(duration: 0.22, curve: .easeInOutCos)]))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let defaults = try #require(json["defaults"] as? [String: [String: Double]])
        #expect(defaults["spring"] == ["response": 0.35, "damping": 0.86])
        let move = try #require((json["elements"] as? [String: [String: Any]])?["window.move"])
        #expect(move["via"] as? String == "proxy")
        #expect(move["curve"] as? String == "easeInOutCos")
    }

    @Test(arguments: [
        #"{ "elements": { "nope.key": { "via": "instant" } } }"#,
        #"{ "elements": { "card.enter": { "via": "teleport" } } }"#,
        #"{ "elements": { "card.enter": { "duration": 0.2 } } }"#,
        #"{ "elements": { "card.enter": { "duration": 0.2, "curve": "wobble" } } }"#,
        #"{ "elements": { "card.enter": {} } }"#,
        #"{ "reduceMotion": "sometimes" }"#,
    ])
    func rejectsMalformedMotion(json: String) {
        #expect(throws: DecodingError.self) { try decode(json) }
    }
}
