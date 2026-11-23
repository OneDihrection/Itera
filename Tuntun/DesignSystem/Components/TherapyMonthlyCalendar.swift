//
//  TherapyMonthlyCalendar.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 21/11/2026.
//

import SwiftUI

/// How much of a day's practice was done, as the calendar draws it.
enum TMCalendarDayStatus: Equatable {
    /// Nothing practised: the plain number.
    case none
    /// Practised without finishing everything: a dotted yellow ring.
    case partial
    /// Everything finished: a filled yellow circle.
    case completed
}

/// A month of practice: the month title between previous and next chevrons, a weekday header,
/// one tappable number per day and a legend.
///
/// Days are coloured from `statuses`, keyed by the start of each day in the environment's
/// calendar. Today carries a small yellow dot; future days are greyed and cannot be tapped. The
/// caller owns the shown month, what each status means and where a tap leads.
struct TMMonthlyCalendar: View {
    /// Any date inside the month to show.
    let month: Date
    let today: Date
    let statuses: [Date: TMCalendarDayStatus]
    let canShowPreviousMonth: Bool
    let canShowNextMonth: Bool
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onSelectDay: (Date) -> Void

    @Environment(\.calendar) private var environmentCalendar
    @Environment(\.locale) private var locale

    /// Day circles are 52 pt, above the 44 pt minimum touch target.
    private let dayDiameter: CGFloat = 52
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 7
    )

    var body: some View {
        TMTherapyCard(color: TherapyPalette.canvas, padding: 32) {
            VStack(spacing: 24) {
                monthHeader

                LazyVGrid(columns: columns, spacing: 14) {
                    weekdayHeader
                    dayCells
                }

                legend
            }
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            chevron(
                symbol: "chevron.left",
                label: "calendar.previousMonth",
                enabled: canShowPreviousMonth,
                action: onPreviousMonth
            )

            Spacer(minLength: 12)

            Text(month, format: .dateTime.month(.wide).year().locale(locale))
                .typography(size: 26, weight: .semiBold, relativeTo: .title2)
                .foregroundStyle(TherapyPalette.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            chevron(
                symbol: "chevron.right",
                label: "calendar.nextMonth",
                enabled: canShowNextMonth,
                action: onNextMonth
            )
        }
    }

    private func chevron(
        symbol: String,
        label: LocalizedStringKey,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .typography(size: 24, weight: .semiBold, relativeTo: .title2)
                .foregroundStyle(enabled ? TherapyPalette.ink : TherapyPalette.planTrack)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var weekdayHeader: some View {
        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
            Text(verbatim: symbol)
                .typography(.subheadline)
                .foregroundStyle(TherapyPalette.ink)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Days

    @ViewBuilder
    private var dayCells: some View {
        ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
            if let day {
                dayCell(day)
            } else {
                Color.clear
                    .frame(height: dayDiameter)
                    .accessibilityHidden(true)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isFuture = day > calendar.startOfDay(for: today)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let status = statuses[day] ?? .none

        return Button {
            onSelectDay(day)
        } label: {
            TMCalendarDayMark(
                number: calendar.component(.day, from: day),
                status: isFuture ? .none : status,
                isToday: isToday,
                isFuture: isFuture,
                diameter: dayDiameter
            )
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .disabled(isFuture)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide).locale(locale)))
        .accessibilityValue(accessibilityValue(status: status, isToday: isToday))
    }

    private func accessibilityValue(status: TMCalendarDayStatus, isToday: Bool) -> Text {
        let statusText: Text? = switch status {
        case .none:
            nil
        case .partial:
            Text("calendar.legend.partial")
        case .completed:
            Text("calendar.legend.completed")
        }

        guard isToday else {
            return statusText ?? Text(verbatim: "")
        }

        guard let statusText else {
            return Text("calendar.today")
        }

        return Text("calendar.today") + Text(verbatim: ", ") + statusText
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 28) {
            legendItem(status: .completed, title: "calendar.legend.completed")
            legendItem(status: .partial, title: "calendar.legend.partial")
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(status: TMCalendarDayStatus, title: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            TMCalendarStatusShape(status: status, lineWidth: 2.5)
                .frame(width: 18, height: 18)

            Text(title)
                .typography(.subheadline)
                .foregroundStyle(TherapyPalette.muted)
        }
    }

    // MARK: - Calendar maths

    /// The environment's calendar speaking the app's language, so weekday and month names follow
    /// the selected language.
    private var calendar: Calendar {
        var calendar = environmentCalendar
        calendar.locale = locale
        return calendar
    }

    /// Short weekday names starting on the calendar's first weekday ("Min" … "Sab" in Indonesian).
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1

        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month's days at the start of each day, after blanks that align day 1 with its weekday.
    private var monthCells: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: month),
            let dayRange = calendar.range(of: .day, in: .month, for: month)
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        let days = (0..<dayRange.count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start)
        }

        return Array(repeating: nil, count: leadingBlanks) + days.map { Optional($0) }
    }
}

