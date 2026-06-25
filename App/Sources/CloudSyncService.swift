import Foundation
import TAC5Core

public enum CloudSyncError: Error, LocalizedError {
    case invalidEndpoint
    case uploadFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid cloud endpoint URL"
        case .uploadFailed(let statusCode):
            return "Cloud upload failed with status code \(statusCode)"
        }
    }
}

public struct SnapshotSourceInfo: Codable, Sendable {
    public let host: String
    public let unitId: UInt8
    public let trigger: String

    public init(host: String, unitId: UInt8, trigger: String) {
        self.host = host
        self.unitId = unitId
        self.trigger = trigger
    }
}

public protocol SnapshotCloudSyncing: Sendable {
    func upload(
        snapshot: TAC5Snapshot,
        source: SnapshotSourceInfo,
        endpoint: String,
        apiKey: String?
    ) async throws
}

public actor HTTPSnapshotCloudSyncService: SnapshotCloudSyncing {
    public init() {}

    public func upload(
        snapshot: TAC5Snapshot,
        source: SnapshotSourceInfo,
        endpoint: String,
        apiKey: String?
    ) async throws {
        guard let url = URL(string: endpoint), let scheme = url.scheme, (scheme == "https" || scheme == "http") else {
            throw CloudSyncError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload = SnapshotUploadPayload(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            source: source,
            snapshot: SnapshotPayload(from: snapshot)
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudSyncError.uploadFailed(statusCode: -1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudSyncError.uploadFailed(statusCode: httpResponse.statusCode)
        }
    }
}

private struct SnapshotUploadPayload: Codable {
    let timestamp: String
    let source: SnapshotSourceInfo
    let snapshot: SnapshotPayload
}

private struct SnapshotPayload: Codable {
    let t1Celsius: Double?
    let t2Celsius: Double?
    let t3Celsius: Double?
    let t4Celsius: Double?
    let supplyAirflowM3h: Double?
    let exhaustAirflowM3h: Double?

    init(from snapshot: TAC5Snapshot) {
        t1Celsius = snapshot.t1Celsius
        t2Celsius = snapshot.t2Celsius
        t3Celsius = snapshot.t3Celsius
        t4Celsius = snapshot.t4Celsius
        supplyAirflowM3h = snapshot.supplyAirflowM3h
        exhaustAirflowM3h = snapshot.exhaustAirflowM3h
    }
}
