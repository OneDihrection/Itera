//
//  FingerSessionCompleteView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

/// The closing page after the feeling question: thanks, and a way to see progress.
struct FingerSessionCompleteView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    private var summary: FingerSessionSummary? {
        dependencies.session?.finalSummary
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(spacing: 18) {
                TherapyCompletionMark()
                Text(completed ? "done.title" : "done.titlePartial")
                    .typography(size: 52, weight: .bold, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                message
                    .typography(size: 26, weight: .regular, relativeTo: .title3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 40)

            TherapyButton(title: closingTitle, pill: true, action: close)
                .frame(maxWidth: 360)

            Spacer(minLength: 40)
        }
        .foregroundStyle(TherapyPalette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
        .environment(\.locale, dependencies.session?.sessionLanguage.locale ?? AppLanguage.selected.locale)
        .interactiveDismissDisabled()
    }

    private var completed: Bool {
        summary?.outcome == .completed
    }

    private var message: Text {
        guard completed else {
            return Text("done.messagePartial")
        }

        switch PartOfDay(date: summary?.ended ?? Date()) {
        case .morning:
            return Text("done.message.morning")
        case .afternoon:
            return Text("done.message.afternoon")
        case .evening:
            return Text("done.message.evening")
        case .night:
            return Text("done.message.night")
        }
    }

    /// While today's plan runs, this page leads on to the next exercise instead of Progress.
    private var closingTitle: LocalizedStringKey {
        dependencies.dailyPlan.isRunning ? "plan.nextContinue" : "done.viewProgress"
    }

    private func close() {
        guard !dependencies.dailyPlan.isRunning else {
            dependencies.dailyPlan.finish(completed: completed, router: router)
            return
        }

        router.dismissFullScreenCover()
        router.push(.reports)
    }
}

/// Indonesian distinguishes pagi, siang, sore and malam; English uses the same four parts.
private enum PartOfDay {
    case morning, afternoon, evening, night

    init(date: Date, calendar: Calendar = .current) {
        switch calendar.component(.hour, from: date) {
        case 4..<11:
            self = .morning
        case 11..<15:
            self = .afternoon
        case 15..<18:
            self = .evening
        default:
            self = .night
        }
    }
}
