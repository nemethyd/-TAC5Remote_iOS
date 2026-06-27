import SwiftUI
import Foundation
import TAC5Core
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ConnectionViewModel: ObservableObject {
    @Published var connectionTarget = "192.168.10.80:502:1"
    @Published var statusText = "Disconnected"
    @Published var snapshot = TAC5Snapshot()
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var boostEnabled = false
    @Published var selectedPreset: TAC5Preset = .k1
    @Published var presetTargetByPreset: [TAC5Preset: UInt16] = [:]

    private var client: ModbusTCPClient?
    private var repository: TAC5Repository?
    private var isRefreshing = false

    func connect() async {
        guard !isBusy else { return }
        let connection: (host: String, port: UInt16, unitId: UInt8)
        do {
            connection = try parseConnectionTarget()
        } catch {
            statusText = "Hibas kapcsolat formatum. Minta: 192.168.10.80:502:1"
            return
        }

        isBusy = true
        defer { isBusy = false }
        statusText = "Connecting..."

        let config = ModbusTCPConfig(
            host: connection.host,
            port: connection.port,
            unitId: connection.unitId,
            timeoutSeconds: 3
        )

        let client = ModbusTCPClient(config: config)
        let repository = TAC5Repository(client: client)

        do {
            let freshSnapshot = try await withConnectTimeout(seconds: 8) {
                try await repository.readSnapshot()
            }
            let boostState = try await repository.readBoostEnabled()
            let preset = try await repository.readPreset()
            let activeTarget = try await repository.readActivePresetTargetAirflow()
            self.client = client
            self.repository = repository
            self.snapshot = freshSnapshot
            if let boostState {
                self.boostEnabled = boostState
            }
            if let preset {
                self.selectedPreset = preset
                if let activeTarget {
                    self.presetTargetByPreset[preset] = activeTarget
                }
            }
            self.isConnected = true
            self.statusText = "Kapcsolodva"
        } catch {
            self.statusText = "Sikertelen kapcsolat vagy olvasas: \(error.localizedDescription)"
            await client.disconnect()
            self.isConnected = false
        }
    }

    func refresh(updateStatus: Bool = true) async {
        guard !isBusy, !isRefreshing, let repository else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let freshSnapshot = try await repository.readSnapshot()
            let boostState = try await repository.readBoostEnabled()
            let preset = try await repository.readPreset()
            let activeTarget = try await repository.readActivePresetTargetAirflow()
            snapshot = freshSnapshot
            if let boostState {
                self.boostEnabled = boostState
            }
            if let preset {
                self.selectedPreset = preset
                if let activeTarget {
                    self.presetTargetByPreset[preset] = activeTarget
                }
            }
            if updateStatus {
                statusText = "Frissitve"
            }
        } catch {
            if updateStatus {
                statusText = "Sikertelen frissites: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() async {
        await client?.disconnect()
        client = nil
        repository = nil
        isConnected = false
        boostEnabled = false
        selectedPreset = .k1
        presetTargetByPreset = [:]
        statusText = "Lecsatlakozva"
    }

    func setBoostEnabled(_ enabled: Bool) async {
        guard !isBusy, isConnected, let repository else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await repository.writeBoostEnabled(enabled)
            let readBack = try await repository.readBoostEnabled()
            boostEnabled = readBack ?? enabled
            statusText = boostEnabled ? "Boost bekapcsolva" : "Boost kikapcsolva"
        } catch {
            statusText = "Sikertelen Boost iras: \(error.localizedDescription)"
        }
    }

    func setPreset(_ preset: TAC5Preset) async {
        guard !isBusy, isConnected, let repository else { return }
        guard selectedPreset != preset else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await repository.writePreset(preset)
            let readBack = try await repository.readPreset()
            let activeTarget = try await repository.readActivePresetTargetAirflow()
            selectedPreset = readBack ?? preset
            if let activeTarget {
                presetTargetByPreset[selectedPreset] = activeTarget
            }
            statusText = "Preset: \(selectedPreset.label)"
        } catch {
            statusText = "Sikertelen preset valtas: \(error.localizedDescription)"
        }
    }

    private func withConnectTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ModbusError.timeout
            }

            guard let result = try await group.next() else {
                throw ModbusError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private func parseConnectionTarget() throws -> (host: String, port: UInt16, unitId: UInt8) {
        let parts = connectionTarget
            .split(separator: ":", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard parts.count == 3, !parts[0].isEmpty else { throw ModbusError.invalidResponse }
        guard let port = UInt16(parts[1]), let unitId = UInt8(parts[2]) else { throw ModbusError.invalidResponse }
        return (host: parts[0], port: port, unitId: unitId)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ConnectionViewModel()

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return v
    }

    private var buildNumber: String {
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return b
    }

    private var buildInfo: String {
        return "v\(appVersion) (#\(buildNumber))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Pelda: 192.168.10.80:502:1", text: $viewModel.connectionTarget)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(viewModel.isConnected ? "Disconnect" : "Connect") {
                        if viewModel.isConnected {
                            Task { await viewModel.disconnect() }
                        } else {
                            Task { await viewModel.connect() }
                        }
                    }
                    .disabled(viewModel.isBusy)
                }

                HStack {
                    ForEach(TAC5Preset.allCases, id: \.rawValue) { preset in
                        Button {
                            Task { await viewModel.setPreset(preset) }
                        } label: {
                            PresetButtonLabel(
                                preset: preset,
                                targetM3h: viewModel.presetTargetByPreset[preset],
                                isSelected: viewModel.selectedPreset == preset
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.isConnected || viewModel.isBusy || viewModel.selectedPreset == preset)
                    }

                    Button(viewModel.boostEnabled ? "Boost ON" : "Boost OFF") {
                        Task { await viewModel.setBoostEnabled(!viewModel.boostEnabled) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.boostEnabled ? .green : .gray)
                    .disabled(!viewModel.isConnected || viewModel.isBusy)

                    Button("Close") {
                        Task {
                            if viewModel.isConnected {
                                await viewModel.disconnect()
                            }
                            await MainActor.run {
                                closeApplication()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Text(viewModel.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metricCard("Outdoor", valueText(viewModel.snapshot.t1Celsius, suffix: " C"))
                    metricCard("Supply", valueText(viewModel.snapshot.t2Celsius, suffix: " C"))
                    metricCard("Extract", valueText(viewModel.snapshot.t3Celsius, suffix: " C"))
                    metricCard("Exhaust", valueText(viewModel.snapshot.t7Celsius, suffix: " C"))
                    metricCard("Supply Airflow", valueText(viewModel.snapshot.supplyAirflowM3h, suffix: " m3/h"))
                    metricCard("Exhaust Airflow", valueText(viewModel.snapshot.exhaustAirflowM3h, suffix: " m3/h"))
                }

                Spacer(minLength: 0)

                Text(buildInfo)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
            .navigationTitle("TAC5 Remote")
            .task(id: viewModel.isConnected) {
                guard viewModel.isConnected else { return }
                while !Task.isCancelled && viewModel.isConnected {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await viewModel.refresh(updateStatus: false)
                }
            }
        }
    }

    @ViewBuilder
    private func metricCard(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func valueText(_ value: Double?, suffix: String) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f%@", value, suffix)
    }

    private func closeApplication() {
#if canImport(UIKit)
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })

        let scene = activeScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        guard let scene else { return }
        UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
#endif
    }
}

private struct PresetButtonLabel: View {
    let preset: TAC5Preset
    let targetM3h: UInt16?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            FanLevelIcon(blades: bladeCount)
            Text(targetText)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(minWidth: 58)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }

    private var bladeCount: Int {
        switch preset {
        case .k1: return 3
        case .k2: return 4
        case .k3: return 5
        }
    }

    private var targetText: String {
        if let targetM3h {
            return "\(targetM3h) m3/h"
        }
        return preset.label
    }
}

private struct FanLevelIcon: View {
    let blades: Int

    var body: some View {
        ZStack {
            ForEach(0..<blades, id: \.self) { index in
                Circle()
                    .fill(Color.primary)
                    .frame(width: 8, height: 16)
                    .offset(y: -7)
                    .rotationEffect(.degrees((360.0 / Double(blades)) * Double(index)))
            }

            Circle()
                .fill(Color.primary)
                .frame(width: 5, height: 5)
        }
        .frame(width: 24, height: 24)
    }
}
