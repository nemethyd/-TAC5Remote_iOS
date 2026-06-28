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
    // Validated against live Mural dump (zero-based Modbus offsets).
    case t7 = 8
    case presetTargetAirflow = 55
    case supplyAirflow = 64
    case exhaustAirflow = 72
    case ratioExhSup = 426
    case caAirflowI = 427
    case caAirflowII = 428
    case caAirflowIII = 429
    case presetWriteTrigger = 199
    case presetState = 202
    case t1 = 154
    case t2 = 155
    case t3 = 156
    case bypassEnable = 222
    case boostEnable = 227
    case operationMode = 425
}

public enum TAC5Preset: UInt16, CaseIterable, Sendable {
    case k1 = 1
    case k2 = 2
    case k3 = 3

    public var label: String {
        switch self {
        case .k1: return "K1"
        case .k2: return "K2"
        case .k3: return "K3"
        }
    }
}

public enum TAC5OperationMode: UInt16, CaseIterable, Sendable {
    case off = 0
    case ca = 1
    case ls = 2
    case cp = 4

    public var label: String {
        switch self {
        case .off: return "OFF"
        case .ca: return "CA"
        case .ls: return "LS"
        case .cp: return "CP"
        }
    }
}

public struct TAC5Codec {
    public init() {}

    public func decodeTemperature(_ registerValue: UInt16) -> Double {
        // Placeholder scaling (0.1 C). Verify against target unit.
        return Double(Int16(bitPattern: registerValue)) / 10.0
    }

    public func decodeAirflow(_ registerValue: UInt16) -> Double {
        // Raw airflow register value in m3/h.
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
        // Fields are not contiguous, so read in small targeted blocks.
        let t7Raw = try await readRegister(TAC5Register.t7.rawValue)
        let supplyRaw = try await readRegister(TAC5Register.supplyAirflow.rawValue)
        let exhaustRaw = try await readRegister(TAC5Register.exhaustAirflow.rawValue)
        let tempsRaw = try await client.readHoldingRegisters(startAddress: TAC5Register.t1.rawValue, quantity: 3)

        let t1Raw = tempsRaw[safe: 0]
        let t2Raw = tempsRaw[safe: 1]
        let t3Raw = tempsRaw[safe: 2]

        return TAC5Snapshot(
            t1Celsius: t1Raw.map(codec.decodeTemperature),
            t2Celsius: t2Raw.map(codec.decodeTemperature),
            t3Celsius: t3Raw.map(codec.decodeTemperature),
            // T7 is exposed with 0.01 scaling on this unit family.
            t7Celsius: t7Raw.map { Double(Int16(bitPattern: $0)) / 100.0 },
            supplyAirflowM3h: supplyRaw.map(codec.decodeAirflow),
            exhaustAirflowM3h: exhaustRaw.map(codec.decodeAirflow)
        )
    }

    public func readBoostEnabled() async throws -> Bool? {
        guard let raw = try await readRegister(TAC5Register.boostEnable.rawValue) else {
            return nil
        }
        return raw == 1
    }

    public func readPreset() async throws -> TAC5Preset? {
        guard let raw = try await readRegister(TAC5Register.presetState.rawValue) else {
            return nil
        }
        return TAC5Preset(rawValue: raw)
    }

    public func readActivePresetTargetAirflow() async throws -> UInt16? {
        try await readRegister(TAC5Register.presetTargetAirflow.rawValue)
    }

    public func readBypassEnabled() async throws -> Bool? {
        guard let raw = try await readRegister(TAC5Register.bypassEnable.rawValue) else {
            return nil
        }
        return raw == 1
    }

    public func readExhaustSupplyRatio() async throws -> UInt16? {
        try await readRegister(TAC5Register.ratioExhSup.rawValue)
    }

    public func writeExhaustSupplyRatio(_ ratioPercent: UInt16) async throws {
        try await client.writeSingleRegister(address: TAC5Register.ratioExhSup.rawValue, value: ratioPercent)
    }

    public func readCaAirflowI() async throws -> UInt16? {
        try await readRegister(TAC5Register.caAirflowI.rawValue)
    }

    public func readCaAirflowII() async throws -> UInt16? {
        try await readRegister(TAC5Register.caAirflowII.rawValue)
    }

    public func readCaAirflowIII() async throws -> UInt16? {
        try await readRegister(TAC5Register.caAirflowIII.rawValue)
    }

    public func writeCaAirflowI(_ value: UInt16) async throws {
        try await client.writeSingleRegister(address: TAC5Register.caAirflowI.rawValue, value: value)
    }

    public func writeCaAirflowII(_ value: UInt16) async throws {
        try await client.writeSingleRegister(address: TAC5Register.caAirflowII.rawValue, value: value)
    }

    public func writeCaAirflowIII(_ value: UInt16) async throws {
        try await client.writeSingleRegister(address: TAC5Register.caAirflowIII.rawValue, value: value)
    }

    public func readOperationMode() async throws -> TAC5OperationMode? {
        guard let raw = try await readRegister(TAC5Register.operationMode.rawValue) else {
            return nil
        }
        return TAC5OperationMode(rawValue: raw)
    }

    public func writeBoostEnabled(_ enabled: Bool) async throws {
        let value: UInt16 = enabled ? 1 : 0
        try await client.writeSingleRegister(address: TAC5Register.boostEnable.rawValue, value: value)
    }

    public func writeBypassEnabled(_ enabled: Bool) async throws {
        let value: UInt16 = enabled ? 1 : 0
        try await client.writeSingleRegister(address: TAC5Register.bypassEnable.rawValue, value: value)
    }

    public func writeOperationMode(_ mode: TAC5OperationMode) async throws {
        try await client.writeSingleRegister(address: TAC5Register.operationMode.rawValue, value: mode.rawValue)
    }

    public func writePreset(_ preset: TAC5Preset) async throws {
        // Observed device behavior: each K preset change writes 199=0, then 202=<preset>.
        try await client.writeSingleRegister(address: TAC5Register.presetWriteTrigger.rawValue, value: 0)
        // Eole emits these writes with a small gap; mirroring that timing improves reliability.
        try await Task.sleep(nanoseconds: 40_000_000)
        try await client.writeSingleRegister(address: TAC5Register.presetState.rawValue, value: preset.rawValue)
    }

    private func readRegister(_ address: UInt16) async throws -> UInt16? {
        let regs = try await client.readHoldingRegisters(startAddress: address, quantity: 1)
        return regs.first
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
