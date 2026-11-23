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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    Text(date, format: .dateTime.weekday(.abbreviated))
                        .typography(size: 20, weight: .regular, relativeTo: .body)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
            }

            HStack(spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    dayButton(date)
                }
            }
            .frame(height: 64, alignment: .top)
        }
        .foregroundStyle(TherapyPalette.brandInk)
        .contentShape(Rectangle())
        .simultaneousGesture(weekSwipeGesture)
        .accessibilityAction(named: Text("home.calendar.previousWeek")) {
            onMoveWeek(-1)
        }
        .accessibilityAction(named: Text("home.calendar.nextWeek")) {
            onMoveWeek(1)
        }
    }

    /// A horizontal swipe changes the visible seven-day page without stealing ordinary taps
    /// from the individual date buttons.
    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height

                guard abs(horizontalDistance) > abs(verticalDistance),
                      abs(horizontalDistance) >= 50 else {
                    return
                }

                onMoveWeek(horizontalDistance < 0 ? 1 : -1)
            }
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
