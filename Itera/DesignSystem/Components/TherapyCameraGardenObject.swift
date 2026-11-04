//
//  TherapyCameraGardenObject.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 03/11/2026.
//

import SwiftUI

/// Transparent, value-driven camera artwork. It never accepts poses or awards work.
struct TherapyCameraGardenObject: View {
    let style: GardenActivityStyle
    let anchor: CGPoint
    let tether: CGPoint
    let secondTether: CGPoint?
    let planter: CGPoint
    let depositOrigin: CGPoint
    let pose: Double
    let secured: Bool
    let waiting: Bool
    let collected: Int
    let depositID: Int
    let paused: Bool
    let showsObject: Bool
    var size: CGFloat = 100
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastDeposit: Int
    @State private var flightStart = CGPoint.zero
    @State private var flightEnd = CGPoint.zero
    @State private var flightProgress = 0.0
    @State private var flying = false

    init(style: GardenActivityStyle, anchor: CGPoint, tether: CGPoint, planter: CGPoint,
         depositOrigin: CGPoint, pose: Double, secured: Bool, waiting: Bool,
         collected: Int, depositID: Int, paused: Bool, showsObject: Bool = true,
         size: CGFloat = 100, animated: Bool = true, secondTether: CGPoint? = nil) {
        self.style = style
        self.anchor = anchor
        self.tether = tether
        self.secondTether = secondTether
        self.planter = planter
        self.depositOrigin = depositOrigin
        self.pose = pose
        self.secured = secured
        self.waiting = waiting
        self.collected = collected
        self.depositID = depositID
        self.paused = paused
        self.showsObject = showsObject
        self.size = size
        self.animated = animated
        _lastDeposit = State(initialValue: depositID)
    }

    private var amount: Double { max(0, min(1, pose)) }
    private var moves: Bool { animated && !reduceMotion && !paused && scenePhase == .active }
    private var flightKey: String { "\(depositID)-\(moves)" }

