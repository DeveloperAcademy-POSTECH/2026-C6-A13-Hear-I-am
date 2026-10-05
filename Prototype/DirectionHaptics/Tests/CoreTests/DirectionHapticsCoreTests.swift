import XCTest
@testable import DirectionHapticsCore

final class DirectionHapticsCoreTests: XCTestCase {
    func testClockwiseRotationAndAngleWrap() {
        XCTAssertEqual(RotationRecognition.clockwiseDegrees(yaw: -.pi / 2, referenceYaw: 0), 90, accuracy: 0.001)
        XCTAssertEqual(RotationRecognition.clockwiseDegrees(yaw: .pi / 2, referenceYaw: 0), -90, accuracy: 0.001)
        XCTAssertEqual(RotationRecognition.clockwiseDegrees(yaw: -179 * .pi / 180, referenceYaw: 179 * .pi / 180), -2, accuracy: 0.001)
        XCTAssertEqual(RotationRecognition.normalized(540), 180)
        XCTAssertTrue(RotationRecognition.normalized(.nan).isNaN)
    }

    func testAllDirectionsSubmitAfterOneSecondAndOnlyOnce() throws {
        for direction in Direction.allCases {
            let degrees = RotationRecognition.target(for: direction)
            var hold = RotationHold()
            for index in 0..<10 {
                XCTAssertNil(hold.update(degrees: degrees, angularSpeed: 2, faceUp: true, time: Double(index) / 10))
            }
            let answer = try XCTUnwrap(hold.update(degrees: degrees, angularSpeed: 2, faceUp: true, time: 1))
            XCTAssertEqual(answer.direction, direction)
            XCTAssertTrue(answer.isCorrect(for: direction))
            XCTAssertNil(hold.update(degrees: degrees, angularSpeed: 2, faceUp: true, time: 1.1))
        }
    }

    func testWrongAndDiagonalHoldsSubmitInsteadOfWaitingForTarget() throws {
        for degrees in [-90.0, 0, 45] {
            var hold = RotationHold()
            for index in 0..<10 {
                XCTAssertNil(hold.update(degrees: degrees, angularSpeed: 0, faceUp: true, time: Double(index) / 10))
            }
            let answer = try XCTUnwrap(hold.update(degrees: degrees, angularSpeed: 0, faceUp: true, time: 1))
            XCTAssertFalse(answer.isCorrect(for: .right))
            if degrees == 45 { XCTAssertNil(answer.direction) }
        }
    }

    func testMovementPostureAndMissingSamplesRestartEntireHold() throws {
        // angle, speed, posture, time, whether the resetting sample itself starts a new hold
        for invalid in [(90.0, 50.0, true, 0.9, false), (90, 0, false, 0.9, false),
                        (Double.nan, 0, true, 0.9, false), (90, 0, true, 2, true),
                        (90, 0, true, 0.7, true), (115, 0, true, 0.9, true)] {
            var hold = RotationHold()
            for index in 0..<9 {
                XCTAssertNil(hold.update(degrees: 90, angularSpeed: 0, faceUp: true, time: Double(index) / 10))
            }
            XCTAssertNil(hold.update(degrees: invalid.0, angularSpeed: invalid.1, faceUp: invalid.2, time: invalid.3))
            let restart = invalid.4 ? invalid.3 : invalid.3 + 0.1
            let degrees = invalid.0.isFinite ? invalid.0 : 90
            // Resume without another gap or angle change that could mask the reset under test.
            for index in (invalid.4 ? 1 : 0)..<10 {
                XCTAssertNil(hold.update(degrees: degrees, angularSpeed: 0, faceUp: true, time: restart + Double(index) / 10))
            }
            let answer = try XCTUnwrap(hold.update(degrees: degrees, angularSpeed: 0, faceUp: true, time: restart + 1.01))
            XCTAssertEqual(answer.degrees, degrees)
        }
    }

    func testSlowRotationDoesNotAccumulateHoldTime() {
        var hold = RotationHold()
        for index in 0..<100 {
            XCTAssertNil(hold.update(degrees: Double(index) * 1.4, angularSpeed: 14, faceUp: true, time: Double(index) / 10))
        }
    }

    func testBackWrapAndTwentyDegreeAnswerTolerance() throws {
        var hold = RotationHold()
        for index in 0..<10 {
            XCTAssertNil(hold.update(degrees: index % 2 == 0 ? 179 : -179, angularSpeed: 0, faceUp: true, time: Double(index) / 10))
        }
        let answer = try XCTUnwrap(hold.update(degrees: -179, angularSpeed: 0, faceUp: true, time: 1))
        XCTAssertTrue(answer.isCorrect(for: .back))
        for direction in Direction.allCases {
            let target = RotationRecognition.target(for: direction)
            for offset in [-20.0, 20] { XCTAssertTrue(RotationAnswer(degrees: target + offset).isCorrect(for: direction)) }
            for offset in [-20.1, 20.1] { XCTAssertFalse(RotationAnswer(degrees: target + offset).isCorrect(for: direction)) }
        }
    }

