//
//  FingerScriptGuidance.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 23/11/2026.
//

import Foundation

/// The recorded lines of one repetition of a 2026-11-23 left-hand script. Keys are full
/// String Catalog keys.
struct FingerScriptRepetition {
    /// Spoken at the start of a set, while the start pose is held.
    var start: [String] = []
    /// Spoken before the first target of a repetition that does not start the set, after the
    /// previous repetition's praise.
    var lead: [String] = []
    /// The target cue per finger: one entry for a single-pose exercise, four for a sequence.
    var targets: [String]
    /// The cue back to the start pose, per finger, or one entry for every finger.
    var returns: [String]

    func target(_ finger: Int) -> String {
        targets[min(finger, targets.count - 1)]
    }

    func back(_ finger: Int) -> String {
        returns[min(finger, returns.count - 1)]
    }
}

/// One exercise's 2026-11-23 left-hand script, as recorded (see
/// Documentation/LeftScriptsNarration.md for the source of every line).
struct FingerScript {
    /// "Selanjutnya kita akan latihan …" and "Latihan ini membantu melatih …".
    let introduction: [String]
    /// "Sebelumnya, kita akan menyesuaikan posisi …", in the exercise's own wording.
    let introCalibration: String
    /// The calibration start pose per calibrated finger (the first one opens the calibration).
    let calibrationStarts: [String]
    /// The calibration target per calibrated finger.
    let calibrationTargets: [String]
    /// Spoken once calibration is complete, before the countdown.
    let calibrationEnding: [String]
    /// Re-opens the start pose after a pause invalidated an unfinished repetition.
    let reopen: String
    /// The first set's recorded repetitions one to five.
    let firstSet: [FingerScriptRepetition]
    /// Later sets' recorded repetitions one to three.
    let laterSets: [FingerScriptRepetition]
    /// Praise after repetitions one to four; the fourth says one repetition remains.
    let praise: [String]
    /// The script's next repetition opens with the cue back to the start pose ("Kita lanjut,
    /// putar kembali … ke arah luar"), so a return speaks the next repetition's `lead` and its
    /// target follows without it. The last return speaks `finalReturn`.
    var returnsWithNextLead = false
    var finalReturn: String? = nil
    /// "Pastikan seluruh jari tangan kirimu terlihat…", or the exercise's own wording.
    var visibleKey = "scripted.left.hand.visible"
    /// "Bagus, posisi tangan sudah terlihat…", or the exercise's own wording.
    var detectedKey = "scripted.left.hand.detected"
}

/// Chooses the 2026-11-23 left-hand scripts' recorded lines from the finger activity's state.
///
/// Like `OppositionGuidance`, it follows any prescription: sentences that state a number play
/// only when it is true (`ScriptedRepetitions`), and Marizka number clips say other counts.
enum FingerScriptGuidance {
    /// The script of `kind` on `side`, or nil when that hand has no 2026-11-23 script. Only the
    /// left hand is written; the right hand's thumb opposition keeps `OppositionGuidance`.
    static func script(for kind: FingerExercise, side: HandSide) -> FingerScript? {
        guard side == .left else {
            return nil
        }

        switch kind {
        case .fullFist:
            return fullFist
        case .hookFist:
            return hookFist
        case .spreading:
            return spreading
        case .extensionSequence:
            return extensionSequence
        case .opposition:
            return opposition
        case .forearmRotation:
            return forearmRotation
        }
    }

    /// Whether `kind` on `side` runs an Indonesian script, old or new: 3 s holds with spoken
    /// seconds and a 5 s countdown before later sets.
    static func isScripted(_ kind: FingerExercise, side: HandSide) -> Bool {
        OppositionGuidance.applies(to: kind) || script(for: kind, side: side) != nil
    }

    // MARK: - Intro

