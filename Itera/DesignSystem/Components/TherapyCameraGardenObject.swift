//
//  TherapyCameraGardenObject.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 03/11/2026.
//

import SwiftUI

/// Transparent, value-driven kampung game artwork for the finger exercises.
///
/// The caller supplies accepted exercise state: pose toward the target, a secured
/// target, and an identified accepted deposit. This view never accepts poses,
/// counts repetitions or advances a session; it only shows what already happened.
struct TherapyCameraGardenObject: View {
    let style: GardenActivityStyle
    let anchor: CGPoint
    let collection: CGPoint
    let depositOrigin: CGPoint
    let pose: Double
    let secured: Bool
    let waiting: Bool
    let collected: Int
    let activeFinger: Int
    let depositFinger: Int
    let depositID: Int
    let paused: Bool
    let showsObject: Bool
    let size: CGFloat
    let animated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastDeposit: Int
    @State private var flightStart = CGPoint.zero
    @State private var flightEnd = CGPoint.zero
    @State private var flightProgress = 0.0
    @State private var flying = false
    @State private var ringingTube: Int?
    @State private var ringSwing = 0.0

    init(
        style: GardenActivityStyle,
        anchor: CGPoint,
        collection: CGPoint,
        depositOrigin: CGPoint,
        pose: Double,
        secured: Bool,
        waiting: Bool,
        collected: Int,
        activeFinger: Int,
        depositFinger: Int,
        depositID: Int,
        paused: Bool,
        showsObject: Bool = true,
        size: CGFloat = 120,
        animated: Bool = true
    ) {
        self.style = style
        self.anchor = anchor
        self.collection = collection
        self.depositOrigin = depositOrigin
        self.pose = pose
        self.secured = secured
        self.waiting = waiting
        self.collected = collected
        self.activeFinger = activeFinger
        self.depositFinger = depositFinger
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
            if style != .chimes {
                activeObject
                    .frame(width: size, height: size)
                    .overlay(alignment: .topTrailing) {
                        statusBadge
                    }
                    .opacity(showsObject ? (waiting ? 0.55 : 1) : 0)
                    .position(anchor)
                    .animation(moves ? .easeOut(duration: 0.2) : nil, value: anchor)
                    .animation(moves ? .easeOut(duration: 0.18) : nil, value: amount)
            }

            collectionView
                .position(collection)

            if flying {
                flightArtwork
                    .modifier(
                        ArcFlight(
                            progress: flightProgress,
                            start: flightStart,
                            end: flightEnd,
                            flutter: style == .bloom
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: flightKey) {
            await presentDeposit()
        }
    }

    // MARK: - Accepted deposit

    /// Plays one bounded, cancellable reward for a newly accepted deposit identity.
    private func presentDeposit() async {
        guard lastDeposit != depositID else {
            return
        }
        lastDeposit = depositID

        guard moves else {
            return
        }

        if style == .chimes {
            ringingTube = depositFinger
            ringSwing = 1
            withAnimation(.easeOut(duration: 1.1)) {
                ringSwing = 0
            }
            try? await Task.sleep(for: .milliseconds(1150))
            ringingTube = nil
            return
        }

        flightStart = flightOrigin
        flightEnd = CGPoint(x: collection.x, y: collection.y - 46)
        flightProgress = 0
        flying = true
        defer {
            flying = false
        }
        withAnimation(.easeInOut(duration: 0.9)) {
            flightProgress = 1
        }
        try? await Task.sleep(for: .milliseconds(950))
    }

    private var flightOrigin: CGPoint {
        switch style {
        case .bloom:
            return CGPoint(x: depositOrigin.x + size * 0.28, y: depositOrigin.y - size * 0.3)
        case .well:
            return CGPoint(x: depositOrigin.x, y: depositOrigin.y - size * 0.1)
        case .juice, .garland, .chimes:
            return depositOrigin
        }
    }

    // MARK: - Active object

    @ViewBuilder
    private var activeObject: some View {
        switch style {
        case .juice:
            juiceOrange
        case .well:
            wellBucket
        case .garland:
            Image("kampung-melati")
                .resizable()
                .scaledToFit()
                .scaleEffect(0.85 + amount * 0.25)
                .shadow(color: Self.glow.opacity(secured ? 0.9 : 0.25), radius: secured ? 10 : 3)
        case .bloom:
            hibiscus
        case .chimes:
            EmptyView()
        }
    }

    /// The orange flattens as the hand closes; juice drops appear only while squeezing.
    private var juiceOrange: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Image("kampung-tetes-jus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.15, height: size * 0.15)
                    .offset(
                        x: CGFloat(index - 1) * size * 0.2,
                        y: size * (0.42 + amount * 0.12) + (index == 1 ? size * 0.06 : 0)
                    )
                    .opacity(amount)
            }
            Image("kampung-jeruk")
                .resizable()
                .scaledToFit()
                .scaleEffect(x: 1 + amount * 0.1, y: 1 - amount * 0.22, anchor: .bottom)
        }
    }

