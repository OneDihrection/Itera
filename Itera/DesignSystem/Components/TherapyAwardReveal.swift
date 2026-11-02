//
//  TherapyAwardReveal.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

/// Bounded entrance and confetti, restarted only when the caller changes award identity.
struct TherapyAwardReveal: View {
    let symbol: String
    let value: String
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            if animated && !reduceMotion {
                TherapyCelebration()
            }
            TherapyBadge(symbol: symbol, value: value, earned: true, size: 200)
                .scaleEffect(revealed || reduceMotion || !animated ? 1 : 0.65)
                .rotationEffect(.degrees(revealed || reduceMotion || !animated ? 0 : -12))
        }
        .frame(height: 260)
        .onAppear {
            withAnimation(reduceMotion || !animated ? nil : .spring(duration: 0.6, bounce: 0.3)) {
                revealed = true
            }
        }
    }
}
