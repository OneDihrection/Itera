//
//  Component.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

/// The shared dependency-injection base. Every feature's component subclasses it, holding the
/// dependency its parent supplied and exposing what that feature's builder needs.
///
/// A parent component conforms to its children's dependency protocols so it can seed their
/// components; nothing resolves dependencies at runtime.
@MainActor
class Component<Dependency> {
    let dependency: Dependency

    init(with dependency: Dependency) {
        self.dependency = dependency
    }
}
