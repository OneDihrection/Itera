//
//  DailyPlanCalendar.swift
//  Tuntun
//
//  Created by Gracia A on 21/11/2026.
//

import SwiftUI

/// The seven-day selector shown above Beranda's daily plan.
struct TMDailyPlanCalendar: View {
    let dates: [Date]
    let selectedDate: Date
    let onSelect: (Date) -> Void
    let onMoveWeek: (Int) -> Void

    @Environment(\.calendar) private var calendar
    @State private var visiblePage: Int? = 0
    @State private var isRecentering = false

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            dateScroller
        }
        .frame(height: 112)
        .foregroundStyle(TherapyPalette.brandInk)
        .accessibilityAction(named: Text("home.calendar.previousWeek")) {
            onMoveWeek(-1)
        }
        .accessibilityAction(named: Text("home.calendar.nextWeek")) {
            onMoveWeek(1)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(dates.prefix(7), id: \.self) { date in
                Text(date, format: .dateTime.weekday(.abbreviated))
                    .typography(size: 20, weight: .regular, relativeTo: .body)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .frame(height: 48)
    }

    private var dateScroller: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(-1...1, id: \.self) { pageOffset in
                    datePage(offset: pageOffset)
                        .containerRelativeFrame(.horizontal)
                        .id(pageOffset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .defaultScrollAnchor(.center)
        .scrollPosition(id: $visiblePage)
        .frame(height: 64)
        .onChange(of: visiblePage) { _, page in
            guard let page else {
                return
            }

            if page == 0 {
                isRecentering = false
                return
            }

            guard !isRecentering else {
                return
            }

            isRecentering = true
            onMoveWeek(page)

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visiblePage = 0
            }
        }
    }

    private func datePage(offset: Int) -> some View {
        let pageDates = dates.compactMap { date in
            calendar.date(byAdding: .day, value: offset * 7, to: date)
        }

        return HStack(spacing: 0) {
            ForEach(pageDates, id: \.self) { date in
                dayButton(date)
            }
        }
        .frame(height: 64, alignment: .top)
    }

    private func dayButton(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)

        return Button {
            onSelect(date)
        } label: {
            Text(date, format: .dateTime.day())
                .typography(size: 20, weight: .bold, relativeTo: .body)
                .foregroundStyle(
                    isToday && !isSelected
                        ? TherapyPalette.planMarker
                        : TherapyPalette.brandInk
                )
                .frame(width: 48, height: 48)
                .background(isSelected ? TherapyPalette.brand : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .top)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
