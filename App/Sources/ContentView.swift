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
    @Published var bypassEnabled = false
    @Published var operationMode: TAC5OperationMode = .ca
    @Published var selectedPreset: TAC5Preset = .k1
    @Published var presetTargetByPreset: [TAC5Preset: UInt16] = [:]
    @Published var traceLogURL: URL?
    @Published var traceEnabled = true

    private var client: ModbusTCPClient?
    private var repository: TAC5Repository?
    private var isRefreshing = false
    private var suppressRefreshUntil: Date = .distantPast
    private let traceEnabledDefaultsKey = "trace.enabled"

    init() {
        loadTracePreference()
        initializeTraceLog()
    }

    func connect() async {
        guard !isBusy else { return }
        let connection: (host: String, port: UInt16, unitId: UInt8)
        do {
            connection = try parseConnectionTarget()
        } catch {
            statusText = "Invalid connection format. Example: 192.168.10.80:502:1"
            trace("connect failed: invalid connection format: \(connectionTarget)")
            return
        }

        isBusy = true
        defer { isBusy = false }
        statusText = "Connecting..."
        trace("connect start host=\(connection.host) port=\(connection.port) unit=\(connection.unitId)")

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
            let boostState = try? await repository.readBoostEnabled()
            let bypassState = try? await repository.readBypassEnabled()
            let mode = try? await repository.readOperationMode()
            let preset = try? await repository.readPreset()
            let activeTarget = try? await repository.readActivePresetTargetAirflow()
            self.client = client
            self.repository = repository
            self.snapshot = freshSnapshot
            if let boostState {
                self.boostEnabled = boostState
            }
            if let bypassState {
                self.bypassEnabled = bypassState
            }
            if let mode {
                self.operationMode = mode
            }
            if let preset {
                self.selectedPreset = preset
                if let activeTarget {
                    self.presetTargetByPreset[preset] = activeTarget
                }
            }
            self.isConnected = true
            self.statusText = "Connected"
            trace("connect success")
        } catch {
            self.statusText = "Connect/read failed: \(error.localizedDescription)"
            trace("connect failed: \(error.localizedDescription)")
            await client.disconnect()
            self.isConnected = false
        }
    }

    func refresh(updateStatus: Bool = true) async {
        guard !isBusy, !isRefreshing, Date() >= suppressRefreshUntil, let repository else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let freshSnapshot = try await repository.readSnapshot()
            let boostState = try? await repository.readBoostEnabled()
            let bypassState = try? await repository.readBypassEnabled()
            let mode = try? await repository.readOperationMode()
            let preset = try? await repository.readPreset()
            let activeTarget = try? await repository.readActivePresetTargetAirflow()
            snapshot = freshSnapshot
            if let boostState {
                self.boostEnabled = boostState
            }
            if let bypassState {
                self.bypassEnabled = bypassState
            }
            if let mode {
                self.operationMode = mode
            }
            if let preset {
                self.selectedPreset = preset
                if let activeTarget {
                    self.presetTargetByPreset[preset] = activeTarget
                }
            }
            if updateStatus {
                statusText = "Refreshed"
            }
            trace("refresh success")
        } catch {
            if updateStatus {
                statusText = "Refresh failed: \(error.localizedDescription)"
            }
            trace("refresh failed: \(error.localizedDescription)")
        }
    }

    func disconnect() async {
        await client?.disconnect()
        client = nil
        repository = nil
        isConnected = false
        boostEnabled = false
        bypassEnabled = false
        operationMode = .ca
        selectedPreset = .k1
        presetTargetByPreset = [:]
        statusText = "Disconnected"
        trace("disconnect")
    }

    func setBoostEnabled(_ enabled: Bool) async {
        guard !isBusy, isConnected, let repository else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await repository.writeBoostEnabled(enabled)
            // Some units accept write but reject immediate readback for this register.
            boostEnabled = enabled
            if let readBack = try? await repository.readBoostEnabled() {
                boostEnabled = readBack
            }
            statusText = boostEnabled ? "Boost enabled" : "Boost disabled"
            trace("boost write success value=\(boostEnabled ? 1 : 0)")
        } catch {
            statusText = "Boost write failed: \(error.localizedDescription)"
            trace("boost write failed: \(error.localizedDescription)")
        }
    }

    func setPreset(_ preset: TAC5Preset) async {
        guard !isBusy, isConnected else { return }
        guard selectedPreset != preset else { return }
        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            guard let repository else { throw ModbusError.connectionClosed }
            do {
                try await repository.writePreset(preset)
            } catch {
                if isTransientPresetError(error) {
                    trace("preset transient error; retrying once: \(error.localizedDescription)")
                    suppressRefreshUntil = Date().addingTimeInterval(4.0)
                    await reconnectAfterTransientPresetError()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard let retryRepository = self.repository else {
                        throw ModbusError.connectionClosed
                    }
                    try await retryRepository.writePreset(preset)
                } else {
                    throw error
                }
            }
            selectedPreset = preset
            // Match Eole behavior: do not force immediate readback right after preset write.
            // The periodic refresh loop will update PRESET_STATE and airflow once the unit settles.
            statusText = "Preset: \(selectedPreset.label)"
            trace("preset switch success value=\(selectedPreset.rawValue)")
        } catch {
            statusText = "Preset switch failed: \(error.localizedDescription)"
            trace("preset switch failed: \(error.localizedDescription)")
        }
    }

    func setBypassEnabled(_ enabled: Bool) async {
        guard !isBusy, isConnected, let repository else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await repository.writeBypassEnabled(enabled)
            // Some units accept write but reject immediate readback for this register.
            bypassEnabled = enabled
            if let readBack = try? await repository.readBypassEnabled() {
                bypassEnabled = readBack
            }
            statusText = bypassEnabled ? "Bypass enabled" : "Bypass disabled"
            trace("bypass write success value=\(bypassEnabled ? 1 : 0)")
        } catch {
            statusText = "Bypass write failed: \(error.localizedDescription)"
            trace("bypass write failed: \(error.localizedDescription)")
        }
    }

    func setOperationMode(_ mode: TAC5OperationMode) async {
        guard !isBusy, isConnected, let repository else { return }
        guard operationMode != mode else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await repository.writeOperationMode(mode)
            operationMode = mode
            if let readBack = try? await repository.readOperationMode() {
                operationMode = readBack
            }
            statusText = "Mode: \(operationMode.label)"
            trace("mode switch success value=\(operationMode.rawValue)")
        } catch {
            statusText = "Mode switch failed: \(error.localizedDescription)"
            trace("mode switch failed: \(error.localizedDescription)")
        }
    }

    func clearTraceLog() {
        guard let traceLogURL else { return }
        do {
            try "".write(to: traceLogURL, atomically: true, encoding: .utf8)
            trace("trace log cleared")
            statusText = "Trace log cleared"
        } catch {
            statusText = "Trace clear failed: \(error.localizedDescription)"
            trace("trace clear failed: \(error.localizedDescription)")
        }
    }

    func setTraceEnabled(_ enabled: Bool) {
        traceEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: traceEnabledDefaultsKey)
        if enabled {
            trace("trace logging enabled")
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

    private func isTransientPresetError(_ error: Error) -> Bool {
        guard let modbusError = error as? ModbusError else { return false }
        switch modbusError {
        case .invalidResponse, .timeout, .connectionFailed, .connectionClosed:
            return true
        default:
            return false
        }
    }

    private func reconnectAfterTransientPresetError() async {
        do {
            let connection = try parseConnectionTarget()
            await client?.disconnect()

            let config = ModbusTCPConfig(
                host: connection.host,
                port: connection.port,
                unitId: connection.unitId,
                timeoutSeconds: 4
            )

            let newClient = ModbusTCPClient(config: config)
            let newRepository = TAC5Repository(client: newClient)
            _ = try await newRepository.readPreset()
            self.client = newClient
            self.repository = newRepository
            self.isConnected = true
            trace("preset retry reconnect success")
        } catch {
            trace("preset retry reconnect failed: \(error.localizedDescription)")
        }
    }

    private func initializeTraceLog() {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        let url = cacheDir.appendingPathComponent("tac5_trace.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        traceLogURL = url

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        trace("session start app=\(appVersion) build=\(buildNumber)")
    }

    private func loadTracePreference() {
        if UserDefaults.standard.object(forKey: traceEnabledDefaultsKey) == nil {
            traceEnabled = true
            return
        }
        traceEnabled = UserDefaults.standard.bool(forKey: traceEnabledDefaultsKey)
    }

    private func trace(_ message: String) {
        guard traceEnabled else { return }
        guard let traceLogURL else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            let handle = try FileHandle(forWritingTo: traceLogURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Keep trace logging non-fatal for app behavior.
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ConnectionViewModel()
    @State private var isShowingSettings = false

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
                TextField("Example: 192.168.10.80:502:1", text: $viewModel.connectionTarget)
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
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isBusy)

                    Button("Close") {
                        Task {
                            if viewModel.isConnected {
                                await viewModel.disconnect()
                            }
                            let didClose = await MainActor.run { closeApplication() }
                            if !didClose {
                                await MainActor.run {
                                    viewModel.statusText = "Disconnected. iOS may not allow app close from button."
                                }
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
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
                }

                HStack {
                    Button {
                        Task { await viewModel.setBoostEnabled(!viewModel.boostEnabled) }
                    } label: {
                        ModeToggleLabel(
                            title: "Boost",
                            systemImage: "bolt.fill",
                            isOn: viewModel.boostEnabled,
                            accent: .green
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.isConnected || viewModel.isBusy)

                    Button {
                        Task { await viewModel.setBypassEnabled(!viewModel.bypassEnabled) }
                    } label: {
                        ModeToggleLabel(
                            title: "Bypass",
                            systemImage: "arrow.triangle.branch",
                            isOn: viewModel.bypassEnabled,
                            accent: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.isConnected || viewModel.isBusy)
                }

                if viewModel.traceEnabled {
                    HStack {
                        if let traceURL = viewModel.traceLogURL {
                            ShareLink(item: traceURL) {
                                Label("Export Trace", systemImage: "square.and.arrow.up")
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.bordered)
                        }

                        Button("Clear Trace") {
                            viewModel.clearTraceLog()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                    }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(viewModel: viewModel)
            }
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

    private func closeApplication() -> Bool {
#if canImport(UIKit)
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })

        let scene = activeScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        guard let scene else { return false }
        UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
        return true
    #else
        return false
#endif
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                tracingSection
                operationModeSection
                modeParametersSection
            }
            .navigationTitle("Settings")
            .toolbar {
                doneToolbarItem
            }
        }
    }

    private var tracingSection: some View {
        Section("Tracing") {
            Toggle("Enable Trace Logging", isOn: traceToggleBinding)

            Text("When trace logging is off, trace export and clear buttons are hidden on the main screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var operationModeSection: some View {
        Section("Operation Mode") {
            modeButtonRow

            Text("Current mode: \(viewModel.operationMode.label)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(viewModel.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var modeParametersSection: some View {
        Section("Mode Parameters") {
            if viewModel.operationMode == .ca {
                CAModeParametersPreview()
            } else {
                Text("No mapped editable parameters for \(viewModel.operationMode.label) yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modeButtonRow: some View {
        HStack(spacing: 8) {
            ForEach(TAC5OperationMode.allCases, id: \.rawValue) { mode in
                modeButton(for: mode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func modeButton(for mode: TAC5OperationMode) -> some View {
        if viewModel.operationMode == mode {
            Button(mode.label) {
                Task { await viewModel.setOperationMode(mode) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        } else {
            Button(mode.label) {
                Task { await viewModel.setOperationMode(mode) }
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isConnected || viewModel.isBusy)
        }
    }

    private var traceToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.traceEnabled },
            set: { viewModel.setTraceEnabled($0) }
        )
    }

    private var doneToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") {
                dismiss()
            }
        }
    }
}

private struct CAModeParametersPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            parameterLine(title: "Exhaust / Supply Ratio", supplyValue: "100", exhaustValue: nil, unit: "%")

            HStack {
                Text("Parameter")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Supply")
                    .font(.caption.weight(.semibold))
                    .frame(width: 72, alignment: .center)
                Text("Exhaust")
                    .font(.caption.weight(.semibold))
                    .frame(width: 72, alignment: .center)
            }

            parameterLine(title: "Airflow I", supplyValue: "200", exhaustValue: "200", unit: "m3/h")
            parameterLine(title: "Airflow II", supplyValue: "300", exhaustValue: "300", unit: "m3/h")
            parameterLine(title: "Airflow III", supplyValue: "400", exhaustValue: "400", unit: "m3/h")

            Text("Layout preview only. Register mapping and write actions will be added after per-mode tests.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func parameterLine(title: String, supplyValue: String, exhaustValue: String?, unit: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            valueBox(supplyValue)

            if let exhaustValue {
                valueBox(exhaustValue)
            }

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }

    private func valueBox(_ value: String) -> some View {
        Text(value)
            .font(.body.monospacedDigit())
            .frame(width: 72, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
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

private struct ModeToggleLabel: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                Text(isOn ? "ON" : "OFF")
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? accent : Color.gray.opacity(0.14))
        )
    }
}
