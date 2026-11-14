//
//  TherapyQRCode.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import CoreImage.CIFilterBuiltins
import SwiftUI
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

// MARK: - Code image

/// A crisp QR code for supplied text, drawn black on white with a quiet margin so any camera can
/// read it. Shows a placeholder if the text cannot be encoded.
struct TMTherapyQRCode: View {
    let text: String
    var size: CGFloat = 280

    var body: some View {
        Group {
            if let image = Self.image(for: text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(TherapyPalette.muted)
            }
        }
        .frame(width: size, height: size)
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityHidden(true)
    }

    private static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Scanner

#if targetEnvironment(macCatalyst)
/// VisionKit's scanner is unavailable on Mac Catalyst; callers show the typed-code field.
struct TMTherapyQRScanner: View {
    let onCode: (String) -> Void

    static var isAvailable: Bool { false }

    var body: some View { EmptyView() }
}
#else
/// Live QR scanning with VisionKit. Reports each new payload once. Where scanning is not
/// supported (the Simulator, older iPads) callers show a typed-code field instead.
struct TMTherapyQRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var last: String?

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, payload != last else {
                    continue
                }

                last = payload
                onCode(payload)
            }
        }
    }
}
#endif
