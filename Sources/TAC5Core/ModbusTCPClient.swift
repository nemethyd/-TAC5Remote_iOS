import Foundation
#if canImport(Network)
import Network
#endif

public enum ModbusError: Error, LocalizedError {
    case connectionClosed
    case connectionFailed(String)
    case timeout
    case invalidResponse
    case exception(code: UInt8)
    case unsupportedFunction

    public var errorDescription: String? {
        switch self {
        case .connectionClosed: return "Connection closed"
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .timeout: return "Operation timed out"
        case .invalidResponse: return "Invalid Modbus response"
        case .exception(let code): return "Modbus exception code: \(code)"
        case .unsupportedFunction: return "Unsupported Modbus function"
        }
    }
}

public struct ModbusTCPConfig: Sendable {
    public var host: String
    public var port: UInt16
    public var unitId: UInt8
    public var timeoutSeconds: TimeInterval

    public init(host: String, port: UInt16 = 502, unitId: UInt8 = 1, timeoutSeconds: TimeInterval = 3) {
        self.host = host
        self.port = port
        self.unitId = unitId
        self.timeoutSeconds = timeoutSeconds
    }
}

public actor ModbusTCPClient {
    private let config: ModbusTCPConfig
    private var txId: UInt16 = 1
#if canImport(Network)
    private var connection: NWConnection?
#endif

    public init(config: ModbusTCPConfig) {
        self.config = config
    }

    public func readHoldingRegisters(startAddress: UInt16, quantity: UInt16) async throws -> [UInt16] {
        guard quantity > 0, quantity <= 125 else { throw ModbusError.invalidResponse }
        let pdu = buildReadHoldingPDU(startAddress: startAddress, quantity: quantity)
        let response = try await exchange(pdu: pdu)
        return try parseReadHoldingResponse(response: response, quantity: quantity)
    }

    public func writeSingleRegister(address: UInt16, value: UInt16) async throws {
        let pdu = buildWriteSinglePDU(address: address, value: value)
        let response = try await exchange(pdu: pdu)
        _ = try parseWriteSingleResponse(response: response)
    }

    public func disconnect() {
#if canImport(Network)
        connection?.cancel()
        connection = nil
#endif
    }

    private func exchange(pdu: Data) async throws -> Data {
#if canImport(Network)
        try await ensureConnected()
        guard let connection else { throw ModbusError.connectionClosed }

        do {
            let transactionId = nextTxId()
            let request = buildADU(transactionId: transactionId, pdu: pdu)

            try await send(data: request, on: connection)

            let mbapHeader = try await receiveExactly(count: 7, on: connection)
            let responseTransactionId = UInt16(mbapHeader[0]) << 8 | UInt16(mbapHeader[1])
            let protocolId = UInt16(mbapHeader[2]) << 8 | UInt16(mbapHeader[3])
            let length = UInt16(mbapHeader[4]) << 8 | UInt16(mbapHeader[5])
            let unitId = mbapHeader[6]

            guard responseTransactionId == transactionId, protocolId == 0, unitId == config.unitId else {
                throw ModbusError.invalidResponse
            }

            guard length >= 2 else { throw ModbusError.invalidResponse }
            let pduLength = Int(length) - 1
            return try await receiveExactly(count: pduLength, on: connection)
        } catch {
            // If frame parsing or timeout fails, reset the TCP stream to avoid byte misalignment.
            disconnect()
            throw error
        }
#else
        _ = pdu
        throw ModbusError.unsupportedFunction
#endif
    }

#if canImport(Network)
    private func ensureConnected() async throws {
        if connection != nil { return }

        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            throw ModbusError.invalidResponse
        }

        let newConnection = NWConnection(
            host: NWEndpoint.Host(config.host),
            port: port,
            using: .tcp
        )

        try await withTimeout(config.timeoutSeconds) {
            try await withCheckedThrowingContinuation { continuation in
                newConnection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        newConnection.stateUpdateHandler = nil
                        continuation.resume()
                    case .failed(let error):
                        newConnection.stateUpdateHandler = nil
                        continuation.resume(throwing: ModbusError.connectionFailed(String(describing: error)))
                    case .cancelled:
                        newConnection.stateUpdateHandler = nil
                        continuation.resume(throwing: ModbusError.connectionClosed)
                    default:
                        break
                    }
                }

                newConnection.start(queue: DispatchQueue.global(qos: .userInitiated))
            }
        }

        connection = newConnection
    }

    private func buildADU(transactionId: UInt16, pdu: Data) -> Data {
        var adu = Data()
        adu.append(contentsOf: [UInt8(transactionId >> 8), UInt8(transactionId & 0xFF)])
        adu.append(contentsOf: [0x00, 0x00]) // Protocol ID = 0 for Modbus TCP.

        let length = UInt16(1 + pdu.count)
        adu.append(contentsOf: [UInt8(length >> 8), UInt8(length & 0xFF)])
        adu.append(config.unitId)
        adu.append(pdu)
        return adu
    }

    private func send(data: Data, on connection: NWConnection) async throws {
        try await withTimeout(config.timeoutSeconds) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: ModbusError.connectionFailed(String(describing: error)))
                    } else {
                        continuation.resume()
                    }
                })
            }
        }
    }

    private func receiveExactly(count: Int, on connection: NWConnection) async throws -> Data {
        var buffer = Data()
        buffer.reserveCapacity(count)

        while buffer.count < count {
            let remaining = count - buffer.count
            let chunk = try await withTimeout(config.timeoutSeconds) {
                try await self.receiveChunk(maxLength: remaining, on: connection)
            }

            if chunk.isEmpty {
                throw ModbusError.connectionClosed
            }
            buffer.append(chunk)
        }

        return buffer
    }

    private func receiveChunk(maxLength: Int, on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: ModbusError.connectionFailed(String(describing: error)))
                    return
                }

                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }

                if isComplete {
                    continuation.resume(returning: Data())
                    return
                }

                continuation.resume(returning: Data())
            }
        }
    }

    private func withTimeout<T>(
        _ timeoutSeconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                let ns = UInt64(timeoutSeconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw ModbusError.timeout
            }

            let result = try await group.next()
            group.cancelAll()
            guard let result else { throw ModbusError.timeout }
            return result
        }
    }
