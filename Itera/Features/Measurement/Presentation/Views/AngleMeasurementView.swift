//
//  AngleMeasurementView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import SwiftUI

/// Trial page for measuring joint angles with each tracking backend, to compare with a goniometer.
struct TMAngleMeasurementView: View {
    @State private var model: AngleMeasurementViewModel
    @Environment(NavigationRouter.self) private var router
    @Environment(PermissionManager.self) private var permissions
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraAllowed = true

    init(model: AngleMeasurementViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 24) {
            TMTherapyPageHeader(
                title: "measurement.title",
                leadingTitle: "measurement.close",
                leadingSymbol: "xmark",
                leadingAction: close
            )

            HStack(alignment: .top, spacing: 24) {
                cameraPanel
                controls
                    .frame(width: 420)
            }
        }
        .padding(32)
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas.ignoresSafeArea())
        .task {
            cameraAllowed = await permissions.request(.camera) == .authorized

            if cameraAllowed {
                model.start()
            }
        }
        .onDisappear(perform: model.stop)
        .onChange(of: scenePhase) { _, phase in
            // Capture stops in the background, as in every session (SYSTEM_DESIGN section 5).
            if phase == .active, cameraAllowed {
                model.start()
            } else if phase == .background {
                model.stop()
            }
        }
    }

    private func close() {
        model.stop()
        router.dismissFullScreenCover()
    }

    // MARK: - Camera

    private var cameraPanel: some View {
        ZStack(alignment: .top) {
            Color.black

            preview

            if let live = model.live {
                TMTherapyAngleOverlay(
                    points: live.points.map { CGPoint(x: $0.x, y: $0.y) },
                    aspect: model.imageAspect,
                    label: TMTherapyAngleText.format(live.degrees)
                )
            }

            if let message = statusMessage {
                Text(message)
                    .typography(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(TherapyPalette.calmUnderlay, in: Capsule())
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    /// One preview per subject: the body and hand services own separate capture sessions.
    @ViewBuilder
    private var preview: some View {
        switch model.subject {
        case .body:
            TMBodyCameraPreview(
                session: model.tracking.session,
                front: true,
                onReady: { _ in },
                onOrientation: model.orientationChanged
            )
        case .hand:
            TMHandCameraPreview(
                camera: model.camera,
                ready: { _ in },
                videoBoundsChanged: { _ in }
            )
        }
    }

    private var statusMessage: LocalizedStringKey? {
        guard cameraAllowed else {
            return "measurement.status.noCamera"
        }

        switch model.status {
        case .startingCamera:
            return "measurement.status.starting"
        case .notVisible:
            return model.subject == .body ? "measurement.status.noBody" : "measurement.status.noHand"
        case .measuring:
            return nil
        }
    }

    // MARK: - Controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                subjectPicker
                targetPickers
                backendPicker
                readings

                TMTherapyButton(
                    title: "measurement.reset",
                    symbol: "arrow.counterclockwise",
                    secondary: true,
                    pill: true,
                    action: model.resetRange
                )

                Text("measurement.disclaimer")
                    .typography(.footnote)
                    .foregroundStyle(TherapyPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var subjectPicker: some View {
        Picker(
            "measurement.subject",
            selection: Binding(get: { model.subject }, set: { model.select($0) })
        ) {
            ForEach(AngleMeasurementViewModel.Subject.allCases) { subject in
                Text(LocalizedStringKey(subject.titleKey)).tag(subject)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var targetPickers: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            switch model.subject {
            case .body:
                Picker("measurement.angle", selection: $model.bodyAngle) {
                    ForEach(BodyAngle.allCases) { angle in
                        Text(LocalizedStringKey(angle.titleKey)).tag(angle)
                    }
                }
                .frame(minHeight: 44)
            case .hand:
                Toggle("measurement.spread", isOn: $model.measuresSpread)
                    .frame(minHeight: 44)

                if !model.measuresSpread {
                    Picker("measurement.finger", selection: $model.finger) {
                        ForEach(MeasuredFinger.allCases) { finger in
                            Text(LocalizedStringKey(finger.titleKey)).tag(finger)
                        }
                    }
                    .frame(minHeight: 44)

                    Picker("measurement.joint", selection: $model.fingerJoint) {
                        ForEach(model.availableJoints) { joint in
                            Text(LocalizedStringKey(joint.titleKey)).tag(joint)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Picker("measurement.side", selection: $model.side) {
                Text("session.left").tag(HandSide.left)
                Text("session.right").tag(HandSide.right)
            }
            .pickerStyle(.segmented)
        }
        .typography(.body)
    }

    @ViewBuilder
    private var backendPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("measurement.backend")
                .typography(.headline)

            switch model.subject {
            case .body:
                Picker(
                    "measurement.backend",
                    selection: Binding(get: { model.bodyBackend }, set: { model.select($0) })
                ) {
                    ForEach(BodyPoseBackend.allCases) { backend in
                        Text(LocalizedStringKey(backend.titleKey)).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
            case .hand:
                Picker(
                    "measurement.backend",
                    selection: Binding(get: { model.handBackend }, set: { model.select($0) })
                ) {
                    ForEach(HandPoseBackend.allCases.filter(\.isAvailable)) { backend in
                        Text(LocalizedStringKey(backend.titleKey)).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var readings: some View {
        TMTherapyCard(color: TherapyPalette.panel, padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                TMTherapyAngleReadout(
                    title: "measurement.held",
                    degrees: model.estimator.held,
                    holdProgress: model.estimator.holdProgress,
                    caption: sourceCaption
                )

                Divider()

                reading("measurement.live", model.live?.degrees)
                reading("measurement.minimum", model.estimator.minimum)
                reading("measurement.maximum", model.estimator.maximum)
                reading("measurement.range", range)
            }
        }
    }

    private func reading(_ title: LocalizedStringKey, _ degrees: Double?) -> some View {
        LabeledContent {
            Text(verbatim: TMTherapyAngleText.format(degrees))
                .typography(.headline)
                .monospacedDigit()
        } label: {
            Text(title)
                .typography(.body)
        }
        .accessibilityElement(children: .combine)
    }

    private var range: Double? {
        guard let minimum = model.estimator.minimum, let maximum = model.estimator.maximum else {
            return nil
        }

        return maximum - minimum
    }

    private var sourceCaption: LocalizedStringKey {
        switch model.live?.source {
        case .world3D:
            return "measurement.source.world3D"
        case .image2D:
            return "measurement.source.image2D"
        case nil:
            return "measurement.source.none"
        }
    }
}
