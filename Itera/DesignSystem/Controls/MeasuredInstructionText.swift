//
//  MeasuredInstructionText.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//  Adapted from VisionPoc TherapyInstructionText.swift.
//

import SwiftUI
import UIKit

/// Native text measurement keeps the reading gate tied to the text actually on screen.
struct MeasuredInstructionText: UIViewRepresentable {
    let phrase: String
    let instructionID: UUID
    let fontSize: CGFloat
    let reduceMotion: Bool
    let voiceOver: Bool
    let onReadingChanged: (UUID, Bool) -> Void

    func makeUIView(context: Context) -> ReadingScrollView { ReadingScrollView() }

    func updateUIView(_ view: ReadingScrollView, context: Context) {
        view.configure(
            phrase: phrase, id: instructionID, fontSize: fontSize,
            reduceMotion: reduceMotion, voiceOver: voiceOver, onReadingChanged: onReadingChanged
        )
    }

    static func dismantleUIView(_ view: ReadingScrollView, coordinator: ()) { view.stop() }

    final class ReadingScrollView: UIScrollView, UIScrollViewDelegate {
        private let text = UILabel()
        private var instructionID: UUID?
        private var configuredPhrase = ""
        private var onReadingChanged: ((UUID, Bool) -> Void)?
        private var measuredSize = CGSize.zero
        private var reduceMotion = false
        private var voiceOver = false
        private var readingComplete = false
        private var generation = 0
        private var resumeAt = 0.0
        private var nextPageAt = 0.0
        private var bottomSince: Double?
        private var lastTick: Double?
        private var displayLink: CADisplayLink?
        private lazy var displayTarget = DisplayTarget(view: self)

        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            backgroundColor = .clear
            contentInsetAdjustmentBehavior = .never
            alwaysBounceVertical = false
            text.numberOfLines = 0
            text.textAlignment = .center
            text.textColor = .white
            text.isAccessibilityElement = true
            text.accessibilityTraits = .header
            addSubview(text)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configure(
            phrase: String, id: UUID, fontSize: CGFloat, reduceMotion: Bool, voiceOver: Bool,
            onReadingChanged: @escaping (UUID, Bool) -> Void
        ) {
            self.onReadingChanged = onReadingChanged
            guard instructionID != id || configuredPhrase != phrase || text.font.pointSize != fontSize
                    || self.reduceMotion != reduceMotion || self.voiceOver != voiceOver else { return }
            displayLink?.invalidate()
            displayLink = nil
            instructionID = id
            configuredPhrase = phrase
            text.text = phrase
            text.font = AppFont.uiFont(size: fontSize)
            let copy = SessionGuidanceCopy(phrase: phrase)
            let rendered = NSMutableAttributedString(
                string: copy.main,
                attributes: [.font: AppFont.uiFont(size: fontSize)]
            )
            if let support = copy.support {
                rendered.append(NSAttributedString(
                    string: "\n\n" + support,
                    attributes: [.font: AppFont.uiFont(size: fontSize * 0.5)]
                ))
            }
            text.attributedText = rendered
            self.reduceMotion = reduceMotion
            self.voiceOver = voiceOver
            measuredSize = .zero
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
            if measuredSize != bounds.size {
                measuredSize = bounds.size
                let width = min(1_100, max(1, bounds.width - 48))
                let height = ceil(text.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
                text.frame = CGRect(x: (bounds.width - width) / 2, y: 8, width: width, height: height)
                contentSize = CGSize(width: bounds.width, height: height + 16)
                setContentOffset(.zero, animated: false)
                generation += 1
                readingComplete = false
                bottomSince = nil
                lastTick = nil
                resumeAt = CACurrentMediaTime() + 1.5
                let page = pageDistance
                nextPageAt = resumeAt + (reduceMotion ? Double(page) / 32 : 0)
                report(false)
                if maximumOffset <= 1, !voiceOver { complete() }
            }
            startIfNeeded()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stop(); measuredSize = .zero }
            else { setNeedsLayout(); startIfNeeded() }
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
            lastTick = nil
            generation += 1
        }

        private var maximumOffset: CGFloat { max(0, contentSize.height - bounds.height) }
        private var pageDistance: CGFloat { max(1, max(bounds.height * 0.5, bounds.height - text.font.lineHeight)) }

        private func startIfNeeded() {
            guard window != nil, !readingComplete, !voiceOver, displayLink == nil, measuredSize != .zero else { return }
            let link = CADisplayLink(target: displayTarget, selector: #selector(DisplayTarget.tick(_:)))
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        fileprivate func tick(_ timestamp: Double) {
            let delta = lastTick.map { min(0.1, max(0, timestamp - $0)) } ?? 0
            lastTick = timestamp
            guard window != nil, !voiceOver, !isTracking, !isDragging, !isDecelerating, timestamp >= resumeAt else { return }
            if contentOffset.y < maximumOffset - 1 {
                bottomSince = nil
                if reduceMotion {
                    guard timestamp >= nextPageAt else { return }
                    let page = pageDistance
                    setContentOffset(CGPoint(x: 0, y: min(maximumOffset, contentOffset.y + page)), animated: false)
                    nextPageAt = timestamp + Double(page) / 32
                } else {
                    setContentOffset(CGPoint(x: 0, y: min(maximumOffset, contentOffset.y + CGFloat(delta * 32))), animated: false)
                }
            } else {
                if bottomSince == nil { bottomSince = timestamp }
                if timestamp - (bottomSince ?? timestamp) >= 2 { complete() }
            }
        }

        private func complete() {
            guard !readingComplete else { return }
            readingComplete = true
            displayLink?.invalidate()
            displayLink = nil
            report(true)
        }

        private func report(_ complete: Bool) {
            guard let id = instructionID else { return }
            let revision = generation
            // Layout may run inside a SwiftUI update; deliver state changes on the next main turn.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == revision else { return }
                self.onReadingChanged?(id, complete)
            }
        }

        private func manualInteraction() {
            if readingComplete { readingComplete = false; report(false) }
            bottomSince = nil
            resumeAt = CACurrentMediaTime() + 3
            let page = pageDistance
            nextPageAt = resumeAt + (reduceMotion ? Double(page) / 32 : 0)
            startIfNeeded()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { manualInteraction() }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { manualInteraction() }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { manualInteraction() }

        private final class DisplayTarget: NSObject {
            weak var view: ReadingScrollView?
            init(view: ReadingScrollView) { self.view = view }
            @objc func tick(_ link: CADisplayLink) { view?.tick(link.timestamp) }
        }
    }
}

/// Main action and optional supporting sentence share one localized narration string.
struct SessionGuidanceCopy {
    let main: String
    let support: String?

    init(phrase: String) {
        let lines = phrase.split(separator: "\n", maxSplits: 1).map(String.init)
        main = lines.first ?? phrase
        support = lines.count > 1 ? lines[1] : nil
    }
}
