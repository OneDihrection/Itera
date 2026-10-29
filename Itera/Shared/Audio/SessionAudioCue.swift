//
//  SessionAudioCue.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

/// Typed requests keep accepted-work feedback separate from patient instructions.
indirect enum SessionAudioCue {
    case count(Int)
    case countdown(Int)
    case target
    case closing(completed: Bool)
    case guidance(prefix: SessionAudioCue, key: String)
}
