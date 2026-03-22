//
//  TetherCentral.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-16.
//

@preconcurrency import CoreBluetooth
import OSLog

public actor TetherCentral {
    private let cbCentral: CBCentralManager
    private let cbCentralDelegate: CentralDelegateHandler
    private let logger: Logger = .init(subsystem: "sh.dovgo.tether", category: "central")
    public var state: State {
        State(cbCentral.state)
    }

    public func isScanning() async -> Bool {
        await cbCentralDelegate.continuationManager.hasStream(for: .scan)
    }

    public init() {
        self.cbCentralDelegate = CentralDelegateHandler(continuationManager: ContinuationManager(), logger: self.logger)
        self.cbCentral = CBCentralManager(delegate: self.cbCentralDelegate, queue: DispatchQueue.global())
    }

    // MARK: - State
    public func stateStream() async -> AsyncStream<State> {
        let id = UUID()
        let currentState = state
        // Safe: `id` practically is always unique, .alreadyPending should never happen.
        // swiftlint:disable force_try
        return try! await cbCentralDelegate
            .continuationManager
            .stream(for: .state(id)) { continuation in
                // Immediately yield current state
                continuation.yield(currentState)
            }
        // swiftlint:enable force_try
    }

    public func wait(for desiredState: State) async {
        guard desiredState != self.state else {
            // Return immediately if at desired state
            return
        }
        _ = await stateStream().first(where: { $0 == desiredState })
    }

    // MARK: - Scanning
    public func scanForPeripherals(withServices services: [UUID]) async throws -> AsyncStream<Peripheral> {
        do {
            return try await cbCentralDelegate
                .continuationManager
                .stream(for: .scan) { continuation in
                    continuation.onTermination = { _ in
                        self.cbCentral.stopScan()
                        Task {
                            await self.cbCentralDelegate.continuationManager.finish(.scan)
                        }
                    }
                    self.cbCentral.scanForPeripherals(withServices: services.cbUUIDs)
                }
        } catch ContinuationManagerError.continuationExists {
            throw Error.alreadyInProgress
        }
    }

    public func stopScan() async {
        await cbCentralDelegate.continuationManager.finish(.scan)
    }

    // MARK: - Connection
    public func connect(to peripheral: Peripheral) async throws {
        do {
            try await cbCentralDelegate
                .continuationManager
                .continuation(for: .connect(peripheral.identifier)) {
                    self.cbCentral.connect(peripheral.cbPeripheral, options: nil)
                }
        } catch ContinuationManagerError.continuationExists {
            throw Error.alreadyInProgress
        }
    }

    public func disconnect(from peripheral: Peripheral) async throws {
        do {
            try await cbCentralDelegate
                .continuationManager
                .continuation(for: .disconnect(peripheral.identifier)) {
                    self.cbCentral.cancelPeripheralConnection(peripheral.cbPeripheral)
                }
        } catch ContinuationManagerError.continuationExists {
            throw Error.alreadyInProgress
        }
    }
}

public extension TetherCentral {
    enum State: Sendable {
        case unknown
        case resetting
        case unsupported
        case unauthorized
        case poweredOff
        case poweredOn
    }
}

extension TetherCentral.State {
    init(_ cbState: CBManagerState) {
        switch cbState {
        case .resetting: self = .resetting
        case .unsupported: self = .unsupported
        case .unauthorized: self = .unauthorized
        case .poweredOff: self = .poweredOff
        case .poweredOn: self = .poweredOn
        default:
            self = .unknown
        }
    }
}