    /// The plan intro: title and purpose, the goals when a recording states them, then the
    /// calibration, safety and voice-command notes.
    static func introduction(_ script: FingerScript, sets: Int, repetitions: Int) -> [NarrationLine] {
        var lines = script.introduction.map { NarrationLine(key: $0) }

        if ScriptedRepetitions.hasRecordedGoals(sets: sets, repetitions: repetitions) {
            lines.append(NarrationLine(key: "scripted.intro.goalsTwoSets %lld", argument: repetitions))
        }

        lines += [script.introCalibration, "scripted.intro.safety", "scripted.intro.voice"]
            .map { NarrationLine(key: $0) }
        return lines
    }

    // MARK: - Session

    /// Phase 1, before calibration: sit, place the hands, show the hand (forearm rotation: the
    /// elbow, arm, wrist and palm).
    static func setupLines(for script: FingerScript) -> [NarrationLine] {
        ["scripted.left.hand.sit", "scripted.left.hand.position", script.visibleKey]
            .map { NarrationLine(key: $0) }
    }

    /// What the scripts say when the hand is out of view or turned away.
    static func recoveryKey(for problem: FingerTrackingProblem, script: FingerScript) -> String? {
        switch problem {
        case .position:
            return "scripted.left.hand.adjust"
        case .fingers:
            return script.visibleKey
        default:
            return nil
        }
    }

    /// The recorded lines for the current moment, in speaking order.
    static func movementLines(for activity: FingerActivity, script: FingerScript) -> [NarrationLine] {
        let finger = activity.finger
        let goal = activity.routine.repetitions

        switch activity.phase {
        case .baseline:
            if finger == 0 {
                // The hand was found: phase 2 begins.
                return [
                    script.detectedKey,
                    "scripted.left.calibration.intro",
                    script.calibrationStarts[0],
                ].map { NarrationLine(key: $0) }
            }
            return [NarrationLine(key: script.calibrationStarts[min(finger, script.calibrationStarts.count - 1)])]
        case .target:
            return [NarrationLine(key: script.calibrationTargets[min(finger, script.calibrationTargets.count - 1)])]
        case .demonstration:
            return script.calibrationEnding.map { NarrationLine(key: $0) }
        case .countdown:
            return [NarrationLine(key: activity.set == 1 ? "calibration.countdown" : "scripted.countdown.next")]
        case .active:
            return practiceLines(for: activity, script: script, goal: goal)
        case .feedback:
            return summaryLines(completedSets: activity.completedSets, routine: activity.routine)
        default:
            return []
        }
    }

    private static func practiceLines(for activity: FingerActivity, script: FingerScript, goal: Int) -> [NarrationLine] {
        let finger = activity.finger
        let repetition = activity.repetitions + 1
        let recorded = recordedRepetition(repetition, set: activity.set, goal: goal, script: script)

        if activity.needsStart {
            guard repetition == 1, finger == 0 else {
                // Pause invalidates an unfinished cycle: re-open, then repeat the current
                // finger, without praising discarded movement.
                return [NarrationLine(key: script.reopen)]
            }

            let opening = activity.set > 1 ? [nextSetKey(activity.set)] : []
            return (opening + recorded.start).map { NarrationLine(key: $0) }
        }

        if activity.returning {
            return [NarrationLine(key: returnKey(repetition: repetition, finger: finger, set: activity.set, goal: goal, script: script))]
        }

        var lines: [NarrationLine] = []
        if finger == 0, repetition > 1 {
            lines.append(praise(after: repetition - 1, goal: goal, script: script))
            if !script.returnsWithNextLead {
                lines += recorded.lead.map { NarrationLine(key: $0) }
            }
        }
        lines.append(NarrationLine(key: recorded.target(finger)))
        return lines
    }

    /// The cue back to the start pose after `repetition`'s target. Chosen by the next
    /// repetition's recorded variant when the script opens repetitions with that cue, so its
    /// "Terakhir" is said only before the last repetition.
    private static func returnKey(repetition: Int, finger: Int, set: Int, goal: Int, script: FingerScript) -> String {
        guard script.returnsWithNextLead else {
            return recordedRepetition(repetition, set: set, goal: goal, script: script).back(finger)
        }

        guard repetition < goal else {
            return script.finalReturn ?? recordedRepetition(repetition, set: set, goal: goal, script: script).back(finger)
        }

        let next = recordedRepetition(repetition + 1, set: set, goal: goal, script: script)
        return next.lead.first ?? next.back(finger)
    }

