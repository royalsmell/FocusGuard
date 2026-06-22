import CoreImage
import CoreMedia
import Foundation
import ImageIO
import SharedCore

final class BroadcastImageProcessor: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    func dHash(pixelBuffer: CVPixelBuffer) -> UInt64? {
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        guard source.extent.width > 0, source.extent.height > 0 else { return nil }
        let scale = CGAffineTransform(
            scaleX: CGFloat(DHash64.pixelWidth) / source.extent.width,
            y: CGFloat(DHash64.pixelHeight) / source.extent.height
        )
        let image = source.transformed(by: scale)
        var rgba = [UInt8](repeating: 0, count: DHash64.pixelWidth * DHash64.pixelHeight * 4)
        context.render(
            image,
            toBitmap: &rgba,
            rowBytes: DHash64.pixelWidth * 4,
            bounds: CGRect(x: 0, y: 0, width: DHash64.pixelWidth, height: DHash64.pixelHeight),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        var grayscale: [UInt8] = []
        grayscale.reserveCapacity(DHash64.pixelWidth * DHash64.pixelHeight)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            let value = (Int(rgba[index]) * 299 + Int(rgba[index + 1]) * 587 + Int(rgba[index + 2]) * 114) / 1_000
            grayscale.append(UInt8(value))
        }
        return DHash64.compute(grayscalePixels: grayscale)
    }

    func jpeg(pixelBuffer: CVPixelBuffer, longEdge: CGFloat, quality: CGFloat) -> Data? {
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let sourceLongEdge = max(source.extent.width, source.extent.height)
        guard sourceLongEdge > 0 else { return nil }
        let scale = min(1, longEdge / sourceLongEdge)
        let transformed = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.jpegRepresentation(
            of: transformed,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }
}

