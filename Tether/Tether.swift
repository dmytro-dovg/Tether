//
//  Tether.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-16.
//

import Foundation
@preconcurrency import CoreBluetooth

enum TetherError: Error {
    case alreadyScanning
}

actor Queue {
    var scanContinuation: AsyncStream<Peripheral>.Continuation? = nil
    func setScanContinuation(_ continuation: AsyncStream<Peripheral>.Continuation?) {
        scanContinuation = continuation
    }
    actor ConnectTask {
        let peripheral: Peripheral
        let completion: @Sendable (Result<Void, Error>) -> Void


        init(peripheral: Peripheral, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
            self.peripheral = peripheral
            self.completion = completion
        }
    }

    var connectTasks: [ConnectTask] = []

    func startConnectTask(peripheral: Peripheral, _ body: @escaping @Sendable (Result<Void, Error>) -> Void) -> ConnectTask {
        let task = ConnectTask(peripheral: peripheral, completion: body)
        self.connectTasks.append(task)
        return task
    }
    
    func takeConnectTask(for identifier: UUID) -> ConnectTask? {
        if let index = connectTasks.firstIndex(where: { $0.peripheral.cbPeripheral.identifier == identifier }) {
            return connectTasks.remove(at: index)
        }
        return nil
    }
}

class Delegate: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    weak var taskQueue: Queue?
    var onDiscover: (@Sendable (Peripheral) -> Void)?

    init(taskQueue: Queue) {
        self.taskQueue = taskQueue
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        onDiscover?(Peripheral(cbPeripheral: peripheral))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task {
            print("++++ Success connect")
            if let task = await taskQueue?.takeConnectTask(for: peripheral.identifier) {
                task.completion(.success(()))
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Task {
            guard let error else {
                print("++++ No error")
                return
            }
            print("++++ Failure connect")
            if let task = await taskQueue?.takeConnectTask(for: peripheral.identifier) {
                task.completion(.failure(error))
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        if let error {
            print("++++ Disconnect due to a failure: \(error)")
            return
        }
        Task {
            print("++++ Success disconnect")
            if let task = await taskQueue?.takeConnectTask(for: peripheral.identifier) {
                task.completion(.success(()))
            }
        }

    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if let error {
            print("++++ Disconnect 2 due to a failure: \(error)")
            return
        }
        Task {
            print("++++ Success disconnect 2")
            if let task = await taskQueue?.takeConnectTask(for: peripheral.identifier) {
                task.completion(.success(()))
            }
        }
    }
}

public struct Peripheral: Sendable {
    let cbPeripheral: CBPeripheral

    public var info: String {
        "Name: \(cbPeripheral.name ?? "Unknown"), UUID: \(cbPeripheral.identifier.uuidString)"
    }
}

public final class TetherCentral: Sendable {
    let central: CBCentralManager
    let centralDelegate: Delegate
    let dispatchQueue: DispatchQueue
    let taskQueue: Queue

    public var state: State {
        State.from(cbState: central.state)
    }

    public init() {
        self.dispatchQueue = DispatchQueue(label: "sh.dmytro.tether.queue")
        self.taskQueue = Queue()
        self.centralDelegate = Delegate(taskQueue: self.taskQueue)
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
                await self.taskQueue.startConnectTask(peripheral: peripheral) { result in
                    switch result {
                        case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            self.central.connect(peripheral.cbPeripheral, options: nil)
        }
    }

    public func disconnect(_ peripheral: Peripheral) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                await self.taskQueue.startConnectTask(peripheral: peripheral) { result in
                    switch result {
                        case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            self.central.cancelPeripheralConnection(peripheral.cbPeripheral)
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

