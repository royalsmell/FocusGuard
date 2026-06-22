import Foundation

public enum DHash64 {
    public static let pixelWidth = 9
    public static let pixelHeight = 8

    public static func compute(grayscalePixels: [UInt8]) -> UInt64? {
        guard grayscalePixels.count == pixelWidth * pixelHeight else { return nil }
        var hash: UInt64 = 0
        var bit = 0
        for row in 0..<pixelHeight {
            let offset = row * pixelWidth
            for column in 0..<(pixelWidth - 1) {
                if grayscalePixels[offset + column] > grayscalePixels[offset + column + 1] {
                    hash |= UInt64(1) << UInt64(bit)
                }
                bit += 1
            }
        }
        return hash
    }

    public static func distance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}

