import Foundation

public struct TAC5Snapshot: Sendable {
    public var t1Celsius: Double?
    public var t2Celsius: Double?
    public var t3Celsius: Double?
    public var t4Celsius: Double?
    public var supplyAirflowM3h: Double?
    public var exhaustAirflowM3h: Double?

    public init(
        t1Celsius: Double? = nil,
        t2Celsius: Double? = nil,
        t3Celsius: Double? = nil,
        t4Celsius: Double? = nil,
        supplyAirflowM3h: Double? = nil,
        exhaustAirflowM3h: Double? = nil
    ) {
        self.t1Celsius = t1Celsius
        self.t2Celsius = t2Celsius
        self.t3Celsius = t3Celsius
        self.t4Celsius = t4Celsius
        self.supplyAirflowM3h = supplyAirflowM3h
        self.exhaustAirflowM3h = exhaustAirflowM3h
    }
}

public enum TAC5Register: UInt16, CaseIterable {
    // Placeholder addresses. Replace with validated TAC5 map.
    case t1 = 41001
    case t2 = 41002
    case t3 = 41003
    case t4 = 41004
    case supplyAirflow = 41010
    case exhaustAirflow = 41011
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
            t4Celsius: reg(.t4).map(codec.decodeTemperature),
            supplyAirflowM3h: reg(.supplyAirflow).map(codec.decodeAirflow),
            exhaustAirflowM3h: reg(.exhaustAirflow).map(codec.decodeAirflow)
        )
    }
}