    private static func recordedRepetition(_ repetition: Int, set: Int, goal: Int, script: FingerScript) -> FingerScriptRepetition {
        if set == 1 {
            return script.firstSet[ScriptedRepetitions.recordedRepetition(repetition, goal: goal) - 1]
        }

        return script.laterSets[ScriptedRepetitions.recordedLaterSetRepetition(repetition, goal: goal) - 1]
    }

    /// "Yuk kita mulai lagi untuk set kedua", recorded for sets two to five.
    private static func nextSetKey(_ set: Int) -> String {
        "scripted.nextSet.\(min(max(set, 2), 5))"
    }

    /// Recorded praise for the first three repetitions, and for the fourth only when one
    /// repetition remains, as its "satu repetisi lagi" says. Otherwise the Marizka number.
    private static func praise(after repetition: Int, goal: Int, script: FingerScript) -> NarrationLine {
        let lastButOne = repetition == 4 && goal == 5
        guard repetition <= 3 || lastButOne else {
            return .number(repetition)
        }

        return NarrationLine(key: script.praise[repetition - 1])
    }

    static func summaryLines(completedSets: Int, routine: FingerRoutine) -> [NarrationLine] {
        ScriptedSummary.lines(completedSets: completedSets, sets: routine.sets, goal: routine.repetitions)
    }

    // MARK: - Scripts

    private static let commonPraise = (1...4).map { "scripted.praise.\($0)" }

    /// A single-pose repetition: start (first only), target, return.
    private static func pose(_ prefix: String, start: String? = nil, target: String, back: String) -> FingerScriptRepetition {
        FingerScriptRepetition(
            start: start.map { [prefix + $0] } ?? [],
            targets: [prefix + target],
            returns: [prefix + back]
        )
    }

    private static let fullFist: FingerScript = {
        let p = "fullFist.left."
        return FingerScript(
            introduction: [p + "intro.title", p + "intro.purpose"],
            introCalibration: "scripted.intro.calibration",
            calibrationStarts: [p + "prep.start"],
            calibrationTargets: [p + "prep.target"],
            calibrationEnding: [p + "prep.return", "scripted.calibration.complete"],
            reopen: p + "prep.start",
            firstSet: [
                pose(p, start: "firstSet.rep.1.start", target: "firstSet.rep.1.target", back: "firstSet.rep.1.return"),
                pose(p, target: "firstSet.rep.2.target", back: "firstSet.rep.2.return"),
                pose(p, target: "firstSet.rep.3.target", back: "firstSet.rep.3.return"),
                pose(p, target: "firstSet.rep.4.target", back: "firstSet.rep.1.return"),
                pose(p, target: "firstSet.rep.5.target", back: "firstSet.rep.5.return"),
            ],
            laterSets: [
                pose(p, start: "laterSet.rep.1.start", target: "laterSet.rep.1.target", back: "laterSet.rep.1.return"),
                pose(p, target: "firstSet.rep.2.target", back: "firstSet.rep.2.return"),
                pose(p, target: "firstSet.rep.5.target", back: "firstSet.rep.5.return"),
            ],
            praise: commonPraise
        )
    }()

    private static let hookFist: FingerScript = {
        let p = "hookFist.left."
        return FingerScript(
            introduction: [p + "intro.title", p + "intro.purpose"],
            introCalibration: "scripted.intro.calibration",
            calibrationStarts: [p + "prep.start"],
            calibrationTargets: [p + "prep.target"],
            calibrationEnding: [p + "prep.return", "scripted.calibration.complete"],
            reopen: p + "prep.start",
            firstSet: [
                pose(p, start: "firstSet.rep.1.start", target: "firstSet.rep.1.target", back: "firstSet.rep.1.return"),
                pose(p, target: "firstSet.rep.2.target", back: "firstSet.rep.2.return"),
                pose(p, target: "firstSet.rep.3.target", back: "firstSet.rep.3.return"),
                pose(p, target: "firstSet.rep.4.target", back: "firstSet.rep.2.return"),
                pose(p, target: "firstSet.rep.5.target", back: "firstSet.rep.2.return"),
            ],
            laterSets: [
                pose(p, start: "laterSet.rep.1.start", target: "firstSet.rep.1.target", back: "firstSet.rep.1.return"),
                pose(p, target: "firstSet.rep.2.target", back: "firstSet.rep.2.return"),
                pose(p, target: "firstSet.rep.5.target", back: "firstSet.rep.2.return"),
            ],
            praise: commonPraise
        )
    }()

