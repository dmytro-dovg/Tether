//
//  Tether.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-16.
//

import Foundation
@preconcurrency import CoreBluetooth
import OSLog

enum TetherError: Error {
    case alreadyScanning
    case alreadyConnected
    case alreadyDisconnecting
    case unknownError
}

actor Queue {
    var scanContinuation: AsyncStream<Peripheral>.Continuation? = nil
    var connectContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    var disconnectContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    var isScanning: Bool {
        scanContinuation != nil
    }

    func startScan(_ body: @Sendable (AsyncStream<Peripheral>.Continuation) -> Void) async throws -> AsyncStream<Peripheral> {
        guard scanContinuation == nil else {
            throw TetherError.alreadyScanning
        }
        return AsyncStream(Peripheral.self) { continuation in
            scanContinuation = continuation
            body(continuation)
        }
    }

    func stopScan() {
        scanContinuation = nil
    }

    func waitForConnect(to uuid: UUID, _ body: @Sendable () -> Void) async throws {
        guard connectContinuations[uuid] == nil else {
            throw TetherError.alreadyConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectContinuations[uuid] = continuation
            body()
        }
    }

    func popConnectContinuation(for uuid: UUID) -> CheckedContinuation<Void, Error>? {
        connectContinuations.removeValue(forKey: uuid)
    }

    func waitForDisconnect(to uuid: UUID, _ body: @Sendable () -> Void) async throws {
        guard disconnectContinuations[uuid] == nil else {
            throw TetherError.alreadyDisconnecting
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            disconnectContinuations[uuid] = continuation
            body()
        }
    }

    func popDisconnectContinuation(for uuid: UUID) -> CheckedContinuation<Void, Error>? {
        disconnectContinuations.removeValue(forKey: uuid)
    }
}

class CentralDelegateHandler: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    var logger: Logger?
    weak var taskQueue: Queue?

    init(taskQueue: Queue, logger: Logger? = nil) {
        self.logger = logger
        self.taskQueue = taskQueue
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task {
            await taskQueue?.scanContinuation?.yield(Peripheral(cbPeripheral: peripheral))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task {
            logger?.debug("Connected: \(peripheral.name ?? "Unknown peripheral")")
            await taskQueue?.popConnectContinuation(for: peripheral.identifier)?.resume()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Task {
            let errorToThrow = error ?? TetherError.unknownError
            await taskQueue?.popConnectContinuation(for: peripheral.identifier)?.resume(throwing: errorToThrow)
            logger?.warning("Failed to connect: \(peripheral.name ?? "Unknown peripheral")\nError: \(errorToThrow.localizedDescription)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        if let error {
            logger?.warning("Disconnected with error: \(peripheral.name ?? "Unknown peripheral")\nError: \(error.localizedDescription)")
            Task { await taskQueue?.popDisconnectContinuation(for: peripheral.identifier)?.resume(throwing: error) }
            return
        }
        Task {
            logger?.debug("Disconnected: \(peripheral.name ?? "Unknown peripheral")")
            await taskQueue?.popDisconnectContinuation(for: peripheral.identifier)?.resume()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if let error {
            logger?.warning("Disconnected(2) with error: \(peripheral.name ?? "Unknown peripheral")\nError: \(error.localizedDescription)")
            Task { await taskQueue?.popDisconnectContinuation(for: peripheral.identifier)?.resume(throwing: error) }
            return
        }
        Task {
            logger?.debug("Disconnected(2): \(peripheral.name ?? "Unknown peripheral")")
            await taskQueue?.popDisconnectContinuation(for: peripheral.identifier)?.resume()
        }
    }
}

public struct Peripheral: Sendable {
    let cbPeripheral: CBPeripheral
    public var identifier: UUID { cbPeripheral.identifier }
    public var name: String? { cbPeripheral.name }
}

extension Peripheral: CustomDebugStringConvertible {
    public var debugDescription: String {
        "Name: \(name ?? "Unknown"), UUID: \(identifier.uuidString)"
    }
}

public actor TetherCentral: Sendable {
    private let cbCentral: CBCentralManager
    private let cbCentralDelegate: CentralDelegateHandler
    private let taskQueue: Queue
    private let logger: Logger = .init(subsystem: "sh.dmytro.tether", category: "central")
    public var state: State {
        State.from(cbState: cbCentral.state)
    }

    public func isScanning() async -> Bool {
        await self.taskQueue.isScanning
    }

    public init() {
        self.taskQueue = Queue()
        self.cbCentralDelegate = CentralDelegateHandler(taskQueue: self.taskQueue, logger: self.logger)
        self.cbCentral = CBCentralManager(delegate: self.cbCentralDelegate, queue: DispatchQueue.global())
    }


    // MARK: - Scanning
    public func scanForPeripherals(withServices services: [UUID]) async throws -> AsyncStream<Peripheral> {
        try await self.taskQueue.startScan() { continuation in
            continuation.onTermination = { _ in
                self.cbCentral.stopScan()
                Task { await self.taskQueue.stopScan() }
            }
            self.cbCentral.scanForPeripherals(withServices: services.map { CBUUID(nsuuid: $0) })
        }
    }

    public func stopScan() async {
        await self.taskQueue.scanContinuation?.finish()
    }

    // MARK: - Connection
    public func connect(_ peripheral: Peripheral) async throws {
        try await taskQueue.waitForConnect(to: peripheral.identifier) {
            self.cbCentral.connect(peripheral.cbPeripheral, options: nil)
        }
    }

    public func disconnect(_ peripheral: Peripheral) async throws {
        try await taskQueue.waitForDisconnect(to: peripheral.identifier) {
            self.cbCentral.cancelPeripheralConnection(peripheral.cbPeripheral)
        }
    }
}

extension TetherCentral {
    public enum State {
        case unknown
        case resetting
        case unsupported
        case unauthorized
        case poweredOff
        case poweredOn
    }
}

fileprivate extension TetherCentral.State {
    var cbState: CBManagerState {
        switch self {
            case .unknown: return .unknown
            case .resetting: return .resetting
            case .unsupported: return .unsupported
            case .unauthorized: return .unauthorized
            case .poweredOff: return .poweredOff
            case .poweredOn: return .poweredOn
        }
    }

    static func from(cbState: CBManagerState) -> Self {
        switch cbState {
            case .unknown: return .unknown
            case .resetting: return .resetting
            case .unsupported: return .unsupported
            case .unauthorized: return .unauthorized
            case .poweredOff: return .poweredOff
            case .poweredOn: return .poweredOn
        @unknown default:
            return .unknown
        }
    }
}

