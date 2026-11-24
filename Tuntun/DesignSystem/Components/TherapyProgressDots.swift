//
//  TherapyProgressDots.swift
//  Tuntun
//
//  Created by dimaswisodewo on 06/11/2026.
//

import SwiftUI

/// Quiet repetition progress for the camera view: one soft dot per repetition, no counters.
///
/// Long goals fall back to a thin bar so the row never wraps or crowds the preview.
struct TMTherapyProgressDots: View {
    let completed: Int
    let total: Int
    var label: LocalizedStringKey

    private let maximumDots = 12

    var body: some View {
        let done = min(max(0, completed), max(0, total))

        content(done: done)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.65), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(verbatim: "\(done) / \(total)"))
    }

    @ViewBuilder
    private func content(done: Int) -> some View {
        if total <= maximumDots {
            HStack(spacing: 12) {
                ForEach(0..<max(0, total), id: \.self) { index in
                    Circle()
                        .fill(index < done ? TherapyPalette.guidanceBlue : .clear)
                        .overlay {
                            Circle().strokeBorder(TherapyPalette.guidanceBlue, lineWidth: 3)
                        }
                        .frame(width: 24, height: 24)
                }
            }
        } else {
            ProgressView(value: Double(done), total: Double(max(1, total)))
                .tint(TherapyPalette.guidanceBlue)
                .frame(width: 200)
        }
    }
}

// MARK: - Set progress

/// Every set of the exercise as "Set N" over one circle per repetition, for the live layout's
/// side column. Done repetitions are green circles with a check; the rest are quiet grey.
///
/// Earlier sets are drawn full: a set only advances once its goal is reached, and Skip ends the
/// activity. Circles keep the size twelve would need, so a shorter goal spreads its circles
/// across the row instead of growing them. Goals above twelve wrap into rows of twelve.
struct TMTherapySetProgress: View {
    let setNumber: Int
    let setTotal: Int
    let completed: Int
    let goal: Int
    let setLabel: (Int) -> Text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let circlesPerRow = 12
    private static let minimumSpacing: CGFloat = 4
    private static let maximumDiameter: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(1...max(1, setTotal), id: \.self) { set in
                setRow(set)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func setRow(_ set: Int) -> some View {
        let done = doneCount(in: set)

        return VStack(alignment: .leading, spacing: 8) {
            setLabel(set)
                .typography(size: 24, weight: .medium, relativeTo: .title3)
                .foregroundStyle(TherapyPalette.ink)

            circleRows(done: done)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(setLabel(set))
        .accessibilityValue(Text(verbatim: "\(done) / \(max(0, goal))"))
    }

    private func doneCount(in set: Int) -> Int {
        let goal = max(0, goal)

        if set < setNumber {
            return goal
        }

        if set == setNumber {
            return min(max(0, completed), goal)
        }

        return 0
    }

    /// Measures the width once and lays the circles out in rows of at most twelve.
    private func circleRows(done: Int) -> some View {
        let count = max(0, goal)
        let rows = stride(from: 0, to: count, by: Self.circlesPerRow).map { start in
            start..<min(count, start + Self.circlesPerRow)
        }

        return GeometryReader { proxy in
            let diameter = circleDiameter(for: proxy.size.width)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.lowerBound) { range in
                    HStack(spacing: 0) {
                        ForEach(Array(range.enumerated()), id: \.element) { offset, index in
                            if offset > 0 {
                                Spacer(minLength: Self.minimumSpacing)
                            }

                            circle(checked: index < done, diameter: diameter)
                        }
                    }
                }
            }
        }
        .frame(height: rowsHeight(rows: rows.count))
    }

    private func circleDiameter(for width: CGFloat) -> CGFloat {
        let gaps = CGFloat(Self.circlesPerRow - 1) * Self.minimumSpacing
        let fitting = (width - gaps) / CGFloat(Self.circlesPerRow)

        return max(0, min(Self.maximumDiameter, fitting))
    }

    /// Reserves the rows at the largest circle size; narrower columns leave a little air below.
    private func rowsHeight(rows: Int) -> CGFloat {
        let rows = CGFloat(max(1, rows))

        return rows * Self.maximumDiameter + (rows - 1) * 8
    }

    private func circle(checked: Bool, diameter: CGFloat) -> some View {
        Circle()
            .fill(checked ? TherapyPalette.success : TherapyPalette.actionMuted)
            .overlay {
                if checked {
                    Image(systemName: "checkmark")
                        .typography(size: diameter * 0.45, weight: .bold)
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: diameter, height: diameter)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: checked)
    }
}

#Preview("Set progress") {
    VStack(alignment: .leading, spacing: 40) {
        TMTherapySetProgress(setNumber: 1, setTotal: 3, completed: 5, goal: 12) {
            Text("session.setNumber \($0)")
        }

        TMTherapySetProgress(setNumber: 2, setTotal: 2, completed: 2, goal: 5) {
            Text("session.setNumber \($0)")
        }

        TMTherapySetProgress(setNumber: 1, setTotal: 1, completed: 0, goal: 1) {
            Text("session.setNumber \($0)")
        }
    }
    .frame(width: 440)
    .padding(24)
    .background(TherapyPalette.canvas)
}
