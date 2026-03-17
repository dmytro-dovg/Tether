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
}

actor Queue {
    var scanContinuation: AsyncStream<Peripheral>.Continuation? = nil
    var connectContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    func setScanContinuation(_ continuation: AsyncStream<Peripheral>.Continuation?) {
        scanContinuation = continuation
    }

    func addConnect(continuation: CheckedContinuation<Void, Error>, for uuid: UUID) throws {
        guard connectContinuations[uuid] == nil else {
            throw TetherError.alreadyConnected
        }
        connectContinuations[uuid] = continuation
    }

    func popContinuation(for uuid: UUID) -> CheckedContinuation<Void, Error>? {
        connectContinuations.removeValue(forKey: uuid)
    }
}

class Delegate: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    var logger: Logger?
    weak var taskQueue: Queue?
    var onDiscover: (@Sendable (Peripheral) -> Void)?

    init(taskQueue: Queue, logger: Logger? = nil) {
        self.logger = logger
        self.taskQueue = taskQueue
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        onDiscover?(Peripheral(cbPeripheral: peripheral))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task {
            logger?.debug("Connected: \(peripheral.name ?? "Unknown peripheral")")
            await taskQueue?.popContinuation(for: peripheral.identifier)?.resume()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Task {
            guard let error else {
                logger?.warning("Failed to connect: \(peripheral.name ?? "Unknown peripheral")\nNo Error")
                return
            }
            logger?.warning("Failed to connect: \(peripheral.name ?? "Unknown peripheral")\nError: \(error.localizedDescription)")
            await taskQueue?.popContinuation(for: peripheral.identifier)?.resume(throwing: error)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        if let error {
            logger?.warning("Disconnected with error: \(peripheral.name ?? "Unknown peripheral")\nError: \(error.localizedDescription)")
            return
        }
        Task {
            logger?.debug("Disconnected: \(peripheral.name ?? "Unknown peripheral")")
            await taskQueue?.popContinuation(for: peripheral.identifier)?.resume()
        }

    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if let error {
            logger?.warning("Disconnected(2) with error: \(peripheral.name ?? "Unknown peripheral")\nError: \(error.localizedDescription)")
            return
        }
        Task {
            logger?.debug("Disconnected(2): \(peripheral.name ?? "Unknown peripheral")")
            await taskQueue?.popContinuation(for: peripheral.identifier)?.resume()
        }
    }
}

public struct Peripheral: Sendable {
    let cbPeripheral: CBPeripheral

    public var info: String {
        "Name: \(cbPeripheral.name ?? "Unknown"), UUID: \(cbPeripheral.identifier.uuidString)"
    }
}

public actor TetherCentral: Sendable {
    let central: CBCentralManager
    let centralDelegate: Delegate
    let dispatchQueue: DispatchQueue
    let taskQueue: Queue

    let logger: Logger = .init(subsystem: "sh.dmytro.tether", category: "central")

    public var state: State {
        State.from(cbState: central.state)
    }

    public init() {
        self.dispatchQueue = DispatchQueue(label: "sh.dmytro.tether.queue")
        self.taskQueue = Queue()
        self.centralDelegate = Delegate(taskQueue: self.taskQueue, logger: self.logger)
        self.central = CBCentralManager(delegate: self.centralDelegate, queue: self.dispatchQueue)
    }

    public func scanForPeripherals(withServices services: [UUID]) async throws -> AsyncStream<Peripheral> {
        guard await self.taskQueue.scanContinuation == nil else {
            throw TetherError.alreadyScanning
        }
        let cbUuids: [CBUUID] = services.map { CBUUID(nsuuid: $0) }
        let (stream, continuation) =  AsyncStream.makeStream(of: Peripheral.self)
        await self.taskQueue.setScanContinuation(continuation)
        self.centralDelegate.onDiscover = { @Sendable peripheral in
            continuation.yield(peripheral)
        }
        continuation.onTermination = { _ in
            self.central.stopScan()
            Task { await self.taskQueue.setScanContinuation(nil) }
        }
        self.central.scanForPeripherals(withServices: cbUuids)
        return stream
    }

    public func stopScan() async {
        await self.taskQueue.scanContinuation?.finish()
    }

    public func connect(_ peripheral: Peripheral) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                try await taskQueue.addConnect(continuation: continuation, for: peripheral.cbPeripheral.identifier)
                self.central.connect(peripheral.cbPeripheral, options: nil)
            }
        }
    }

    public func disconnect(_ peripheral: Peripheral) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                try await taskQueue.addConnect(continuation: continuation, for: peripheral.cbPeripheral.identifier)
                self.central.cancelPeripheralConnection(peripheral.cbPeripheral)
            }
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

