//
//  TherapyAchievementShareSheet.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 02/11/2026.
//

import SwiftUI
import UIKit

/// Exports a badge card on demand; the caller owns presentation and dismissal.
struct TMTherapyAchievementShareSheet: UIViewControllerRepresentable {
    let symbol: String
    let value: String
    let title: String
    let earnedDate: Date
    let caption: String
    let locale: Locale
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let card = TMTherapyAchievementShareCard(
            symbol: symbol,
            value: value,
            title: title,
            earnedDate: earnedDate
        )
        .environment(\.locale, locale)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = true

        var items: [Any] = [caption]
        if let image = renderer.uiImage {
            items.append(image)
        }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            Task { @MainActor in
                onComplete(error != nil)
            }
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct TMTherapyAchievementShareCard: View {
    let symbol: String
    let value: String
    let title: String
    let earnedDate: Date

    var body: some View {
        VStack(spacing: 24) {
            Text(verbatim: "Itera")
                .typography(.title2)
                .foregroundStyle(TherapyPalette.primary)
            TMTherapyBadge(symbol: symbol, value: value, earned: true, size: 200)
            Text(verbatim: title)
                .typography(.largeTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                Text("achievement.earned").typography(.headline)
                Text(earnedDate, format: .dateTime.day().month(.wide).year())
                    .typography(.body)
            }
            Text("achievement.encouragement")
                .typography(.title2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(44)
        .frame(width: 600)
        .background(TherapyPalette.cream)
    }
}