    var body: some View {
        ZStack {
            if showsObject && !waiting && style != .petals && style != .light {
                Path { path in
                    path.move(to: tether)
                    path.addLine(to: anchor)
                    if let secondTether {
                        path.move(to: secondTether)
                        path.addLine(to: anchor)
                    }
                }
                .stroke(TherapyPalette.tertiary.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 6]))
            }
            object
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    if secured && !waiting {
                        Image(systemName: "checkmark.circle.fill").typography(.title2)
                            .foregroundStyle(TherapyPalette.primary)
                            .background(TherapyPalette.surface, in: Circle())
                    }
                    if waiting {
                        Image(systemName: "pause.circle.fill").typography(.title2)
                            .foregroundStyle(TherapyPalette.primary)
                            .background(TherapyPalette.surface, in: Circle())
                    }
                }
                .opacity(showsObject ? (waiting ? 0.55 : 1) : 0)
                .position(anchor)
                .animation(moves ? .easeOut(duration: 0.2) : nil, value: anchor)
                .animation(moves ? .easeOut(duration: 0.18) : nil, value: amount)
            planterView.position(planter)
            if flying {
                flightArtwork
                    .foregroundStyle(TherapyPalette.tertiary)
                    .shadow(color: TherapyPalette.primary.opacity(0.5), radius: 5)
                    .scaleEffect(1 - flightProgress * 0.55)
                    .position(
                        x: flightStart.x + (flightEnd.x - flightStart.x) * flightProgress,
                        y: flightStart.y + (flightEnd.y - flightStart.y) * flightProgress - sin(flightProgress * .pi) * 70
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: flightKey) {
            guard lastDeposit != depositID else {
                return
            }
            lastDeposit = depositID
            guard moves else {
                return
            }
            flightStart = depositOrigin
            flightEnd = style == .seeds || style == .butterfly
                ? CGPoint(x: planter.x, y: planter.y - 50) : planter
            flightProgress = 0
            flying = true
            defer { flying = false }
            withAnimation(.easeInOut(duration: 0.9)) {
                flightProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(950))
        }
    }

    @ViewBuilder
    private var object: some View {
        switch style {
        case .light:
            ZStack {
                Circle().fill(TherapyPalette.tertiary.opacity(0.06 + amount * 0.1))
                Circle().stroke(TherapyPalette.tertiary.opacity(0.65), lineWidth: 2)
                    .padding(size * 0.18)
                ForEach(0..<8) { index in
                    let angle = Double(index) * .pi / 4
                    let radius = size * (0.45 - amount * 0.15)
                    Circle().fill(TherapyPalette.tertiary)
                        .frame(width: 6, height: 6)
                        .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                }
            }
        case .butterfly:
            leafShelter
        case .seeds:
            TherapyGardenSeed(squeeze: amount, secured: secured)
        case .petals:
            ZStack {
                ForEach(0..<6) { index in
                    Ellipse().stroke(TherapyPalette.tertiary.opacity(0.65), lineWidth: 2)
                        .background(Ellipse().fill(TherapyPalette.secondary.opacity(0.08)))
                        .frame(width: size * 0.25, height: size * 0.4)
                        .offset(y: -size * (0.12 + amount * 0.18))
                        .rotationEffect(.degrees(Double(index) * 60))
                }
            }
        case .firefly:
            ZStack {
                Circle().fill(TherapyPalette.tertiary.opacity(0.1 + amount * 0.12))
                Ellipse().fill(TherapyPalette.surface.opacity(0.75))
                    .frame(width: 22, height: 10).rotationEffect(.degrees(-25 - amount * 20))
                    .offset(x: -13, y: -7)
                Ellipse().fill(TherapyPalette.surface.opacity(0.75))
                    .frame(width: 22, height: 10).rotationEffect(.degrees(25 + amount * 20))
                    .offset(x: 13, y: -7)
                Capsule().fill(TherapyPalette.tertiary.gradient)
                    .frame(width: 17, height: 28)
                    .shadow(color: TherapyPalette.tertiary, radius: 4 + amount * 12)
            }
        }
    }

    @ViewBuilder
    private var flightArtwork: some View {
        if style == .seeds {
            TherapyGardenSeed(squeeze: 0, secured: false)
        } else if style == .butterfly {
            Image("garden-butterfly")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .rotationEffect(.degrees(-18 + flightProgress * 30))
                .scaleEffect(x: 0.6 + abs(sin(flightProgress * .pi * 4)) * 0.4)
        } else if style == .petals {
            TherapyGardenFlower().frame(width: 54, height: 68)
        } else {
            Image(systemName: style == .light ? "sparkles" : "sparkle")
                .typography(size: 34, weight: .bold)
        }
    }

    private var leafShelter: some View {
        ZStack {
            Image("garden-butterfly")
                .resizable()
                .scaledToFit()
                .padding(size * 0.15)
                .scaleEffect(x: 0.3 + (1 - amount) * 0.7, y: 0.8)
                .opacity(secured ? 1 - amount : 0)
                .offset(y: -size * 0.12)
            Image("garden-leaf")
                .resizable()
                .scaledToFit()
                .rotation3DEffect(.degrees(amount * 50), axis: (x: 0, y: 1, z: 0))
                .rotationEffect(.degrees(amount * -18))
                .scaleEffect(x: 1 - amount * 0.25, y: 1)
                .offset(y: secured ? (1 - amount) * size * 0.2 : 0)
        }
    }

    @ViewBuilder
    private var planterView: some View {
        if style == .seeds || style == .butterfly {
            VStack(spacing: 2) {
                ZStack(alignment: .bottom) {
                    if collected > 0 {
                        Image(style == .butterfly ? "garden-butterfly" : "garden-leaf")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 44)
                            .offset(y: -36)
                    }
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4, bottomLeadingRadius: 18,
                        bottomTrailingRadius: 18, topTrailingRadius: 4
                    )
                    .fill(TherapyPalette.tertiary)
                    .frame(width: 80, height: 42)
                    Ellipse().fill(TherapyPalette.ink.opacity(0.85))
                        .frame(width: 80, height: 14)
                        .offset(y: -34)
                }
                .frame(height: 72)
                Text("garden.collected \(collected)")
                    .typography(.headline)
                    .foregroundStyle(TherapyPalette.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(TherapyPalette.surface.opacity(0.95), in: Capsule())
            }
            .offset(y: -22)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill").typography(.title2)
                Text("garden.collected \(collected)").typography(.headline)
            }
            .foregroundStyle(TherapyPalette.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(TherapyPalette.surface.opacity(0.9), in: UnevenRoundedRectangle(
                topLeadingRadius: 10, bottomLeadingRadius: 26,
                bottomTrailingRadius: 26, topTrailingRadius: 10
            ))
        }
    }
}

private struct TherapyGardenSeed: View {
    let squeeze: Double
    let secured: Bool

    var body: some View {
        Image("garden-seed")
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 32)
            .scaleEffect(x: 1 - squeeze * 0.18, y: 1 + squeeze * 0.08)
            .shadow(color: TherapyPalette.tertiary.opacity(secured ? 0.9 : 0.3), radius: secured ? 8 : 3)
    }
}