// MARK: - Day mark

/// One day's number with its status drawn around it.
private struct TMCalendarDayMark: View {
    let number: Int
    let status: TMCalendarDayStatus
    let isToday: Bool
    let isFuture: Bool
    let diameter: CGFloat

    private let todayDotDiameter: CGFloat = 7

    /// The today dot's centre sits 8 pt below the circle's edge, so it never touches a ring.
    private var todayDotOffset: CGFloat {
        diameter / 2 + 8
    }

    var body: some View {
        ZStack {
            TMCalendarStatusShape(status: status, lineWidth: 3)
                .frame(width: diameter, height: diameter)

            Text(verbatim: "\(number)")
                .typography(
                    size: 22,
                    weight: isToday ? .bold : .regular,
                    relativeTo: .body
                )
                .foregroundStyle(numberColor)

            if isToday {
                Circle()
                    .fill(TherapyPalette.brand)
                    .frame(width: todayDotDiameter, height: todayDotDiameter)
                    .offset(y: todayDotOffset)
            }
        }
        .frame(maxWidth: .infinity)
        // Tall enough for the today dot below the circle.
        .frame(height: (todayDotOffset + todayDotDiameter / 2) * 2)
        .contentShape(Rectangle())
    }

    private var numberColor: Color {
        if isFuture {
            return TherapyPalette.planTrack
        }

        if status == .completed {
            return TherapyPalette.onBrand
        }

        return TherapyPalette.ink
    }
}

/// The completed circle or partial dotted ring, shared by the day marks and the legend.
private struct TMCalendarStatusShape: View {
    let status: TMCalendarDayStatus
    let lineWidth: CGFloat

    var body: some View {
        switch status {
        case .none:
            Color.clear
        case .completed:
            Circle()
                .fill(TherapyPalette.brand)
        case .partial:
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(
                    TherapyPalette.brand,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        dash: [0.1, lineWidth * 2]
                    )
                )
        }
    }
}

// MARK: - Previews

#if DEBUG
private struct TMMonthlyCalendarPreview: View {
    @State private var month = Date.now

    private var statuses: [Date: TMCalendarDayStatus] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var statuses: [Date: TMCalendarDayStatus] = [:]

        for offset in [1, 3, 8, 10] {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                statuses[day] = .completed
            }
        }

        for offset in [2, 6] {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                statuses[day] = .partial
            }
        }

        return statuses
    }

    var body: some View {
        TMMonthlyCalendar(
            month: month,
            today: .now,
            statuses: statuses,
            canShowPreviousMonth: true,
            canShowNextMonth: !Calendar.current.isDate(month, equalTo: .now, toGranularity: .month),
            onPreviousMonth: {
                month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
            },
            onNextMonth: {
                month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
            },
            onSelectDay: { _ in }
        )
        .padding(32)
        .background(TherapyPalette.canvas)
    }
}

#Preview("Monthly calendar") {
    TMMonthlyCalendarPreview()
        .environment(\.locale, Locale(identifier: "id"))
}
#endif
