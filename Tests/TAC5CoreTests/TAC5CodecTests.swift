import XCTest
@testable import TAC5Core

final class TAC5CodecTests: XCTestCase {
    func testDecodeTemperatureSignedScaling() {
        let codec = TAC5Codec()

        XCTAssertEqual(codec.decodeTemperature(214), 21.4, accuracy: 0.001)
        XCTAssertEqual(codec.decodeTemperature(UInt16(bitPattern: Int16(-55))), -5.5, accuracy: 0.001)
    }

    func testDecodeAirflowDirectValue() {
        let codec = TAC5Codec()

        XCTAssertEqual(codec.decodeAirflow(180), 180)
    }
}
