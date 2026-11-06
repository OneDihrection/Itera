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
    /// The number currently shown in a hold bubble. Spoken only while nothing else is,
    /// never queued, and a newer number replaces one still playing, so what is heard
    /// always matches the bubble without cutting off an instruction.
    case holdSecond(Int)
    case target
    case towelGrab
    case towelFold
    case towelCompleted
    case closing(completed: Bool)
    case guidance(prefix: SessionAudioCue, key: String)
}
