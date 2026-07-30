import CoreImage.CIFilterBuiltins
import SwiftUI

/// Doc utilisateur — encodé via CoreImage (`CIFilter.qrCodeGenerator()`), système, zéro
/// dépendance tierce (ADR-0012).
struct QRCodeView: View {
    let url: URL

    var body: some View {
        if let image = Self.generate(from: url) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Code QR d'appairage")
        } else {
            Color.clear
        }
    }

    private static func generate(from url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        // Agrandi avant rasterisation : sans ça, l'image native (quelques dizaines de pixels)
        // devient floue une fois étirée par `.resizable()`.
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
