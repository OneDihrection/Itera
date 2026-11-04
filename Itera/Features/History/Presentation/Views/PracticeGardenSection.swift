//
//  PracticeGardenSection.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 03/11/2026.
//

import SwiftUI

struct PracticeGardenSection: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TherapyCard {
            VStack(alignment: .leading, spacing: 22) {
                Label("garden.title", systemImage: "leaf.fill")
                    .typography(.title)
                    .foregroundStyle(TherapyPalette.primary)
                Text("garden.description").typography(.body)
                    .foregroundStyle(TherapyPalette.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 20)], spacing: 24) {
                    ForEach(Array(FingerExercise.allCases.enumerated()), id: \.element) { index, exercise in
                        TherapyGardenBed(
                            title: LocalizedStringKey("garden.activity." + exercise.rawValue),
                            flowers: dependencies.progress.progress.gardenSets[exercise, default: 0],
                            hasSeed: dependencies.progress.progress.movements.contains(exercise),
                            variation: index
                        )
                    }
                }
                if !decorations.isEmpty {
                    Text("garden.decorations").typography(.headline)
                    HStack(spacing: 18) {
                        ForEach(decorations) { badge in
                            Button {
                                router.presentSheet(.achievement(badge.id))
                            } label: {
                                TherapyBadge(symbol: badge.symbol, value: String(badge.target), earned: true, size: 68)
                            }
                            .accessibilityLabel(dependencies.progress.title(for: badge))
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .buttonStyle(TherapySoundButtonStyle())
                }
                if dependencies.progress.progress.sets == 0 {
                    Text("garden.empty").typography(.body)
                }
            }
        }
    }

    private var decorations: [PracticeAchievement] {
        Array(PracticeAchievement.catalog.filter { dependencies.progress.award(for: $0) != nil }.prefix(4))
    }

}
