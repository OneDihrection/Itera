//
//  AppRoute.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum AppRoute: Hashable {
    case home
    case routineConfiguration
    case exercisePicker
    case therapySession
}

struct RoutePresentation: Identifiable {
    let id = UUID()
    let route: AppRoute
}
