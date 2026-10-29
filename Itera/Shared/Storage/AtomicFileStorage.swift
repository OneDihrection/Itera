//
//  AtomicFileStorage.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

/// File mechanics run on the repository's actor; callers retain schema and recovery ownership.
struct AtomicFileStorage {
    func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