    func testDefaultIntensityIsFullExceptIntentionalStrengthDifferences() {
        for set in Presets.all where set.code != "F" {
            for direction in Direction.allCases {
                for step in set.pattern(for: direction).steps where step.kind != .pause {
                    XCTAssertEqual(step.intensity, 1, "\(set.code) \(direction)")
                }
            }
        }
        XCTAssertEqual(Direction.allCases.map { Presets.all[5].pattern(for: $0).steps[0].intensity }, [0.3, 0.5, 0.75, 1])
        XCTAssertEqual(Presets.all[4].pattern(for: .front).steps[0].envelope, .rise)
        XCTAssertEqual(HapticStep.tap().intensity, 1)
        XCTAssertEqual(HapticStep.buzz(0.3).intensity, 1)
        XCTAssertEqual(AppPreferences().gain, 1)
    }

    func testExistingPreferencesMigrateWithoutDiscardingUserSettings() throws {
        let data = Data(#"{"gain":0.65,"preparationSeconds":5,"keepAwake":false,"swipeToAnswer":true,"appearance":"dark"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(decoded.gain, 0.65)
        XCTAssertEqual(decoded.preparationSeconds, 5)
        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertFalse(decoded.keepAwake)
        XCTAssertTrue(decoded.successSound)
    }

    func testRandomDirectionsAreReproducibleIndependentDraws() {
        var source = RandomDirectionSource(seed: 42)
        var same = RandomDirectionSource(seed: 42)
        let directions = (0..<100).map { _ in source.next() }
        XCTAssertEqual(directions, (0..<100).map { _ in same.next() })
        XCTAssertEqual(Set(directions), Set(Direction.allCases))
        XCTAssertTrue(zip(directions, directions.dropFirst()).contains { $0 == $1 }, "Repeated directions must be possible, not a predictable four-item deck")
    }

    func testPreferencesPersistAndClampInvalidPlaybackValues() throws {
        var preferences = AppPreferences()
        preferences.gain = 0.65; preferences.preparationSeconds = 5
        preferences.appearance = .dark; preferences.successSound = false
        XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences)), preferences)
        preferences.gain = .nan; preferences.preparationSeconds = 0
        XCTAssertEqual(preferences.validated.gain, 1)
        XCTAssertEqual(preferences.validated.preparationSeconds, 1)
        preferences.gain = 2; preferences.preparationSeconds = 999
        XCTAssertEqual(preferences.validated.gain, 1)
        XCTAssertEqual(preferences.validated.preparationSeconds, 10)
    }

    func testAll32PresetsCompileAndDirectionsDifferWithinEachSet() throws {
        XCTAssertEqual(Presets.all.count, 8)
        XCTAssertEqual(Set(Presets.all.map(\.id)).count, 8)
        for set in Presets.all {
            XCTAssertNil(set.validationIssue, set.name)
            let compiled = try Direction.allCases.map { try PatternCompiler.compile(set.pattern(for: $0)) }
            for i in compiled.indices {
                XCTAssertFalse(compiled[i].pulses.isEmpty)
                XCTAssertGreaterThan(compiled[i].duration, 0)
                XCTAssertEqual(compiled[i].duration, set.pattern(for: Direction.allCases[i]).duration, accuracy: 0.00001)
                for j in compiled.indices where j > i {
                    XCTAssertNotEqual(compiled[i].pulses, compiled[j].pulses, "\(set.name): directions \(i), \(j)")
                }
            }
        }
    }

    func testCompilerPreservesGapsRepeatsGainAndEnvelopes() throws {
        let pattern = HapticPattern(steps: [.tap(0.8), .rest(0.2), .buzz(0.4, intensity: 0.6, sharpness: 0.9, envelope: .rise)], repetitions: 2, repeatGap: 0.3)
        let compiled = try PatternCompiler.compile(pattern, gain: 0.5)
        XCTAssertEqual(compiled.pulses.count, 4)
        for (pulse, start) in zip(compiled.pulses, [0.0, 0.27, 0.97, 1.24]) { XCTAssertEqual(pulse.start, start, accuracy: 0.00001) }
        XCTAssertEqual(compiled.duration, 1.64, accuracy: 0.00001)
        XCTAssertEqual(compiled.pulses[0].duration, 0)
        XCTAssertEqual(compiled.pulses[0].intensity, 0.4)
        XCTAssertEqual(compiled.pulses[1].intensity, 0.3)
        XCTAssertEqual(compiled.pulses[1].sharpness, 0.9)
        XCTAssertEqual(compiled.pulses[1].envelope, .rise)
    }

    func testInvalidPatternsAndNonFiniteValuesCannotReachEngine() {
        let invalid: [HapticPattern] = [
            .init(steps: []), .init(steps: [.rest(0.5)]), .init(steps: [.buzz(.nan)]),
            .init(steps: [.tap(.infinity)]), .init(steps: [.tap(sharpness: -0.1)]),
            .init(steps: [.buzz(2)], repetitions: 5, repeatGap: 2),
            .init(steps: Array(repeating: .tap(), count: 17)),
            .init(steps: [.tap()], repetitions: 0), .init(steps: [.tap()], repeatGap: .nan)
        ]
        for pattern in invalid { XCTAssertThrowsError(try PatternCompiler.compile(pattern)) }
        for gain in [0.0, 1.1, Double.nan, .infinity] {
            XCTAssertThrowsError(try PatternCompiler.compile(Presets.all[0].pattern(for: .front), gain: gain))
        }
        var missing = Presets.all[0]
        missing.patterns.removeValue(forKey: .left)
        XCTAssertNotNil(missing.validationIssue)
    }

    func testSnapshotsRemainUnchangedAfterEditingAndSwapping() {
        let original = Presets.all[0]
        var edited = original.userCopy()
        let session = StudySession(sets: [edited], context: .init(), seed: 12)
        edited.swap(.left, .right)
        edited.patterns[.front]?.steps[0].intensity = 0.2
        edited.revision = 2
        XCTAssertEqual(session.sets[0].pattern(for: .left), original.pattern(for: .left))
        XCTAssertEqual(session.sets[0].pattern(for: .front), original.pattern(for: .front))
        XCTAssertEqual(edited.pattern(for: .left), original.pattern(for: .right))
        XCTAssertEqual(session.sets[0].revision, 1)
        XCTAssertNotEqual(edited.id, original.id)
        XCTAssertEqual(edited.sourceID, original.id)
        XCTAssertFalse(edited.isBuiltIn)
    }

    func testBalancedRandomizationAndReproducibleSeed() {
        let first = StudySession(sets: Array(Presets.all.prefix(2)), context: .init(), seed: 78541)
        let same = StudySession(sets: Array(Presets.all.prefix(2)), context: .init(), seed: 78541)
        let other = StudySession(sets: Array(Presets.all.prefix(2)), context: .init(), seed: 93481)
        XCTAssertEqual(first.plannedCount, 40)
        XCTAssertEqual(first.orders, same.orders)
        XCTAssertEqual(first.sets, same.sets)
        XCTAssertNotEqual(first.orders, other.orders)
        for order in first.orders {
            for direction in Direction.allCases { XCTAssertEqual(order.filter { $0 == direction }.count, 5) }
        }
        let blockOrders = (0..<30).map { StudySession(sets: Array(Presets.all.prefix(2)), context: .init(), seed: UInt64($0)).sets[0].id }
        XCTAssertEqual(Set(blockOrders).count, 2)
    }

    func testStatisticsExcludeFailuresButIncludeUnknownAndReplays() {
        let stats = StudyStatistics(records: [
            .init(block: 0, index: 0, expected: .front, answered: .front, outcome: .answered),
            .init(block: 0, index: 1, expected: .front, answered: .front, outcome: .answered, replays: 2),
            .init(block: 0, index: 2, expected: .left, answered: .right, outcome: .answered),
            .init(block: 0, index: 3, expected: .left, outcome: .answered),
            .init(block: 0, index: 4, expected: .back, outcome: .failed),
            .init(block: 0, index: 4, expected: .back, outcome: .skipped)
        ])
        XCTAssertEqual(stats.accuracy, 0.5)
        XCTAssertEqual(stats.firstPlayAccuracy, 0.25)
        XCTAssertEqual(stats.accuracy(for: .front), 1)
        XCTAssertEqual(stats.accuracy(for: .left), 0)
        XCTAssertNil(stats.accuracy(for: .back))
        XCTAssertEqual(stats.confusion(expected: .left, answered: nil), 1)
        XCTAssertEqual(stats.confusion(expected: .left, answered: .right), 1)
        XCTAssertEqual(stats.replays, 2)
        XCTAssertEqual(stats.failures, 1)
        XCTAssertEqual(stats.skipped, 1)
        XCTAssertNil(StudyStatistics(records: []).accuracy)
    }

    func testArchiveOnlyStoresPatternsAndFavoritesNotExperimentResults() throws {
        var archive = AppArchive()
        archive.userSets = [Presets.all[1].userCopy()]
        archive.favorites.insert(Presets.all[0].id)
        let data = try JSONEncoder().encode(archive)
        let restored = try JSONDecoder().decode(AppArchive.self, from: data)
        XCTAssertEqual(restored.userSets, archive.userSets)
        XCTAssertEqual(restored.favorites, archive.favorites)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "userSets", "favorites"])
    }
}
