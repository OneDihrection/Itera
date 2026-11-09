//
//  TherapyHandCursor.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import SwiftUI

/// The patient's tracked hand drawn over the camera: an open hand on a dark backing while open, and a
/// pinching hand on a solid mint backing once `closed` (thumb and index together), so the change
/// reads without watching the icon. A holding hand gets a thicker mint outline.
///
/// It is a 68 pt marker (about 60 pt while pinched) so it stays readable on any video. The caller places it
/// and supplies the state; it does not interpret tracking.
struct TherapyHandCursor: View {
    let closed: Bool
    let holding: Bool

    var body: some View {
        Image(systemName: closed ? "hand.pinch.fill" : "hand.raised.fingers.spread")
            .typography(size: 34, weight: .bold)
            .foregroundStyle(closed ? TherapyPalette.calmUnderlay : .white)
            .frame(width: 68, height: 68)
            .background(closed ? TherapyPalette.guidanceBlue : TherapyPalette.calmUnderlay, in: Circle())
            .overlay(
                Circle().stroke(holding ? TherapyPalette.guidanceBlue : .white, lineWidth: holding ? 6 : 3)
            )
            .scaleEffect(closed ? 0.88 : 1)
            .shadow(color: .black.opacity(0.4), radius: 4)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Hand cursor") {
    HStack(spacing: 30) {
        TherapyHandCursor(closed: false, holding: false)
        TherapyHandCursor(closed: true, holding: false)
        TherapyHandCursor(closed: true, holding: true)
    }
    .padding(40)
    .background(.gray)
}
#endif
