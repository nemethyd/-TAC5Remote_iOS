import SwiftUI
import Foundation
import TAC5Core
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ConnectionViewModel: ObservableObject {
    private let exhaustSupplyRatioLimits = 50...200
    private let lsVoltageLimits = 0...100
    private let lsAirflowLimits = 100...840
    private let lsSleepFactorLimits = 0...100

    @Published var connectionTarget = "192.168.10.80:502:1"
    @Published var statusText = "Disconnected"
    @Published var snapshot = TAC5Snapshot()
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var isConnecting = false
    @Published var boostEnabled = false
    @Published var bypassEnabled = false
    @Published var exhaustSupplyRatio: Double?
    @Published var caAirflowI: UInt16?
    @Published var caAirflowII: UInt16?
    @Published var caAirflowIII: UInt16?
    @Published var lsVmin: UInt16?
    @Published var lsVmax: UInt16?
    @Published var lsAirflowAtVmin: UInt16?
    @Published var lsAirflowAtVmax: UInt16?
    @Published var lsStopIfBelowVlow = false
    @Published var lsVlow: UInt16?
    @Published var lsStopIfAboveVhigh = false
    @Published var lsVhigh: UInt16?
    @Published var lsK3Mode: TAC5LSK3Mode = .no
    @Published var lsK3SleepFactor: UInt16?
    @Published var cpOnMode: TAC5CPOnMode = .supply
    @Published var cpSupplyVoltage: UInt16?
    @Published var cpExhaustVoltage: UInt16?
    @Published var cpStartAirflow: UInt16?
    @Published var operationMode: TAC5OperationMode = .ca
    @Published var deviceClockDate: Date?
    @Published var deviceClockWeekday: UInt16?
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
        guard !isBusy, !isConnecting, !isRefreshing else { return }
        let connection: (host: String, port: UInt16, unitId: UInt8)
        do {
            connection = try parseConnectionTarget()
        } catch {
            statusText = "Invalid connection format. Use IP, IP:Port, IP::Unit, or IP:Port:Unit"
            trace("connect failed: invalid connection format: \(connectionTarget)")
            return
        }

        isBusy = true
        isConnecting = true
        defer {
            isBusy = false
            isConnecting = false
        }
        statusText = "Connecting..."
        trace("connect start host=\(connection.host) port=\(connection.port) unit=\(connection.unitId)")

        await client?.disconnect()
        client = nil
        repository = nil

        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            statusText = "Connecting... (\(attempt)/\(maxAttempts))"

            let config = ModbusTCPConfig(
                host: connection.host,
                port: connection.port,
                unitId: connection.unitId,
                timeoutSeconds: 3
            )

            let attemptClient = ModbusTCPClient(config: config)
            let attemptRepository = TAC5Repository(client: attemptClient)

            do {
                let timeout = 8.0 + (Double(attempt - 1) * 2.0)
                trace("attempt=\(attempt) readSnapshot start (timeout=\(timeout)s)")
                let snapshotStart = Date()
                let freshSnapshot = try await withConnectTimeout(seconds: timeout) {
                    try await attemptRepository.readSnapshot()
                }
                trace("attempt=\(attempt) readSnapshot ok (\(String(format: "%.2f", Date().timeIntervalSince(snapshotStart)))s)")
                let boostRaw = await tracedRead("boostRaw") { try await attemptRepository.readBoostRaw() }
                let bypassState = await tracedRead("bypassState") { try await attemptRepository.readBypassEnabled() }
                let ratioState = await tracedRead("ratioState") { try await attemptRepository.readExhaustSupplyRatio() }
                let caAirflowI = await tracedRead("caAirflowI") { try await attemptRepository.readCaAirflowI() }
                let caAirflowII = await tracedRead("caAirflowII") { try await attemptRepository.readCaAirflowII() }
                let caAirflowIII = await tracedRead("caAirflowIII") { try await attemptRepository.readCaAirflowIII() }
                let lsVmin = await tracedRead("lsVmin") { try await attemptRepository.readLsVmin() }
                let lsVmax = await tracedRead("lsVmax") { try await attemptRepository.readLsVmax() }
                let lsAirflowAtVmin = await tracedRead("lsAirflowAtVmin") { try await attemptRepository.readLsAirflowAtVmin() }
                let lsAirflowAtVmax = await tracedRead("lsAirflowAtVmax") { try await attemptRepository.readLsAirflowAtVmax() }
                let lsStopIfBelowVlow = await tracedRead("lsStopIfBelowVlow") { try await attemptRepository.readLsStopIfBelowVlow() }
                let lsVlow = await tracedRead("lsVlow") { try await attemptRepository.readLsVlow() }
                let lsStopIfAboveVhigh = await tracedRead("lsStopIfAboveVhigh") { try await attemptRepository.readLsStopIfAboveVhigh() }
                let lsVhigh = await tracedRead("lsVhigh") { try await attemptRepository.readLsVhigh() }
                let lsK3Mode = await tracedRead("lsK3Mode") { try await attemptRepository.readLsK3Mode() }
                let lsK3SleepFactor = await tracedRead("lsK3SleepFactor") { try await attemptRepository.readLsK3SleepFactor() }
                let cpOnMode = await tracedRead("cpOnMode") { try await attemptRepository.readCpOnMode() }
                let cpSupplyVoltage = await tracedRead("cpSupplyVoltage") { try await attemptRepository.readCpSupplyVoltage() }
                let cpExhaustVoltage = await tracedRead("cpExhaustVoltage") { try await attemptRepository.readCpExhaustVoltage() }
                let cpStartAirflow = await tracedRead("cpStartAirflow") { try await attemptRepository.readCpStartAirflow() }
                let mode = await tracedRead("operationMode") { try await attemptRepository.readOperationMode() }
                let preset = await tracedRead("preset") { try await attemptRepository.readPreset() }
                let activeTarget = await tracedRead("activeTarget") { try await attemptRepository.readActivePresetTargetAirflow() }
                let clockSettings = await tracedRead("clockSettings") { try await attemptRepository.readClockSettings() }
                trace("attempt=\(attempt) all post-snapshot reads done")


                self.client = attemptClient
                self.repository = attemptRepository
                self.snapshot = freshSnapshot
                if let boostRaw {
                    self.boostEnabled = boostRaw != 0
                    trace("monitor 227 boost=\(boostRaw)")
                }
                if let bypassState {
                    self.bypassEnabled = bypassState
                }
                if let ratioState {
                    self.exhaustSupplyRatio = Double(ratioState)
                }
                if let caAirflowI {
                    self.caAirflowI = caAirflowI
                }
                if let caAirflowII {
                    self.caAirflowII = caAirflowII
                }
                if let caAirflowIII {
                    self.caAirflowIII = caAirflowIII
                }
                if let lsVmin {
                    self.lsVmin = lsVmin
                }
                if let lsVmax {
                    self.lsVmax = lsVmax
                }
                if let lsAirflowAtVmin {
                    self.lsAirflowAtVmin = lsAirflowAtVmin
                }
                if let lsAirflowAtVmax {
                    self.lsAirflowAtVmax = lsAirflowAtVmax
                }
                if let lsStopIfBelowVlow {
                    self.lsStopIfBelowVlow = lsStopIfBelowVlow
                }
                if let lsVlow {
                    self.lsVlow = lsVlow
                }
                if let lsStopIfAboveVhigh {
                    self.lsStopIfAboveVhigh = lsStopIfAboveVhigh
                }
                if let lsVhigh {
                    self.lsVhigh = lsVhigh
                }
                if let lsK3Mode {
                    self.lsK3Mode = lsK3Mode
                }
                if let lsK3SleepFactor {
                    self.lsK3SleepFactor = lsK3SleepFactor
                }
                if let cpOnMode {
                    self.cpOnMode = cpOnMode
                }
                if let cpSupplyVoltage {
                    self.cpSupplyVoltage = cpSupplyVoltage
                }
                if let cpExhaustVoltage {
                    self.cpExhaustVoltage = cpExhaustVoltage
                }
                if let cpStartAirflow {
                    self.cpStartAirflow = cpStartAirflow
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
                if let clockSettings {
                    self.applyClockSettings(clockSettings)
                }

                self.isConnected = true
                self.statusText = "Connected"
                trace("connect success attempt=\(attempt)")
                return
            } catch {
                lastError = error
                trace("connect attempt \(attempt) failed: \(error.localizedDescription)")
                await attemptClient.disconnect()

                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(Double(attempt) * 350_000_000))
                }
            }
        }

        self.isConnected = false
        let failureDescription = lastError?.localizedDescription ?? "Connection failed"
        self.statusText = "Connect/read failed: \(failureDescription)"
        trace("connect failed after retries: \(failureDescription)")
    }

    func refresh(updateStatus: Bool = true) async {
        guard !isBusy, !isRefreshing, Date() >= suppressRefreshUntil, let repository else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let freshSnapshot = try await repository.readSnapshot()
            let boostRaw = await pacedRead { try await repository.readBoostRaw() }
            let bypassState = await pacedRead { try await repository.readBypassEnabled() }
            let ratioState = await pacedRead { try await repository.readExhaustSupplyRatio() }
            let caAirflowI = await pacedRead { try await repository.readCaAirflowI() }
            let caAirflowII = await pacedRead { try await repository.readCaAirflowII() }
            let caAirflowIII = await pacedRead { try await repository.readCaAirflowIII() }
            let lsVmin = await pacedRead { try await repository.readLsVmin() }
            let lsVmax = await pacedRead { try await repository.readLsVmax() }
            let lsAirflowAtVmin = await pacedRead { try await repository.readLsAirflowAtVmin() }
            let lsAirflowAtVmax = await pacedRead { try await repository.readLsAirflowAtVmax() }
            let lsStopIfBelowVlow = await pacedRead { try await repository.readLsStopIfBelowVlow() }
            let lsVlow = await pacedRead { try await repository.readLsVlow() }
            let lsStopIfAboveVhigh = await pacedRead { try await repository.readLsStopIfAboveVhigh() }
            let lsVhigh = await pacedRead { try await repository.readLsVhigh() }
            let lsK3Mode = await pacedRead { try await repository.readLsK3Mode() }
            let lsK3SleepFactor = await pacedRead { try await repository.readLsK3SleepFactor() }
            let cpOnMode = await pacedRead { try await repository.readCpOnMode() }
            let cpSupplyVoltage = await pacedRead { try await repository.readCpSupplyVoltage() }
            let cpExhaustVoltage = await pacedRead { try await repository.readCpExhaustVoltage() }
            let cpStartAirflow = await pacedRead { try await repository.readCpStartAirflow() }
            let mode = await pacedRead { try await repository.readOperationMode() }
            let preset = await pacedRead { try await repository.readPreset() }
            let activeTarget = await pacedRead { try await repository.readActivePresetTargetAirflow() }
            let clockSettings = await pacedRead { try await repository.readClockSettings() }
            snapshot = freshSnapshot
            if let boostRaw {
                self.boostEnabled = boostRaw != 0
                trace("monitor 227 boost=\(boostRaw)")
            }
            if let bypassState {
                self.bypassEnabled = bypassState
            }
            if let ratioState {
                self.exhaustSupplyRatio = Double(ratioState)
            }
            if let caAirflowI {
                self.caAirflowI = caAirflowI
            }
            if let caAirflowII {
                self.caAirflowII = caAirflowII
            }
            if let caAirflowIII {
                self.caAirflowIII = caAirflowIII
            }
            if let lsVmin {
                self.lsVmin = lsVmin
            }
            if let lsVmax {
                self.lsVmax = lsVmax
            }
            if let lsAirflowAtVmin {
                self.lsAirflowAtVmin = lsAirflowAtVmin
            }
            if let lsAirflowAtVmax {
                self.lsAirflowAtVmax = lsAirflowAtVmax
            }
            if let lsStopIfBelowVlow {
                self.lsStopIfBelowVlow = lsStopIfBelowVlow
            }
            if let lsVlow {
                self.lsVlow = lsVlow
            }
            if let lsStopIfAboveVhigh {
                self.lsStopIfAboveVhigh = lsStopIfAboveVhigh
            }
            if let lsVhigh {
                self.lsVhigh = lsVhigh
            }
            if let lsK3Mode {
                self.lsK3Mode = lsK3Mode
            }
            if let lsK3SleepFactor {
                self.lsK3SleepFactor = lsK3SleepFactor
            }
            if let cpOnMode {
                self.cpOnMode = cpOnMode
            }
            if let cpSupplyVoltage {
                self.cpSupplyVoltage = cpSupplyVoltage
            }
            if let cpExhaustVoltage {
                self.cpExhaustVoltage = cpExhaustVoltage
            }
            if let cpStartAirflow {
                self.cpStartAirflow = cpStartAirflow
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
            if let clockSettings {
                self.applyClockSettings(clockSettings)
            }
            if updateStatus {
                statusText = "Refreshed"
            }
            if let ratioState {
                trace("monitor 426 ratio=\(ratioState)")
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
        isConnecting = false
        boostEnabled = false
        bypassEnabled = false
        operationMode = .ca
        deviceClockDate = nil
        deviceClockWeekday = nil
        selectedPreset = .k1
        presetTargetByPreset = [:]
        statusText = "Disconnected"
        trace("disconnect")
    }

    func setBoostEnabled(_ enabled: Bool) async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await repository.writeBoostEnabled(enabled)
            // Some units accept write but reject immediate readback for this register.
            boostEnabled = enabled
            if let readBackRaw = try? await repository.readBoostRaw() {
                boostEnabled = readBackRaw != 0
                trace("boost readback raw=\(readBackRaw)")
            }
            statusText = boostEnabled ? "Boost enabled" : "Boost disabled"
            trace("boost write success value=\(boostEnabled ? 1 : 0)")
        } catch {
            statusText = "Boost write failed: \(error.localizedDescription)"
            trace("boost write failed: \(error.localizedDescription)")
        }
    }

    func setPreset(_ preset: TAC5Preset) async {
        guard !isBusy, !isRefreshing, isConnected else { return }
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
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }
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

    func setExhaustSupplyRatio(_ ratioPercent: UInt16) async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }
        guard exhaustSupplyRatioLimits.contains(Int(ratioPercent)) else {
            statusText = "Ratio must be between 50 and 200"
            trace("ratio write rejected: out of range value=\(ratioPercent)")
            return
        }

        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            try await repository.writeExhaustSupplyRatio(ratioPercent)
            exhaustSupplyRatio = Double(ratioPercent)
            statusText = "Ratio: \(ratioPercent)%"
            trace("ratio write success value=\(ratioPercent)")
        } catch {
            statusText = "Ratio write failed: \(error.localizedDescription)"
            trace("ratio write failed: \(error.localizedDescription)")
        }
    }

    func setCaAirflowSetpoints(_ airflowI: UInt16, _ airflowII: UInt16, _ airflowIII: UInt16) async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }
        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            try await repository.writeCaAirflowI(airflowI)
            try await repository.writeCaAirflowII(airflowII)
            try await repository.writeCaAirflowIII(airflowIII)
            caAirflowI = airflowI
            caAirflowII = airflowII
            caAirflowIII = airflowIII
            statusText = "CA airflow setpoints updated"
            trace("ca airflow write success values=\(airflowI)/\(airflowII)/\(airflowIII)")
        } catch {
            statusText = "CA airflow write failed: \(error.localizedDescription)"
            trace("ca airflow write failed: \(error.localizedDescription)")
        }
    }

    func setLsSettings(
        vmin: UInt16,
        vmax: UInt16,
        airflowAtVmin: UInt16,
        airflowAtVmax: UInt16,
        stopIfBelowVlow: Bool,
        vlow: UInt16,
        stopIfAboveVhigh: Bool,
        vhigh: UInt16,
        k3Mode: TAC5LSK3Mode,
        k3SleepFactor: UInt16
    ) async {
        guard !isBusy, !isRefreshing, isConnected, repository != nil else { return }
        guard lsVoltageLimits.contains(Int(vmin)), lsVoltageLimits.contains(Int(vmax)) else {
            statusText = "LS voltages must be between 0.0 V and 10.0 V"
            return
        }
        guard lsVoltageLimits.contains(Int(vlow)), lsVoltageLimits.contains(Int(vhigh)) else {
            statusText = "LS thresholds must be between 0.0 V and 10.0 V"
            return
        }
        guard lsAirflowLimits.contains(Int(airflowAtVmin)), lsAirflowLimits.contains(Int(airflowAtVmax)) else {
            statusText = "LS airflow values must be between 100 and 840"
            return
        }
        guard lsSleepFactorLimits.contains(Int(k3SleepFactor)) else {
            statusText = "Sleep factor must be between 0 and 100"
            return
        }

        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            trace("ls settings apply start vmin=\(vmin) vmax=\(vmax) airflowMin=\(airflowAtVmin) airflowMax=\(airflowAtVmax) stopLow=\(stopIfBelowVlow ? 1 : 0) vlow=\(vlow) stopHigh=\(stopIfAboveVhigh ? 1 : 0) vhigh=\(vhigh) k3=\(k3Mode.label) sleep=\(k3SleepFactor)")
            if self.lsVmin != vmin {
                try await performLsWriteStep("Vmin") {
                    try await $0.writeLsVmin(vmin)
                }
            }
            if self.lsVmax != vmax {
                try await performLsWriteStep("Vmax") {
                    try await $0.writeLsVmax(vmax)
                }
            }
            if self.lsAirflowAtVmin != airflowAtVmin {
                try await performLsWriteStep("Airflow@Vmin") {
                    try await $0.writeLsAirflowAtVmin(airflowAtVmin)
                }
            }
            if self.lsAirflowAtVmax != airflowAtVmax {
                try await performLsWriteStep("Airflow@Vmax") {
                    try await $0.writeLsAirflowAtVmax(airflowAtVmax)
                }
            }
            if self.lsStopIfAboveVhigh != stopIfAboveVhigh {
                try await performLsWriteStep("StopAboveVhigh") {
                    try await $0.writeLsStopIfAboveVhigh(stopIfAboveVhigh)
                }
            }
            if stopIfAboveVhigh, self.lsVhigh != vhigh {
                try await performLsWriteStep("Vhigh") {
                    try await $0.writeLsVhigh(vhigh)
                }
            }
            if self.lsStopIfBelowVlow != stopIfBelowVlow {
                try await performLsWriteStep("StopBelowVlow") {
                    try await $0.writeLsStopIfBelowVlow(stopIfBelowVlow)
                }
            }
            if stopIfBelowVlow, self.lsVlow != vlow {
                try await performLsWriteStep("Vlow") {
                    try await $0.writeLsVlow(vlow)
                }
            }
            if self.lsK3Mode != k3Mode {
                try await performLsWriteStep("K3Mode") {
                    try await $0.writeLsK3Mode(k3Mode)
                }
            }
            if k3Mode == .no, self.lsK3SleepFactor != k3SleepFactor {
                try await performLsWriteStep("K3SleepFactor") {
                    try await $0.writeLsK3SleepFactor(k3SleepFactor)
                }
            }

            self.lsVmin = vmin
            self.lsVmax = vmax
            self.lsAirflowAtVmin = airflowAtVmin
            self.lsAirflowAtVmax = airflowAtVmax
            self.lsStopIfBelowVlow = stopIfBelowVlow
            self.lsVlow = vlow
            self.lsStopIfAboveVhigh = stopIfAboveVhigh
            self.lsVhigh = vhigh
            self.lsK3Mode = k3Mode
            self.lsK3SleepFactor = k3SleepFactor
            statusText = "LS settings updated"
            trace("ls settings write success")
        } catch {
            statusText = "LS settings write failed: \(error.localizedDescription)"
            trace("ls settings write failed: \(error.localizedDescription)")
        }
    }

    func setLsK3Mode(_ mode: TAC5LSK3Mode) async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }

        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            trace("ls k3 mode apply start value=\(mode.label)")
            try await performLsWriteStep("K3Mode") {
                try await $0.writeLsK3Mode(mode)
            }

            let confirmationRepository = self.repository ?? repository
            let confirmed = await readLsK3ModeConfirmed(from: confirmationRepository, expected: mode)
            if confirmed != mode {
                if let confirmed {
                    lsK3Mode = confirmed
                }
                statusText = "LS K3 mode mismatch after write"
                trace("ls k3 mode mismatch expected=\(mode.label) actual=\(confirmed?.label ?? "nil")")
                return
            }

            lsK3Mode = mode
            statusText = "LS K3 mode: \(lsK3Mode.label)"
            trace("ls k3 mode write success value=\(lsK3Mode.label)")
        } catch {
            statusText = "LS K3 mode write failed: \(error.localizedDescription)"
            trace("ls k3 mode write failed: \(error.localizedDescription)")
        }
    }

    func setLsK3SleepFactor(_ value: UInt16) async {
        guard !isBusy, !isRefreshing, isConnected, repository != nil else { return }
        guard lsSleepFactorLimits.contains(Int(value)) else {
            statusText = "Sleep factor must be between 0 and 100"
            return
        }

        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            trace("ls k3 sleep factor apply start value=\(value)")
            try await performLsWriteStep("K3SleepFactor") {
                try await $0.writeLsK3SleepFactor(value)
            }
            lsK3SleepFactor = value
            statusText = "LS K3 sleep factor: \(value)%"
            trace("ls k3 sleep factor write success value=\(value)")
        } catch {
            statusText = "LS K3 sleep factor write failed: \(error.localizedDescription)"
            trace("ls k3 sleep factor write failed: \(error.localizedDescription)")
        }
    }

    func setCpOnMode(_ mode: TAC5CPOnMode) async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }

        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            trace("cp on apply start value=\(mode.label)")
            try await repository.writeCpOnMode(mode)
            cpOnMode = mode
            if let readBack = try? await repository.readCpOnMode() {
                cpOnMode = readBack
            }
            statusText = "CP on: \(cpOnMode.label)"
            trace("cp on write success value=\(cpOnMode.label)")
        } catch {
            statusText = "CP on write failed: \(error.localizedDescription)"
            trace("cp on write failed: \(error.localizedDescription)")
        }
    }

    func setCpSupplyVoltage(_ value: UInt16) async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }
        guard lsVoltageLimits.contains(Int(value)) else {
            statusText = "CP voltage must be between 0.0 V and 10.0 V"
            return
        }

        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            trace("cp supply voltage apply start value=\(value)")
            try await repository.writeCpSupplyVoltage(value)
            cpSupplyVoltage = value
            statusText = "CP supply voltage: \(Self.formatVoltage(value)) V"
            trace("cp supply voltage write success value=\(value)")
        } catch {
            statusText = "CP supply voltage write failed: \(error.localizedDescription)"
            trace("cp supply voltage write failed: \(error.localizedDescription)")
        }
    }

    func setCpExhaustVoltage(_ value: UInt16) async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }
        guard lsVoltageLimits.contains(Int(value)) else {
            statusText = "CP voltage must be between 0.0 V and 10.0 V"
            return
        }

        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            trace("cp exhaust voltage apply start value=\(value)")
            try await repository.writeCpExhaustVoltage(value)
            cpExhaustVoltage = value
            statusText = "CP exhaust voltage: \(Self.formatVoltage(value)) V"
            trace("cp exhaust voltage write success value=\(value)")
        } catch {
            statusText = "CP exhaust voltage write failed: \(error.localizedDescription)"
            trace("cp exhaust voltage write failed: \(error.localizedDescription)")
        }
    }

    private static func formatVoltage(_ value: UInt16) -> String {
        String(format: "%.1f", Double(value) / 10.0)
    }

    func setOperationMode(_ mode: TAC5OperationMode) async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }
        guard operationMode != mode else { return }
        isBusy = true
        defer { isBusy = false }
        suppressRefreshUntil = Date().addingTimeInterval(2.0)

        do {
            do {
                try await repository.writeOperationMode(mode)
            } catch {
                if isTransientModeError(error) {
                    trace("mode transient error; retrying once: \(error.localizedDescription)")
                    suppressRefreshUntil = Date().addingTimeInterval(4.0)
                    await reconnectAfterTransientModeError()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard let retryRepository = self.repository else {
                        throw ModbusError.connectionClosed
                    }
                    try await retryRepository.writeOperationMode(mode)
                } else {
                    throw error
                }
            }
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

    func refreshClockFromController() async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            guard let settings = try await repository.readClockSettings() else {
                statusText = "Clock read failed: no data"
                trace("clock read failed: empty response")
                return
            }
            applyClockSettings(settings)
            statusText = "Clock refreshed"
            trace("clock read success h=\(settings.hours) m=\(settings.minutes) s=\(settings.seconds) d=\(settings.dayOfMonth) mo=\(settings.month) y=\(settings.year)")
        } catch {
            statusText = "Clock read failed: \(error.localizedDescription)"
            trace("clock read failed: \(error.localizedDescription)")
        }
    }

    func applyControllerClock(date: Date) async {
        guard !isBusy, !isRefreshing, isConnected, let repository else { return }

        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard
            let year = comps.year,
            let month = comps.month,
            let day = comps.day,
            let hour = comps.hour,
            let minute = comps.minute,
            let second = comps.second,
            (2000...2099).contains(year),
            (1...12).contains(month),
            (1...31).contains(day),
            (0...23).contains(hour),
            (0...59).contains(minute),
            (0...59).contains(second)
        else {
            statusText = "Clock write failed: invalid date"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await repository.writeClockSettings(
                seconds: UInt16(second),
                minutes: UInt16(minute),
                hours: UInt16(hour),
                dayOfMonth: UInt16(day),
                month: UInt16(month),
                year: UInt16(year)
            )

            // Give the Modbus gateway a short gap before the immediate readback below;
            // without it, this read intermittently fails even though the write just
            // succeeded, leaving the controller-time display stale (see pacedRead).
            try? await Task.sleep(nanoseconds: 60_000_000)
            var readBack = try? await repository.readClockSettings()
            if readBack == nil {
                try? await Task.sleep(nanoseconds: 150_000_000)
                readBack = try? await repository.readClockSettings()
            }
            if let readBack {
                applyClockSettings(readBack)
            } else {
                trace("clock write: readback failed after retry, display may be stale until next clock refresh")
            }

            statusText = "Clock updated"
            trace("clock write success h=\(hour) m=\(minute) s=\(second) d=\(day) mo=\(month) y=\(year)")
        } catch {
            statusText = "Clock write failed: \(error.localizedDescription)"
            trace("clock write failed: \(error.localizedDescription)")
        }
    }

    func synchronizeClockWithMobileDevice() async {
        await applyControllerClock(date: Date())
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

    private func applyClockSettings(_ settings: TAC5ClockSettings) {
        let components = DateComponents(
            calendar: Calendar.current,
            year: Int(settings.year),
            month: Int(settings.month),
            day: Int(settings.dayOfMonth),
            hour: Int(settings.hours),
            minute: Int(settings.minutes),
            second: Int(settings.seconds)
        )
        deviceClockDate = components.date
        deviceClockWeekday = settings.dayOfWeek
    }

    private func withConnectTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            defer { group.cancelAll() }

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
            return result
        }
    }

    private func parseConnectionTarget() throws -> (host: String, port: UInt16, unitId: UInt8) {
        let parts = connectionTarget
            .split(separator: ":", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !parts.isEmpty, !parts[0].isEmpty else { throw ModbusError.invalidResponse }
        guard parts.count <= 3 else { throw ModbusError.invalidResponse }

        let host = parts[0]

        let port: UInt16
        if parts.count >= 2, !parts[1].isEmpty {
            guard let parsedPort = UInt16(parts[1]) else { throw ModbusError.invalidResponse }
            port = parsedPort
        } else {
            port = 502
        }

        let unitId: UInt8
        if parts.count == 3, !parts[2].isEmpty {
            guard let parsedUnitId = UInt8(parts[2]) else { throw ModbusError.invalidResponse }
            unitId = parsedUnitId
        } else {
            unitId = 1
        }

        return (host: host, port: port, unitId: unitId)
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

    private func isTransientModeError(_ error: Error) -> Bool {
        isTransientPresetError(error)
    }

    private func reconnectAfterTransientModeError() async {
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
            _ = try await newRepository.readOperationMode()
            self.client = newClient
            self.repository = newRepository
            self.isConnected = true
            trace("mode retry reconnect success")
        } catch {
            trace("mode retry reconnect failed: \(error.localizedDescription)")
        }
    }

    private func performLsWriteStep(
        _ label: String,
        operation: @escaping @Sendable (TAC5Repository) async throws -> Void
    ) async throws {
        guard let repository else { throw ModbusError.connectionClosed }

        do {
            trace("ls write step start field=\(label)")
            try await operation(repository)
            try? await Task.sleep(nanoseconds: 80_000_000)
            trace("ls write step success field=\(label)")
        } catch {
            guard isTransientModeError(error) else {
                trace("ls write step failed field=\(label) error=\(error.localizedDescription)")
                throw error
            }

            trace("ls write step transient field=\(label) error=\(error.localizedDescription); retrying once")
            await reconnectAfterTransientModeError()
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard let retryRepository = self.repository else {
                trace("ls write step retry unavailable field=\(label)")
                throw ModbusError.connectionClosed
            }

            do {
                trace("ls write step retry start field=\(label)")
                try await operation(retryRepository)
                try? await Task.sleep(nanoseconds: 80_000_000)
                trace("ls write step retry success field=\(label)")
            } catch {
                trace("ls write step retry failed field=\(label) error=\(error.localizedDescription)")
                throw error
            }
        }
    }

    private func readLsK3ModeConfirmed(from repository: TAC5Repository, expected: TAC5LSK3Mode) async -> TAC5LSK3Mode? {
        var lastRead: TAC5LSK3Mode?

        for attempt in 1...3 {
            let enabledRaw = try? await repository.readLsK3EnableRaw()
            let targetRaw = try? await repository.readLsK3TargetSideRaw()
            let readBack = try? await repository.readLsK3Mode()

            let enabledText = enabledRaw.map(String.init) ?? "nil"
            let targetText = targetRaw.map(String.init) ?? "nil"
            let modeText = readBack?.label ?? "nil"
            trace("ls k3 mode readback attempt=\(attempt) enable=\(enabledText) target=\(targetText) mode=\(modeText)")

            if let readBack {
                lastRead = readBack
                if readBack == expected {
                    return readBack
                }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        return lastRead
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

    private func tracedRead<T>(_ label: String, _ operation: () async throws -> T?) async -> T? {
        // TAC5's Modbus TCP<->RTU satellite gateway appears to need a short gap between
        // back-to-back requests; without it, some reads intermittently time out even though
        // the device is reachable and healthy (observed: roughly a third of ~24 rapid-fire
        // sequential reads hit the 3s timeout, alternating with sub-0.4s successes). The
        // official Eole app paces its own writes with a similar small gap for the same reason
        // (see writePreset()), so mirror that here for reads too.
        try? await Task.sleep(nanoseconds: 60_000_000)

        let start = Date()
        do {
            let result = try await operation()
            let elapsed = Date().timeIntervalSince(start)
            trace("read \(label) ok (\(String(format: "%.2f", elapsed))s) value=\(String(describing: result))")
            return result
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            trace("read \(label) FAILED (\(String(format: "%.2f", elapsed))s) error=\(error.localizedDescription)")
            return nil
        }
    }

    /// Same short inter-request gap as tracedRead, without the verbose per-field trace
    /// logging (used by refresh(), which polls repeatedly and would otherwise flood the
    /// trace log with ~24 extra lines every cycle).
    private func pacedRead<T>(_ operation: () async throws -> T?) async -> T? {
        try? await Task.sleep(nanoseconds: 60_000_000)
        return try? await operation()
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
            ScrollView {
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
                        .disabled(viewModel.isConnected ? viewModel.isBusy : viewModel.isConnecting)

                        if supportsInAppClose {
                            Button("Quit") {
                                Task {
                                    if viewModel.isConnected {
                                        await viewModel.disconnect()
                                    }
                                    _ = await MainActor.run { closeApplication() }
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .frame(maxWidth: .infinity)
                        }
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

                    Text(buildInfo)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("TAC5 Remote")
            .navigationBarTitleDisplayMode(.inline)
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

    private var supportsInAppClose: Bool {
#if targetEnvironment(macCatalyst)
        return true
#else
        return false
#endif
    }

    private func closeApplication() -> Bool {
#if targetEnvironment(macCatalyst)
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })

        let scene = activeScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        if let scene {
            UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
        }

        // For Catalyst utility-style usage, ensure the app actually exits after scene teardown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exit(0)
        }
        return true
    #else
        return false
#endif
    }
}

private struct SettingsView: View {
    private enum SettingsTab: String, CaseIterable {
        case general = "Setup"
        case timetable = "Timetable"
    }

    @ObservedObject var viewModel: ConnectionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationStack {
            Form {
                settingsTabSection

                if selectedTab == .general {
                    tracingSection
                    operationModeSection
                    clockSection
                    modeParametersSection
                } else {
                    timetableSection
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                doneToolbarItem
            }
        }
    }

    private var settingsTabSection: some View {
        Section {
            Picker("Area", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
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

    private var clockSection: some View {
        Section("Clock Settings") {
            ClockSettingsEditor(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var modeParametersSection: some View {
        Section("Mode Parameters") {
            if viewModel.operationMode == .ca {
                VStack(alignment: .leading, spacing: 12) {
                    ExhaustSupplyRatioEditor(viewModel: viewModel)
                    CAModeParametersEditor(viewModel: viewModel)
                }
            } else if viewModel.operationMode == .ls {
                LSModeParametersEditor(viewModel: viewModel)
            } else if viewModel.operationMode == .cp {
                CPModeParametersEditor(viewModel: viewModel)
            } else {
                Text("No mapped editable parameters for \(viewModel.operationMode.label) yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timetableSection: some View {
        Section("Week / Year Planner") {
            TimetableSettingsEditor(viewModel: viewModel)
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

private struct ClockSettingsEditor: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @State private var draftDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Controller")
                    .frame(width: 90, alignment: .leading)
                Text(controllerDateText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let weekday = viewModel.deviceClockWeekday {
                Text("Weekday: \(weekdayLabel(for: weekday))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            DatePicker("Set time", selection: $draftDate, displayedComponents: [.date, .hourAndMinute])

            HStack {
                Button("Refresh") {
                    Task { await viewModel.refreshClockFromController() }
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isConnected || viewModel.isBusy)

                Spacer(minLength: 0)

                Button("Apply selected date/time") {
                    Task { await viewModel.applyControllerClock(date: draftDate) }
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isConnected || viewModel.isBusy)
            }

            Button("Synchronize") {
                Task { await viewModel.synchronizeClockWithMobileDevice() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isConnected || viewModel.isBusy)

            Text("Sync writes a single 6-register RTC block (seconds, minutes, hours, day, month, year).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear {
            if let controllerDate = viewModel.deviceClockDate {
                draftDate = controllerDate
            }
        }
        .onChange(of: viewModel.deviceClockDate) { newValue in
            if let newValue {
                draftDate = newValue
            }
        }
    }

    private var controllerDateText: String {
        guard let controllerDate = viewModel.deviceClockDate else { return "-" }
        return Self.controllerDateFormatter.string(from: controllerDate)
    }

    private func weekdayLabel(for value: UInt16) -> String {
        switch value {
        case 0: return "Monday"
        case 1: return "Tuesday"
        case 2: return "Wednesday"
        case 3: return "Thursday"
        case 4: return "Friday"
        case 5: return "Saturday"
        case 6: return "Sunday"
        default: return "Unknown (\(value))"
        }
    }

    private static let controllerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct TimetableSettingsEditor: View {
    private enum PlannerTab: String, CaseIterable {
        case week = "Week planner"
        case year = "Year planner"
    }

    private enum BypassMode: String, CaseIterable {
        case auto = "AUTO"
        case on = "ON"
        case off = "OFF"
    }

    @ObservedObject var viewModel: ConnectionViewModel
    @State private var plannerTab: PlannerTab = .week
    @State private var selectedWeekday = 1
    @State private var selectedSlot = 1
    @State private var slotTime = Date()
    @State private var slotMode: TAC5OperationMode = .ca
    @State private var supplyAirflowText = "400"
    @State private var exhaustAirflowText = "400"
    @State private var bypassMode: BypassMode = .auto
    @State private var disableBypass = false
    @State private var disablePostHeating = false
    @State private var disablePostCooling = false

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Planner", selection: $plannerTab) {
                ForEach(PlannerTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if plannerTab == .week {
                weekPlannerEditor
            } else {
                yearPlannerEditor
            }

            Text("Planner fields are currently local draft values. Register mapping for timetable write/read is not finalized yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var weekPlannerEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Day")
                    .frame(width: 68, alignment: .leading)

                Picker("Day", selection: $selectedWeekday) {
                    ForEach(0..<weekdays.count, id: \.self) { index in
                        Text(weekdays[index]).tag(index + 1)
                    }
                }
                .pickerStyle(.menu)

                Spacer(minLength: 0)

                Text("Slot")
                    .foregroundStyle(.secondary)

                Picker("Slot", selection: $selectedSlot) {
                    ForEach(1...6, id: \.self) { slot in
                        Text(String(slot)).tag(slot)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                DatePicker("Time", selection: $slotTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()

                Picker("Mode", selection: $slotMode) {
                    ForEach(TAC5OperationMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                TextField("Supply", text: $supplyAirflowText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                Text("m3/h")
                    .foregroundStyle(.secondary)

                TextField("Exhaust", text: $exhaustAirflowText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                Text("m3/h")
                    .foregroundStyle(.secondary)
            }

            Picker("Bypass", selection: $bypassMode) {
                ForEach(BypassMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Save day draft") {
                    viewModel.statusText = "Week planner draft updated (Day \(selectedWeekday), Slot \(selectedSlot))"
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button("Apply to controller") {
                    viewModel.statusText = "Timetable write mapping is not enabled yet"
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isConnected || viewModel.isBusy)
            }
        }
    }

    private var yearPlannerEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Disable bypass", isOn: $disableBypass)
            Toggle("Disable post-heating", isOn: $disablePostHeating)
            Toggle("Disable post-cooling", isOn: $disablePostCooling)

            HStack {
                Button("Save year draft") {
                    viewModel.statusText = "Year planner draft updated"
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button("Apply year settings") {
                    viewModel.statusText = "Year planner write mapping is not enabled yet"
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isConnected || viewModel.isBusy)
            }
        }
    }
}

private struct CPModeParametersEditor: View {
    private enum CPInitMode: String, CaseIterable {
        case airflow = "Airflow"
        case pressure = "Pressure"
    }

    private enum CPField: Hashable {
        case sleepFactor
        case singleVoltage
        case supplyVoltage
        case exhaustVoltage
    }

    @ObservedObject var viewModel: ConnectionViewModel
    @State private var cpOnMode: TAC5CPOnMode
    @State private var initializeMode: CPInitMode = .airflow
    @State private var sleepFactorText: String
    @State private var singleVoltageText: String
    @State private var supplyVoltageText: String
    @State private var exhaustVoltageText: String
    @State private var suppressModeAutoApply = false
    @State private var lastFocusedField: CPField?
    @FocusState private var focusedField: CPField?

    init(viewModel: ConnectionViewModel) {
        self.viewModel = viewModel
        _cpOnMode = State(initialValue: viewModel.cpOnMode)
        _sleepFactorText = State(initialValue: String(viewModel.lsK3SleepFactor ?? 100))
        _singleVoltageText = State(initialValue: Self.voltageText(viewModel.cpSupplyVoltage ?? 0))
        _supplyVoltageText = State(initialValue: Self.voltageText(viewModel.cpSupplyVoltage ?? 0))
        _exhaustVoltageText = State(initialValue: Self.voltageText(viewModel.cpExhaustVoltage ?? 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("CP on", selection: $cpOnMode) {
                ForEach(TAC5CPOnMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: cpOnMode) { _ in
                if suppressModeAutoApply {
                    suppressModeAutoApply = false
                    return
                }
                applyCpOnMode()
            }

            if cpOnMode != .supplyExhaust {
                ExhaustSupplyRatioEditor(viewModel: viewModel)
                cpSleepFactorRow
            }

            cpInitializePressureSection

            Text("CP on uses the confirmed raw register 442 mapping. Voltage fields are capture-confirmed; Pressure/Airflow selector is still read-only until its register mapping is confirmed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .onChange(of: focusedField) { newValue in
            if let previous = lastFocusedField, previous != newValue {
                applyField(previous)
            }
            lastFocusedField = newValue
        }
        .onChange(of: viewModel.cpOnMode) { newValue in
            if cpOnMode != newValue {
                suppressModeAutoApply = true
                cpOnMode = newValue
            }
        }
        .onChange(of: viewModel.lsK3SleepFactor) { newValue in
            guard focusedField != .sleepFactor, let newValue else { return }
            sleepFactorText = String(newValue)
        }
        .onChange(of: viewModel.cpSupplyVoltage) { newValue in
            guard focusedField != .singleVoltage, focusedField != .supplyVoltage, let newValue else { return }
            singleVoltageText = Self.voltageText(newValue)
            supplyVoltageText = Self.voltageText(newValue)
        }
        .onChange(of: viewModel.cpExhaustVoltage) { newValue in
            guard focusedField != .exhaustVoltage, let newValue else { return }
            exhaustVoltageText = Self.voltageText(newValue)
        }
    }

    private var cpSleepFactorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("% on K3 (sleep factor)")
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("0-100", text: $sleepFactorText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .focused($focusedField, equals: .sleepFactor)

                Text("%")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
            }

            HStack {
                Spacer(minLength: 0)
                Button("Apply CP") {
                    applySleepFactor()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.isConnected || viewModel.isBusy)
            }
        }
    }

    private var cpInitializePressureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Initialize the pressure")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Initialize the pressure", selection: $initializeMode) {
                    ForEach(CPInitMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(true)
                .frame(maxWidth: 260)
            }

            if cpOnMode == .supplyExhaust {
                cpVoltageRow(title: "Supply", text: $supplyVoltageText, field: .supplyVoltage) {
                    applySupplyVoltage()
                }
                cpVoltageRow(title: "Exhaust", text: $exhaustVoltageText, field: .exhaustVoltage) {
                    applyExhaustVoltage()
                }
            } else {
                cpVoltageRow(title: cpOnMode.label, text: $singleVoltageText, field: .singleVoltage) {
                    applySingleVoltage()
                }
            }
        }
    }

    private func cpVoltageRow(title: String, text: Binding<String>, field: CPField, apply: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 80, alignment: .leading)

            TextField("0,0", text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .focused($focusedField, equals: field)

            Text("V")
                .foregroundStyle(.secondary)

            Text("Start")
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 36)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.gray.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.gray.opacity(0.15), lineWidth: 1))

            Text(viewModel.cpStartAirflow.map(String.init) ?? "0")
                .font(.body.monospacedDigit())
                .frame(width: 64, height: 36)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.gray.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.gray.opacity(0.25), lineWidth: 1))

            Text("m3/h")
                .foregroundStyle(.secondary)

            Button("Apply") {
                apply()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!viewModel.isConnected || viewModel.isBusy)
        }
    }

    private func applyCpOnMode() {
        guard viewModel.isConnected, !viewModel.isBusy else { return }
        guard cpOnMode != viewModel.cpOnMode else { return }

        Task {
            await viewModel.setCpOnMode(cpOnMode)
        }
    }

    private func applySleepFactor() {
        guard viewModel.isConnected, !viewModel.isBusy else { return }
        guard let value = UInt16(sleepFactorText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            viewModel.statusText = "Sleep factor must be numeric"
            return
        }

        Task {
            await viewModel.setLsK3SleepFactor(value)
        }
    }

    private func applySingleVoltage() {
        guard viewModel.isConnected, !viewModel.isBusy else { return }
        guard let value = Self.parseVoltage(singleVoltageText) else {
            viewModel.statusText = "CP voltage must be numeric (0.0-10.0 V)"
            return
        }

        Task {
            await viewModel.setCpSupplyVoltage(value)
        }
    }

    private func applySupplyVoltage() {
        guard viewModel.isConnected, !viewModel.isBusy else { return }
        guard let value = Self.parseVoltage(supplyVoltageText) else {
            viewModel.statusText = "Supply voltage must be numeric (0.0-10.0 V)"
            return
        }

        Task {
            await viewModel.setCpSupplyVoltage(value)
        }
    }

    private func applyExhaustVoltage() {
        guard viewModel.isConnected, !viewModel.isBusy else { return }
        guard let value = Self.parseVoltage(exhaustVoltageText) else {
            viewModel.statusText = "Exhaust voltage must be numeric (0.0-10.0 V)"
            return
        }

        Task {
            await viewModel.setCpExhaustVoltage(value)
        }
    }

    private func applyField(_ field: CPField) {
        switch field {
        case .sleepFactor:
            applySleepFactor()
        case .singleVoltage:
            applySingleVoltage()
        case .supplyVoltage:
            applySupplyVoltage()
        case .exhaustVoltage:
            applyExhaustVoltage()
        }
    }

    private static func parseVoltage(_ text: String) -> UInt16? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed) else { return nil }
        let scaled = (value * 10.0).rounded()
        guard scaled >= 0, scaled <= 100 else { return nil }
        return UInt16(scaled)
    }

    private static func voltageText(_ rawValue: UInt16) -> String {
        let value = Double(rawValue) / 10.0
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

private struct ExhaustSupplyRatioEditor: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @State private var ratioText: String
    @State private var wasRatioFocused = false
    @FocusState private var isRatioFocused: Bool

    init(viewModel: ConnectionViewModel) {
        self.viewModel = viewModel
        let initialValue = Int(viewModel.exhaustSupplyRatio ?? 100)
        _ratioText = State(initialValue: String(initialValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exhaust / Supply Ratio")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("50-200", text: $ratioText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .focused($isRatioFocused)

                Text("%")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Text("Current: \(currentText)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer(minLength: 0)
                Button("Apply ratio") {
                    applyRatio()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.isConnected || viewModel.isBusy)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: isRatioFocused) { isFocused in
            if wasRatioFocused && !isFocused {
                applyRatio()
            }
            wasRatioFocused = isFocused
        }
        .onChange(of: viewModel.exhaustSupplyRatio) { newValue in
            guard !isRatioFocused, let newValue else { return }
            ratioText = String(Int(newValue.rounded()))
        }
    }

    private var currentText: String {
        guard let value = viewModel.exhaustSupplyRatio else { return "-" }
        return String(format: "%.0f%%", value)
    }

    private func applyRatio() {
        let trimmed = ratioText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = UInt16(trimmed) else {
            viewModel.statusText = "Ratio must be a whole number"
            return
        }

        guard (50...200).contains(Int(value)) else {
            viewModel.statusText = "Ratio must be between 50 and 200"
            return
        }

        Task {
            await viewModel.setExhaustSupplyRatio(value)
        }
    }
}

private struct CAModeParametersEditor: View {
    private enum CAField: Hashable {
        case airflowI
        case airflowII
        case airflowIII
    }

    @ObservedObject var viewModel: ConnectionViewModel
    @State private var airflowIText: String
    @State private var airflowIIText: String
    @State private var airflowIIIText: String
    @State private var lastFocusedField: CAField?
    @FocusState private var focusedField: CAField?

    init(viewModel: ConnectionViewModel) {
        self.viewModel = viewModel
        _airflowIText = State(initialValue: String(viewModel.caAirflowI ?? 200))
        _airflowIIText = State(initialValue: String(viewModel.caAirflowII ?? 400))
        _airflowIIIText = State(initialValue: String(viewModel.caAirflowIII ?? 600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Parameter")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Supply")
                    .font(.caption.weight(.semibold))
                    .frame(width: 86, alignment: .center)
                Text("Exhaust")
                    .font(.caption.weight(.semibold))
                    .frame(width: 86, alignment: .center)
            }

            airflowRow(title: "Airflow I", valueText: $airflowIText, field: .airflowI)
            airflowRow(title: "Airflow II", valueText: $airflowIIText, field: .airflowII)
            airflowRow(title: "Airflow III", valueText: $airflowIIIText, field: .airflowIII)

            Text("Supply values are editable in CA mode. Exhaust is calculated from the current ratio.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("CA values are auto-applied when a field loses focus.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer(minLength: 0)
                Button("Apply airflow") {
                    applyAirflowValues()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.isConnected || viewModel.isBusy)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: focusedField) { newValue in
            if let previous = lastFocusedField, previous != newValue {
                applyAirflowValues()
            }
            lastFocusedField = newValue
        }
        .onChange(of: viewModel.caAirflowI) { newValue in
            guard focusedField != .airflowI, let newValue else { return }
            airflowIText = String(newValue)
        }
        .onChange(of: viewModel.caAirflowII) { newValue in
            guard focusedField != .airflowII, let newValue else { return }
            airflowIIText = String(newValue)
        }
        .onChange(of: viewModel.caAirflowIII) { newValue in
            guard focusedField != .airflowIII, let newValue else { return }
            airflowIIIText = String(newValue)
        }
    }

    @ViewBuilder
    private func airflowRow(title: String, valueText: Binding<String>, field: CAField) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Supply", text: valueText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 86)
                .focused($focusedField, equals: field)

            valueBox(exhaustValue(for: valueText.wrappedValue))
        }
    }

    private func valueBox(_ value: String) -> some View {
        Text(value)
            .font(.body.monospacedDigit())
            .frame(width: 86, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
    }

    private func exhaustValue(for supplyText: String) -> String {
        guard let supply = UInt16(supplyText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return "-"
        }

        let ratio = viewModel.exhaustSupplyRatio ?? 100
        let exhaust = Double(supply) * ratio / 100.0
        return String(format: "%.0f", exhaust)
    }

    private func applyAirflowValues() {
        guard viewModel.isConnected, !viewModel.isBusy else { return }
        let trimmedI = airflowIText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedII = airflowIIText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIII = airflowIIIText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let airflowI = UInt16(trimmedI), let airflowII = UInt16(trimmedII), let airflowIII = UInt16(trimmedIII) else {
            viewModel.statusText = "CA airflow values must be whole numbers"
            return
        }

        Task {
            await viewModel.setCaAirflowSetpoints(airflowI, airflowII, airflowIII)
        }
    }
}

private struct LSModeParametersEditor: View {
    private enum LSField: Hashable {
        case vmin
        case vmax
        case airflowAtVmin
        case airflowAtVmax
        case vlow
        case vhigh
        case k3SleepFactor
    }

    @ObservedObject var viewModel: ConnectionViewModel
    @State private var vminText: String
    @State private var vmaxText: String
    @State private var airflowAtVminText: String
    @State private var airflowAtVmaxText: String
    @State private var vlowText: String
    @State private var vhighText: String
    @State private var k3SleepFactorText: String
    @State private var stopIfBelowVlow: Bool
    @State private var stopIfAboveVhigh: Bool
    @State private var k3Mode: TAC5LSK3Mode
    @State private var suppressK3AutoApply = false
    @State private var lastFocusedField: LSField?
    @FocusState private var focusedField: LSField?

    init(viewModel: ConnectionViewModel) {
        self.viewModel = viewModel
        _vminText = State(initialValue: Self.voltageText(viewModel.lsVmin ?? 0))
        _vmaxText = State(initialValue: Self.voltageText(viewModel.lsVmax ?? 100))
        _airflowAtVminText = State(initialValue: String(viewModel.lsAirflowAtVmin ?? 100))
        _airflowAtVmaxText = State(initialValue: String(viewModel.lsAirflowAtVmax ?? 840))
        _vlowText = State(initialValue: Self.voltageText(viewModel.lsVlow ?? 0))
        _vhighText = State(initialValue: Self.voltageText(viewModel.lsVhigh ?? 100))
        _k3SleepFactorText = State(initialValue: String(viewModel.lsK3SleepFactor ?? 100))
        _stopIfBelowVlow = State(initialValue: viewModel.lsStopIfBelowVlow)
        _stopIfAboveVhigh = State(initialValue: viewModel.lsStopIfAboveVhigh)
        _k3Mode = State(initialValue: viewModel.lsK3Mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Input")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Value")
                    .font(.caption.weight(.semibold))
                    .frame(width: 96, alignment: .center)
            }

            lsValueRow(title: "Vmin", text: $vminText, suffix: "V", field: .vmin)
            lsValueRow(title: "Vmax", text: $vmaxText, suffix: "V", field: .vmax)
            lsValueRow(title: "Airflow @Vmin", text: $airflowAtVminText, suffix: "m3/h", field: .airflowAtVmin)
            lsValueRow(title: "Airflow @Vmax", text: $airflowAtVmaxText, suffix: "m3/h", field: .airflowAtVmax)

            Toggle("Stop fans if V < Vlow", isOn: $stopIfBelowVlow)
                .onChange(of: stopIfBelowVlow) { _ in
                    applyLsSettings()
                }
            if stopIfBelowVlow {
                lsValueRow(title: "Vlow", text: $vlowText, suffix: "V", field: .vlow)
            }

            Toggle("Stop fans if V > Vhigh", isOn: $stopIfAboveVhigh)
                .onChange(of: stopIfAboveVhigh) { _ in
                    applyLsSettings()
                }
            if stopIfAboveVhigh {
                lsValueRow(title: "Vhigh", text: $vhighText, suffix: "V", field: .vhigh)
            }

            Picker("0-10V on K3", selection: $k3Mode) {
                ForEach(TAC5LSK3Mode.allCases, id: \.label) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: k3Mode) { _ in
                if suppressK3AutoApply {
                    suppressK3AutoApply = false
                    return
                }
                applyK3ModeOnly()
            }

            ExhaustSupplyRatioEditor(viewModel: viewModel)

            if k3Mode == .no {
                lsValueRow(title: "% on K3 (sleep factor)", text: $k3SleepFactorText, suffix: "%", field: .k3SleepFactor)
            }

            Text("LS values are auto-applied when a field loses focus.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer(minLength: 0)
                Button("Apply LS") {
                    applyLsSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.isConnected || viewModel.isBusy)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: focusedField) { newValue in
            if let previous = lastFocusedField, previous != newValue {
                applyLsSettings()
            }
            lastFocusedField = newValue
        }
        .onChange(of: viewModel.lsK3Mode) { newValue in
            if k3Mode != newValue {
                suppressK3AutoApply = true
                k3Mode = newValue
            }
        }
    }

    @ViewBuilder
    private func lsValueRow(title: String, text: Binding<String>, suffix: String, field: LSField) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
                .focused($focusedField, equals: field)

            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }

    private func applyLsSettings() {
        guard viewModel.isConnected, !viewModel.isBusy else { return }
        guard let vmin = Self.parseVoltage(vminText) else {
            viewModel.statusText = "Vmin must be numeric (0.0-10.0 V)"
            return
        }
        guard let vmax = Self.parseVoltage(vmaxText) else {
            viewModel.statusText = "Vmax must be numeric (0.0-10.0 V)"
            return
        }
        guard let airflowAtVmin = UInt16(airflowAtVminText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            viewModel.statusText = "Airflow @Vmin must be numeric"
            return
        }
        guard let airflowAtVmax = UInt16(airflowAtVmaxText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            viewModel.statusText = "Airflow @Vmax must be numeric"
            return
        }

        let vlow: UInt16
        if stopIfBelowVlow {
            guard let parsedVlow = Self.parseVoltage(vlowText) else {
                viewModel.statusText = "Vlow must be numeric (0.0-10.0 V)"
                return
            }
            vlow = parsedVlow
        } else {
            vlow = viewModel.lsVlow ?? 0
        }

        let vhigh: UInt16
        if stopIfAboveVhigh {
            guard let parsedVhigh = Self.parseVoltage(vhighText) else {
                viewModel.statusText = "Vhigh must be numeric (0.0-10.0 V)"
                return
            }
            vhigh = parsedVhigh
        } else {
            vhigh = viewModel.lsVhigh ?? 100
        }

        let k3SleepFactor: UInt16
        if k3Mode == .no {
            guard let parsedSleep = UInt16(k3SleepFactorText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                viewModel.statusText = "Sleep factor must be numeric"
                return
            }
            k3SleepFactor = parsedSleep
        } else {
            k3SleepFactor = viewModel.lsK3SleepFactor ?? 100
        }

        Task {
            await viewModel.setLsSettings(
                vmin: vmin,
                vmax: vmax,
                airflowAtVmin: airflowAtVmin,
                airflowAtVmax: airflowAtVmax,
                stopIfBelowVlow: stopIfBelowVlow,
                vlow: vlow,
                stopIfAboveVhigh: stopIfAboveVhigh,
                vhigh: vhigh,
                k3Mode: k3Mode,
                k3SleepFactor: k3SleepFactor
            )
        }
    }

    private func applyK3ModeOnly() {
        guard viewModel.isConnected, !viewModel.isBusy else { return }
        guard k3Mode != viewModel.lsK3Mode else { return }

        Task {
            await viewModel.setLsK3Mode(k3Mode)
        }
    }

    private static func parseVoltage(_ text: String) -> UInt16? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Accept both decimal separators regardless of active keyboard locale.
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { return nil }
        let scaled = (value * 10.0).rounded()
        guard scaled >= 0, scaled <= 100 else { return nil }
        return UInt16(scaled)
    }

    private static func voltageText(_ rawValue: UInt16) -> String {
        let value = Double(rawValue) / 10.0
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
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
