import Foundation

public struct TAC5Snapshot: Sendable {
    public var t1Celsius: Double?
    public var t2Celsius: Double?
    public var t3Celsius: Double?
    public var t7Celsius: Double?
    public var supplyAirflowM3h: Double?
    public var exhaustAirflowM3h: Double?

    public init(
        t1Celsius: Double? = nil,
        t2Celsius: Double? = nil,
        t3Celsius: Double? = nil,
        t7Celsius: Double? = nil,
        supplyAirflowM3h: Double? = nil,
        exhaustAirflowM3h: Double? = nil
    ) {
        self.t1Celsius = t1Celsius
        self.t2Celsius = t2Celsius
        self.t3Celsius = t3Celsius
        self.t7Celsius = t7Celsius
        self.supplyAirflowM3h = supplyAirflowM3h
        self.exhaustAirflowM3h = exhaustAirflowM3h
    }

    // Backward-compatible alias for older call sites and payload mapping.
    public var t4Celsius: Double? {
        get { t7Celsius }
        set { t7Celsius = newValue }
    }
}

public enum TAC5Register: UInt16, CaseIterable {
    // Modbus PDU uses zero-based register offsets (not 4xxxx notation).
    case t1 = 0
    case t2 = 1
    case t3 = 2
    case t7 = 6
    case supplyAirflow = 9
    case exhaustAirflow = 10
}

public struct TAC5Codec {
    public init() {}

    public func decodeTemperature(_ registerValue: UInt16) -> Double {
        // Placeholder scaling (0.1 C). Verify against target unit.
        return Double(Int16(bitPattern: registerValue)) / 10.0
    }

    public func decodeAirflow(_ registerValue: UInt16) -> Double {
        // Placeholder direct value in m3/h. Verify against target unit.
        return Double(registerValue)
    }
}

public actor TAC5Repository {
    private let client: ModbusTCPClient
    private let codec = TAC5Codec()

    public init(client: ModbusTCPClient) {
        self.client = client
    }

    public func readSnapshot() async throws -> TAC5Snapshot {
        let regs = try await client.readHoldingRegisters(startAddress: TAC5Register.t1.rawValue, quantity: 11)

        func reg(_ r: TAC5Register) -> UInt16? {
            let index = Int(r.rawValue - TAC5Register.t1.rawValue)
            guard index >= 0, index < regs.count else { return nil }
            return regs[index]
        }

        return TAC5Snapshot(
            t1Celsius: reg(.t1).map(codec.decodeTemperature),
            t2Celsius: reg(.t2).map(codec.decodeTemperature),
            t3Celsius: reg(.t3).map(codec.decodeTemperature),
            t7Celsius: reg(.t7).map(codec.decodeTemperature),
            supplyAirflowM3h: reg(.supplyAirflow).map(codec.decodeAirflow),
            exhaustAirflowM3h: reg(.exhaustAirflow).map(codec.decodeAirflow)
        )
    }
}
