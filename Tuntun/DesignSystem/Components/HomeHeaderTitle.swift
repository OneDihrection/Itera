//
//  HomeHeaderTitle.swift
//  Tuntun
//
//  Created by Gracia A on 21/11/2026.
//

import SwiftUI

/// The reusable 40-point title used by Beranda's selected date and empty state.
struct TMHomeHeaderTitle: View {
    let text: Text
    var color: Color = TherapyPalette.ink

    var body: some View {
        text
            .typography(size: 40, weight: .bold, relativeTo: .largeTitle)
            .tracking(0.6)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
