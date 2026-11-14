//
//  ArmRaiseActivity.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

struct ArmRaiseActivity: TherapyActivity {
    private var movement: MovementActivity
    init(configuration: SessionActivity, scriptedGuidance: Bool = false) {
        movement = MovementActivity(configuration: configuration, scriptedGuidance: scriptedGuidance)
    }
    var presentation: ActivityPresentation { movement.presentation }
    mutating func handle(_ event: ActivityEvent) -> ActivityTransition { movement.handle(event) }
}