#endif

    private func buildReadHoldingPDU(startAddress: UInt16, quantity: UInt16) -> Data {
        var d = Data([0x03])
        d.append(contentsOf: [UInt8(startAddress >> 8), UInt8(startAddress & 0xFF)])
        d.append(contentsOf: [UInt8(quantity >> 8), UInt8(quantity & 0xFF)])
        return d
    }

    private func buildWriteSinglePDU(address: UInt16, value: UInt16) -> Data {
        var d = Data([0x06])
        d.append(contentsOf: [UInt8(address >> 8), UInt8(address & 0xFF)])
        d.append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
        return d
    }

    private func parseReadHoldingResponse(response: Data, quantity: UInt16) throws -> [UInt16] {
        guard response.count >= 2 else { throw ModbusError.invalidResponse }
        let fn = response[0]
        if fn == 0x83 {
            guard response.count >= 2 else { throw ModbusError.invalidResponse }
            throw ModbusError.exception(code: response[1])
        }
        guard fn == 0x03 else { throw ModbusError.invalidResponse }
        let byteCount = Int(response[1])
        guard byteCount == Int(quantity) * 2 else { throw ModbusError.invalidResponse }
        guard response.count == 2 + byteCount else { throw ModbusError.invalidResponse }

        var out: [UInt16] = []
        out.reserveCapacity(Int(quantity))
        for i in stride(from: 2, to: response.count, by: 2) {
            let hi = UInt16(response[i])
            let lo = UInt16(response[i + 1])
            out.append((hi << 8) | lo)
        }
        return out
    }

    private func parseWriteSingleResponse(response: Data) throws -> Bool {
        guard response.count >= 5 else { throw ModbusError.invalidResponse }
        let fn = response[0]
        if fn == 0x86 {
            throw ModbusError.exception(code: response[1])
        }
        guard fn == 0x06 else { throw ModbusError.invalidResponse }
        return true
    }

    private func nextTxId() -> UInt16 {
        defer { txId = txId == .max ? 1 : txId + 1 }
        return txId
    }
}
