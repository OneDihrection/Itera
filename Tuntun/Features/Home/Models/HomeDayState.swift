//
//  HomeDayState.swift
//  Tuntun
//
//  Created by Gracia A on 21/11/2026.
//

import Foundation

/// The presentation state of the date selected in Beranda's weekly calendar.
enum HomeDayState: Equatable {
    /// A previous or current plan whose exercises are all complete.
    case completed
    /// Today's plan, which can be started or continued.
    case current
    /// Tomorrow's prescribed plan, visible now but not startable yet.
    case upcoming
    /// A selectable date with no prescribed exercises.
    case noSchedule
}