    private static let spreading: FingerScript = {
        let p = "spreading.left."
        return FingerScript(
            introduction: [p + "intro.title", p + "intro.purpose"],
            introCalibration: "scripted.intro.calibration",
            calibrationStarts: [p + "prep.start"],
            calibrationTargets: [p + "prep.target"],
            calibrationEnding: [p + "prep.return", "scripted.calibration.complete"],
            reopen: p + "prep.start",
            firstSet: [
                pose(p, start: "firstSet.rep.1.start", target: "firstSet.rep.1.target", back: "firstSet.rep.1.return"),
                pose(p, target: "firstSet.rep.2.target", back: "firstSet.rep.2.return"),
                pose(p, target: "firstSet.rep.3.target", back: "firstSet.rep.3.return"),
                pose(p, target: "firstSet.rep.4.target", back: "firstSet.rep.3.return"),
                pose(p, target: "firstSet.rep.3.target", back: "firstSet.rep.3.return"),
            ],
            laterSets: [
                pose(p, start: "laterSet.rep.1.start", target: "firstSet.rep.1.target", back: "firstSet.rep.1.return"),
                pose(p, target: "firstSet.rep.2.target", back: "firstSet.rep.2.return"),
                pose(p, target: "laterSet.rep.3.target", back: "firstSet.rep.3.return"),
            ],
            praise: commonPraise
        )
    }()

    private static let extensionSequence: FingerScript = {
        let p = "extensionSequence.left."
        let fingers = 0..<4
        let back = [p + "firstSet.return"]

        func targets(_ repetition: Int) -> [String] {
            fingers.map { p + "firstSet.rep.\(repetition).target.\($0)" }
        }

        // Repetition 5 names only the first two fingers; the last two repeat repetition 4's.
        let fifthTargets = [
            p + "firstSet.rep.5.target.0",
            p + "firstSet.rep.5.target.1",
            p + "firstSet.rep.4.target.2",
            p + "firstSet.rep.4.target.3",
        ]
        let first = FingerScriptRepetition(
            start: [p + "firstSet.rep.1.opening", p + "firstSet.rep.1.start"],
            targets: fingers.map { p + "prep.target.\($0)" },
            returns: fingers.map { p + "prep.return.\($0)" }
        )
        let third = FingerScriptRepetition(lead: [p + "firstSet.rep.3.start"], targets: targets(3), returns: back)
        let fifth = FingerScriptRepetition(lead: [p + "firstSet.rep.5.start"], targets: fifthTargets, returns: back)

        return FingerScript(
            introduction: [p + "intro.title", p + "intro.purpose"],
            introCalibration: "scripted.intro.calibration",
            calibrationStarts: [p + "prep.start"] + (0..<3).map { p + "prep.return.\($0)" },
            calibrationTargets: fingers.map { p + "prep.target.\($0)" },
            calibrationEnding: [p + "prep.return.3", p + "prep.end", "scripted.calibration.complete"],
            reopen: p + "prep.end",
            firstSet: [
                first,
                FingerScriptRepetition(lead: [p + "firstSet.rep.2.start"], targets: targets(2), returns: back),
                third,
                FingerScriptRepetition(lead: [p + "firstSet.rep.4.start"], targets: targets(4), returns: back),
                fifth,
            ],
            laterSets: [
                FingerScriptRepetition(start: [p + "laterSet.rep.1.start"], targets: targets(2), returns: back),
                third,
                fifth,
            ],
            praise: commonPraise
        )
    }()

