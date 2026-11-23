//
//  HomeHeaderSubtitle.swift
//  Tuntun
//
//  Created by Gracia A on 21/11/2026.
//

import SwiftUI

/// The reusable supporting sentence directly below a Beranda title.
struct TMHomeHeaderSubtitle: View {
    let text: Text
    var color: Color = TherapyPalette.ink

    var body: some View {
        text
            .typography(size: 24, weight: .medium, relativeTo: .title3)
            .tracking(0.6)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
