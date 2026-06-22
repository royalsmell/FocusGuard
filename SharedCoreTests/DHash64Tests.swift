import XCTest
@testable import SharedCore

final class DHash64Tests: XCTestCase {
    func testDHashUsesHorizontalDifferences() {
        let descendingRow: [UInt8] = [9, 8, 7, 6, 5, 4, 3, 2, 1]
        let pixels = Array(repeating: descendingRow, count: 8).flatMap { $0 }
        let hash = DHash64.compute(grayscalePixels: pixels)
        XCTAssertEqual(hash, UInt64.max)
        XCTAssertEqual(DHash64.distance(hash ?? 0, 0), 64)
    }

    func testDHashRejectsUnexpectedPixelCount() {
        XCTAssertNil(DHash64.compute(grayscalePixels: [0, 1]))
    }
}