    /// Hooking the fingers raises the bucket from the water toward the crossbar.
    private var wellBucket: some View {
        let unit = size / 128
        let bucketSize = 30 * unit
        let bucketCenter = (82 - 25 * amount) * unit

        return ZStack(alignment: .topLeading) {
            Image("kampung-sumur")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)

            Path { path in
                path.move(to: CGPoint(x: 64 * unit, y: 42 * unit))
                path.addLine(to: CGPoint(x: 64 * unit, y: bucketCenter - bucketSize * 0.3))
            }
            .stroke(Self.rope, style: StrokeStyle(lineWidth: max(2, 3 * unit), lineCap: .round))

            Image("kampung-ember")
                .resizable()
                .scaledToFit()
                .frame(width: bucketSize, height: bucketSize)
                .position(x: 64 * unit, y: bucketCenter)
                .mask(alignment: .top) {
                    // The bucket emerges from the water surface instead of floating in front of the well.
                    Rectangle().frame(height: 70 * unit)
                }
        }
        .frame(width: size, height: size)
    }

    /// The bud opens into a kembang sepatu; a butterfly lands once the target is secured.
    private var hibiscus: some View {
        ZStack {
            Image("kampung-sepatu-kuncup")
                .resizable()
                .scaledToFit()
                .scaleEffect(0.75)
                .opacity(1 - amount)
            Image("kampung-sepatu")
                .resizable()
                .scaledToFit()
                .scaleEffect(0.45 + amount * 0.55)
                .opacity(amount)
            Image("kampung-kupu")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.32, height: size * 0.32)
                .offset(x: size * 0.28, y: -size * 0.3)
                .opacity(secured ? 1 : 0)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if waiting {
            Image(systemName: "pause.circle.fill")
                .typography(.title2)
                .foregroundStyle(TherapyPalette.primary)
                .background(TherapyPalette.surface, in: Circle())
        } else if secured {
            Image(systemName: "checkmark.circle.fill")
                .typography(.title2)
                .foregroundStyle(TherapyPalette.primary)
                .background(TherapyPalette.surface, in: Circle())
        }
    }

    // MARK: - Collection

    @ViewBuilder
    private var collectionView: some View {
        switch style {
        case .juice:
            VStack(spacing: 4) {
                juiceGlass
                countLabel("kampung.juice.count \(collected)")
            }
            .offset(y: -36)
        case .well:
            VStack(spacing: 4) {
                growingPlant
                countLabel("kampung.well.count \(collected)")
            }
            .offset(y: -40)
        case .garland:
            VStack(spacing: 4) {
                garland
                countLabel("kampung.garland.count \(collected)")
            }
            .offset(y: -30)
        case .bloom:
            VStack(spacing: 4) {
                butterflyGarden
                countLabel("kampung.bloom.count \(collected)")
            }
            .offset(y: -36)
        case .chimes:
            VStack(spacing: 4) {
                bambooChimes
                countLabel("kampung.chimes.count \(collected / 4)")
            }
            .offset(y: -84)
        }
    }

    /// Each accepted squeeze adds a fifth of a glass; a full glass starts a fresh one.
    private var juiceGlass: some View {
        let remainder = collected % Self.juicePerGlass
        let fill = collected > 0 && remainder == 0
            ? 1
            : Double(remainder) / Double(Self.juicePerGlass)
        // Liquid spans 14 / 128 of the glass bottom when empty up to 92 / 128 when full.
        let visible = fill > 0 ? (14 + 78 * fill) / 128 : 0
        let glassSize: CGFloat = 76

        return ZStack {
            Image("kampung-gelas-kosong")
                .resizable()
                .scaledToFit()
            Image("kampung-gelas-penuh")
                .resizable()
                .scaledToFit()
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: glassSize * visible)
                }
        }
        .frame(width: glassSize, height: glassSize)
        .animation(moves ? .easeOut(duration: 0.5) : nil, value: collected)
    }

    private var growingPlant: some View {
        let potSize: CGFloat = 76
        let growth = 0.35 + 0.65 * min(1, Double(collected) / 10)

        return ZStack(alignment: .bottom) {
            Image("kampung-tunas")
                .resizable()
                .scaledToFit()
                .frame(width: potSize, height: potSize)
                .scaleEffect(growth, anchor: .bottom)
                // The sprout base sits on the pot soil, 47 / 128 from the pot artwork top.
                .offset(y: -potSize * (1 - 47 / 128))
            Image("kampung-pot")
                .resizable()
                .scaledToFit()
                .frame(width: potSize, height: potSize)
        }
        .frame(width: potSize, height: potSize * 1.6, alignment: .bottom)
        .animation(moves ? .easeOut(duration: 0.6) : nil, value: collected)
    }

    private var garland: some View {
        let width: CGFloat = 230
        let height: CGFloat = 62
        let shown = min(collected, Self.garlandLength)

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 6, y: 10))
                path.addQuadCurve(to: CGPoint(x: width - 6, y: 10), control: CGPoint(x: width / 2, y: height + 20))
            }
            .stroke(Self.garlandString, style: StrokeStyle(lineWidth: 3, lineCap: .round))

            ForEach(0..<shown, id: \.self) { index in
                Image("kampung-melati")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .position(garlandPoint(index: index, width: width, height: height))
            }
        }
        .frame(width: width, height: height)
        .animation(moves ? .easeOut(duration: 0.4) : nil, value: shown)
    }

    private func garlandPoint(index: Int, width: CGFloat, height: CGFloat) -> CGPoint {
        let t = (CGFloat(index) + 0.5) / CGFloat(Self.garlandLength)
        let start = CGPoint(x: 6, y: 10)
        let control = CGPoint(x: width / 2, y: height + 20)
        let end = CGPoint(x: width - 6, y: 10)
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

    private var butterflyGarden: some View {
        let visitors = min(collected, 3)
        let offsets: [CGSize] = [
            CGSize(width: -40, height: -20),
            CGSize(width: 40, height: -26),
            CGSize(width: 0, height: -46),
        ]

        return ZStack {
            Image("kampung-sepatu")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
            ForEach(0..<visitors, id: \.self) { index in
                Image("kampung-kupu")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .offset(offsets[index])
            }
        }
        .frame(width: 140, height: 90, alignment: .bottom)
        .animation(moves ? .easeOut(duration: 0.4) : nil, value: visitors)
    }

    /// Four bamboo tubes, index to little finger. The named finger's tube glows and
    /// leans with movement; an accepted finger rings its tube once.
    private var bambooChimes: some View {
        ZStack(alignment: .top) {
            Image("kampung-gantungan")
                .resizable()
                .scaledToFit()
                .frame(width: 190)
            HStack(alignment: .top, spacing: 14) {
                ForEach(0..<4, id: \.self) { tube in
                    let active = tube == activeFinger && showsObject && !waiting
                    Image("kampung-bambu")
                        .resizable()
                        .frame(width: 28, height: Self.tubeLengths[tube])
                        .shadow(color: Self.glow.opacity(active ? 0.95 : 0), radius: active ? 10 : 0)
                        .rotationEffect(.degrees(active ? amount * 8 : 0), anchor: .top)
                        .modifier(BambooSwing(amount: ringingTube == tube ? ringSwing : 0))
                }
            }
            .padding(.top, 40)
        }
        .frame(width: 200, height: 160, alignment: .top)
        .animation(moves ? .easeOut(duration: 0.18) : nil, value: amount)
    }

    @ViewBuilder
    private var flightArtwork: some View {
        switch style {
        case .juice:
            Image("kampung-tetes-jus")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
        case .well:
            Image("kampung-tetes-air")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
        case .garland:
            Image("kampung-melati")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
        case .bloom:
            Image("kampung-kupu")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
        case .chimes:
            EmptyView()
        }
    }

    private func countLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .typography(.headline)
            .foregroundStyle(TherapyPalette.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(TherapyPalette.surface.opacity(0.95), in: Capsule())
    }

    // MARK: - Constants

    private static let juicePerGlass = 5
    private static let garlandLength = 12
    private static let tubeLengths: [CGFloat] = [112, 98, 86, 74]
    private static let glow = Color(red: 1, green: 0.85, blue: 0.45)
    private static let rope = Color(red: 0.79, green: 0.64, blue: 0.42)
    private static let garlandString = Color(red: 0.86, green: 0.89, blue: 0.83)
}

// MARK: - Animation effects

/// Moves a reward along a gentle arc. Animating `progress` evaluates every frame,
/// so the arc and optional wing flutter follow the path rather than a straight line.
private struct ArcFlight: GeometryEffect {
    var progress: Double
    let start: CGPoint
    let end: CGPoint
    let flutter: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = start.x + (end.x - start.x) * progress
        let y = start.y + (end.y - start.y) * progress - sin(progress * .pi) * 60
        let scale = 1 - progress * 0.35
        let wings = flutter ? 0.65 + abs(sin(progress * .pi * 6)) * 0.35 : 1

        let transform = CGAffineTransform(translationX: x - size.width / 2, y: y - size.height / 2)
            .translatedBy(x: size.width / 2, y: size.height / 2)
            .scaledBy(x: scale * wings, y: scale)
            .translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(transform)
    }
}

/// A decaying pendulum swing around the tube's top edge.
private struct BambooSwing: GeometryEffect {
    var amount: Double

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let angle = sin(amount * .pi * 4) * amount * 0.22
        let transform = CGAffineTransform(translationX: size.width / 2, y: 0)
            .rotated(by: angle)
            .translatedBy(x: -size.width / 2, y: 0)
        return ProjectionTransform(transform)
    }
}
