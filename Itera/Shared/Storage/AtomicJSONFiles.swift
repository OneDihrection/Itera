//
//  AtomicJSONFiles.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

enum AtomicJSONFiles {
    static func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    /// Call from the owning repository actor, never during a render or inference callback.
    static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
