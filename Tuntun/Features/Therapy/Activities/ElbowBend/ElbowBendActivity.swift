//
//  ElbowBendActivity.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

struct ElbowBendActivity: TherapyActivity {
    private var movement: MovementActivity
    /// - Parameter scriptedGuidance: the Indonesian script's 3 s holds and 5 s later-set countdown.
    init(configuration: SessionActivity, scriptedGuidance: Bool = false) {
        movement = MovementActivity(configuration: configuration, scriptedGuidance: scriptedGuidance)
    }
    var presentation: ActivityPresentation { movement.presentation }
    mutating func handle(_ event: ActivityEvent) -> ActivityTransition { movement.handle(event) }
}
