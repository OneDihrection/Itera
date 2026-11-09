//
//  TherapyProgressSummary.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

// MARK: - Week summary

/// A black headline band above a row of seven day cells, inside one outlined container.
///
/// The caller supplies already-formatted text; this view decides nothing about history.
struct TMTherapyWeekSummary: View {
    struct Day: Identifiable {
        let id: Date
        let label: String
        let caption: LocalizedStringKey
        let done: Bool
    }

    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let days: [Day]

    var body: some View {
        VStack(spacing: 0) {
            header
            dayRow
        }
        .background(TherapyPalette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(TherapyPalette.outline, lineWidth: 1.5)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .typography(size: 40, weight: .bold, relativeTo: .largeTitle)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .typography(size: 24, weight: .regular, relativeTo: .title3)
        }
        .foregroundStyle(TherapyPalette.onHero)
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TherapyPalette.heroCard)
    }

    private var dayRow: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(days) { day in
                VStack(spacing: 10) {
                    Text(verbatim: day.label)
                        .typography(size: 20, weight: .semiBold, relativeTo: .headline)
                    dayMark(done: day.done)
                    Text(day.caption)
                        .typography(size: 20, weight: day.done ? .semiBold : .regular, relativeTo: .subheadline)
                        .foregroundStyle(day.done ? TherapyPalette.ink : TherapyPalette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func dayMark(done: Bool) -> some View {
        if done {
            Image(systemName: "checkmark")
                .typography(size: 15, weight: .bold)
                .frame(width: 32, height: 32)
                .background(TherapyPalette.panel, in: Circle())
        } else {
            Image(systemName: "minus")
                .typography(size: 15, weight: .regular)
                .foregroundStyle(TherapyPalette.muted)
                .frame(width: 32, height: 32)
        }
    }
}

// MARK: - Challenge card

/// The current goal: name, progress text, a status pill and a segmented progress bar.
struct TMTherapyChallengeCard: View {
    let title: LocalizedStringKey
    let progressText: LocalizedStringKey
    let status: LocalizedStringKey
    let targetText: LocalizedStringKey
    let completed: Int
    let total: Int

    /// Above this many steps the bar is drawn continuously, so segments stay legible.
    private static let maximumSegments = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text(title)
                    .typography(size: 32, weight: .semiBold, relativeTo: .title)
                Spacer(minLength: 12)
                Text(status)
                    .typography(size: 20, weight: .medium, relativeTo: .subheadline)
                    .foregroundStyle(TherapyPalette.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(TherapyPalette.canvas, in: Capsule())
            }
            HStack(alignment: .lastTextBaseline) {
                Text(progressText)
                    .typography(size: 34, weight: .bold, relativeTo: .title)
                Spacer(minLength: 12)
                Text(targetText)
                    .typography(size: 20, weight: .regular, relativeTo: .subheadline)
                    .multilineTextAlignment(.trailing)
            }
            bar
        }
        .foregroundStyle(TherapyPalette.challengeInk)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TherapyPalette.challengeFill, in: RoundedRectangle(cornerRadius: 30))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var bar: some View {
        let done = min(max(0, completed), total)

        if total <= Self.maximumSegments {
            HStack(spacing: 8) {
                ForEach(0..<max(1, total), id: \.self) { index in
                    Capsule()
                        .fill(index < done ? TherapyPalette.challengeInk : TherapyPalette.outline)
                        .frame(height: 8)
                }
            }
        } else {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(TherapyPalette.outline)
                    Capsule()
                        .fill(TherapyPalette.challengeInk)
                        .frame(width: geometry.size.width * Double(done) / Double(max(1, total)))
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Achievement row

/// A compact earned-badge summary: medal icon, title, subtitle and a trailing count.
struct TMTherapyAchievementRow: View {
    let title: String
    let subtitle: String
    let count: LocalizedStringKey
    var symbol = "medal"

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: symbol)
                .typography(size: 30, weight: .regular)
                .foregroundStyle(TherapyPalette.challengeInk.opacity(0.7))
                .frame(width: 76, height: 76)
                .background(TherapyPalette.challengeFill, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title)
                    .typography(size: 24, weight: .semiBold, relativeTo: .headline)
                Text(verbatim: subtitle)
                    .typography(size: 20, weight: .regular, relativeTo: .subheadline)
                    .foregroundStyle(TherapyPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(count)
                .typography(size: 20, weight: .regular, relativeTo: .subheadline)
                .foregroundStyle(TherapyPalette.muted)
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TherapyPalette.canvas, in: RoundedRectangle(cornerRadius: 30))
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(TherapyPalette.outline, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }
}
