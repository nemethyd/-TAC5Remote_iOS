import SwiftUI
import Foundation
import TAC5Core

@MainActor
final class ConnectionViewModel: ObservableObject {
    @Published var host = "192.168.1.50"
    @Published var port = "502"
    @Published var unitId = "1"
    @Published var statusText = "Disconnected"
    @Published var snapshot = TAC5Snapshot()
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var cloudUploadEnabled = false {
        didSet {
            if !cloudUploadEnabled {
                cloudStatusText = "Cloud disabled"
            }
        }
    }
    @Published var cloudEndpoint = "https://example.com/api/tac5/snapshots"
    @Published var cloudApiKey = ""
    @Published var cloudStatusText = "Cloud disabled"

    private var client: ModbusTCPClient?
    private var repository: TAC5Repository?
    private let cloudSyncService: SnapshotCloudSyncing

    init(cloudSyncService: SnapshotCloudSyncing = HTTPSnapshotCloudSyncService()) {
        self.cloudSyncService = cloudSyncService
    }

    func connect() async {
        guard !isBusy else { return }
        guard let parsedPort = UInt16(port), let parsedUnitId = UInt8(unitId) else {
            statusText = "Invalid port or unit ID"
            return
        }

        isBusy = true
        statusText = "Connecting..."

        let config = ModbusTCPConfig(
            host: host,
            port: parsedPort,
            unitId: parsedUnitId,
            timeoutSeconds: 3
        )

        let client = ModbusTCPClient(config: config)
        let repository = TAC5Repository(client: client)

        do {
            let freshSnapshot = try await repository.readSnapshot()
            self.client = client
            self.repository = repository
            self.snapshot = freshSnapshot
            self.isConnected = true
            self.statusText = "Connected"

            if cloudUploadEnabled {
                await syncSnapshotToCloud(snapshot: freshSnapshot, trigger: "connect")
            }
        } catch {
            self.statusText = "Connect/read failed: \(error.localizedDescription)"
            client.disconnect()
            self.isConnected = false
        }

        isBusy = false
    }

    func refresh() async {
        guard !isBusy, let repository else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let freshSnapshot = try await repository.readSnapshot()
            snapshot = freshSnapshot
            statusText = "Connected"

            if cloudUploadEnabled {
                await syncSnapshotToCloud(snapshot: freshSnapshot, trigger: "refresh")
            }
        } catch {
            statusText = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func syncNow() async {
        guard isConnected else {
            cloudStatusText = "Connect first"
            return
        }
        await syncSnapshotToCloud(snapshot: snapshot, trigger: "manual")
    }

    func disconnect() {
        client?.disconnect()
        client = nil
        repository = nil
        isConnected = false
        statusText = "Disconnected"
    }

    private func syncSnapshotToCloud(snapshot: TAC5Snapshot, trigger: String) async {
        guard cloudUploadEnabled else {
            cloudStatusText = "Cloud disabled"
            return
        }

        let parsedUnitId = UInt8(unitId) ?? 1
        cloudStatusText = "Cloud sync in progress..."

        do {
            try await cloudSyncService.upload(
                snapshot: snapshot,
                source: SnapshotSourceInfo(host: host, unitId: parsedUnitId, trigger: trigger),
                endpoint: cloudEndpoint,
                apiKey: cloudApiKey.isEmpty ? nil : cloudApiKey
            )
            cloudStatusText = "Cloud sync OK"
        } catch {
            cloudStatusText = "Cloud sync failed: \(error.localizedDescription)"
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ConnectionViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Host", text: $viewModel.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("Port", text: $viewModel.port)
                        .keyboardType(.numberPad)
                    TextField("Unit ID", text: $viewModel.unitId)
                        .keyboardType(.numberPad)

                    Button(viewModel.isConnected ? "Disconnect" : "Connect") {
                        if viewModel.isConnected {
                            viewModel.disconnect()
                        } else {
                            Task { await viewModel.connect() }
                        }
                    }
                    .disabled(viewModel.isBusy)

                    if viewModel.isConnected {
                        Button("Refresh") {
                            Task { await viewModel.refresh() }
                        }
                        .disabled(viewModel.isBusy)
                    }

                    Text(viewModel.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Cloud") {
                    Toggle("Enable cloud upload", isOn: $viewModel.cloudUploadEnabled)

                    TextField("Cloud endpoint", text: $viewModel.cloudEndpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)

                    SecureField("API key (optional)", text: $viewModel.cloudApiKey)

                    Button("Sync Now") {
                        Task { await viewModel.syncNow() }
                    }
                    .disabled(!viewModel.isConnected || !viewModel.cloudUploadEnabled || viewModel.isBusy)

                    Text(viewModel.cloudStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Telemetry") {
                    LabeledContent("T1", valueText(viewModel.snapshot.t1Celsius, suffix: " C"))
                    LabeledContent("T2", valueText(viewModel.snapshot.t2Celsius, suffix: " C"))
                    LabeledContent("T3", valueText(viewModel.snapshot.t3Celsius, suffix: " C"))
                    LabeledContent("T4", valueText(viewModel.snapshot.t4Celsius, suffix: " C"))
                    LabeledContent("Supply", valueText(viewModel.snapshot.supplyAirflowM3h, suffix: " m3/h"))
                    LabeledContent("Exhaust", valueText(viewModel.snapshot.exhaustAirflowM3h, suffix: " m3/h"))
                }
            }
            .navigationTitle("TAC5 Remote")
        }
    }

    private func valueText(_ value: Double?, suffix: String) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f%@", value, suffix)
    }
}
