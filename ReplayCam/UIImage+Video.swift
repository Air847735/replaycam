import UIKit
import CoreVideo

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Scale-1 resize for pixel-accurate video export.
    func resizedExact(to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func toPixelBuffer() -> CVPixelBuffer? {
        let w = Int(size.width), h = Int(size.height)
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary

        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs, &buffer) == kCVReturnSuccess,
              let pb = buffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        UIGraphicsPopContext()

        return pb
    }
}
