//
//  TherapyFoldPanel.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import SwiftUI

/// A value-driven pair of cloth-like panels. The caller owns folding and acceptance rules.
struct TMTherapyFoldPanel: View {
    let progress: Double
    let horizontal: Bool
    let layers: Int
    var fillOpacity = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let halfWidth = horizontal ? width / 2 : width
            let halfHeight = horizontal ? height : height / 2
            ZStack(alignment: .topLeading) {
                face(back: false)
                    .frame(width: halfWidth, height: halfHeight)
                face(back: progress > 0.5)
                    .frame(width: halfWidth, height: halfHeight)
                    .rotation3DEffect(
                        .degrees(reduceMotion ? 0 : progress * 180),
                        axis: (x: horizontal ? 0 : 1, y: horizontal ? -1 : 0, z: 0),
                        anchor: horizontal ? .leading : .top,
                        perspective: 0.35
                    )
                    .offset(
                        x: horizontal ? halfWidth * (reduceMotion ? 1 - progress * 2 : 1) : 0,
                        y: horizontal ? 0 : halfHeight * (reduceMotion ? 1 - progress * 2 : 1)
                    )
            }
            .shadow(color: .black.opacity(0.2), radius: 5, y: CGFloat(min(8, layers)))
        }
        .accessibilityHidden(true)
    }

    private func face(back: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(back ? Color(red: 0.65, green: 0.78, blue: 0.72) : Color(red: 0.88, green: 0.94, blue: 0.85))
            .opacity(min(1, max(0, fillOpacity)))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .padding(9)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.black.opacity(0.7), lineWidth: 2)
            }
    }
}
