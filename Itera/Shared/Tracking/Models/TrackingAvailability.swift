//
//  TrackingAvailability.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum TrackingAvailability {
    case waiting
    case ready(UUID)
    case discontinuity
}