    private static let forearmRotation: FingerScript = {
        let p = "forearmRotation.left."

        func turn(_ repetition: Int, start: [String] = [], lead: String? = nil, target: String) -> FingerScriptRepetition {
            FingerScriptRepetition(
                start: start.map { p + $0 },
                lead: lead.map { [p + $0] } ?? [],
                targets: [p + target],
                returns: [p + "prep.return"]
            )
        }

        return FingerScript(
            introduction: [p + "intro.title", p + "intro.purpose"],
            introCalibration: "opposition.left.intro.calibration",
            calibrationStarts: [p + "prep.start"],
            calibrationTargets: [p + "prep.target"],
            calibrationEnding: [p + "prep.return", "scripted.left.calibration.prepared"],
            reopen: p + "prep.start",
            firstSet: [
                turn(1, start: ["firstSet.rep.1.start"], target: "firstSet.rep.1.target"),
                turn(2, lead: "firstSet.rep.2.start", target: "firstSet.rep.2.target"),
                turn(3, lead: "firstSet.rep.3.start", target: "firstSet.rep.3.target"),
                turn(4, lead: "firstSet.rep.4.start", target: "firstSet.rep.4.target"),
                turn(5, lead: "firstSet.rep.5.start", target: "firstSet.rep.4.target"),
            ],
            laterSets: [
                turn(1, start: ["laterSet.rep.1.start"], target: "firstSet.rep.1.target"),
                turn(2, lead: "firstSet.rep.2.start", target: "firstSet.rep.2.target"),
                turn(3, lead: "firstSet.rep.5.start", target: "firstSet.rep.4.target"),
            ],
            praise: ["scripted.praise.1", "opposition.left.praise.2", "opposition.left.praise.3", "opposition.left.praise.4"],
            returnsWithNextLead: true,
            finalReturn: p + "prep.return",
            visibleKey: p + "prep.visible",
            detectedKey: p + "prep.detected"
        )
    }()

    private static let opposition: FingerScript = {
        let p = "opposition.left."
        let shortTouches = (0..<4).map { p + "short.touch.\($0)" }
        let short = FingerScriptRepetition(targets: shortTouches, returns: [p + "short.open"])
        // Repetition 2 reuses approved 14/11 clips where its words are the same.
        let secondTouches = [
            p + "firstSet.rep.2.touch.0",
            p + "rep.2.touch.1",
            p + "rep.2.touch.2",
            p + "rep.3.touch.3",
        ]
        let secondOpens = [p + "rep.2.open.0", p + "rep.2.open.1", p + "rep.1.open.1", p + "short.open"]

        return FingerScript(
            introduction: [p + "intro.title", p + "intro.purpose"],
            introCalibration: p + "intro.calibration",
            calibrationStarts: [p + "prep.start", p + "calibration.open", p + "calibration.open", p + "rep.1.open.1"],
            calibrationTargets: (0..<4).map { p + "prep.touch.\($0)" },
            calibrationEnding: [p + "prep.openPalm", "scripted.left.calibration.prepared"],
            reopen: p + "calibration.open",
            firstSet: [
                FingerScriptRepetition(
                    start: [p + "firstSet.rep.1.opening"],
                    targets: [p + "rep.1.touch.0", p + "firstSet.rep.1.touch.1", p + "rep.2.touch.2", p + "rep.1.touch.3"],
                    returns: [p + "firstSet.rep.1.open.0", p + "rep.1.open.1", p + "rep.2.open.1", p + "rep.1.open.3"]
                ),
                FingerScriptRepetition(targets: secondTouches, returns: secondOpens),
                short,
                short,
                short,
            ],
            laterSets: [
                FingerScriptRepetition(
                    targets: [p + "laterSet.rep.1.touch.0"] + secondTouches.dropFirst(),
                    returns: secondOpens
                ),
                FingerScriptRepetition(lead: [p + "rep.4.opening"], targets: shortTouches, returns: [p + "short.open"]),
                short,
            ],
            praise: ["scripted.praise.1", p + "praise.2", p + "praise.3", p + "praise.4"]
        )
    }()
}
