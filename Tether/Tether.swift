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

class CentralDelegateHandler: NSObject, @unchecked Sendable {
    var logger: Logger?
    let continuationManager: ContinuationManager<Event>

    init(continuationManager: ContinuationManager<Event> = .init(), logger: Logger? = nil) {
        self.logger = logger
        self.continuationManager = continuationManager
    }
}

extension CentralDelegateHandler {
    enum Event: Hashable {
        case scan
        case connect(UUID)
        case disconnect(UUID)
    }
}

extension CentralDelegateHandler: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {

    }

//    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
//
//    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task {
            await continuationManager.yield(Peripheral(cbPeripheral: peripheral), for: .scan)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task {
            logger?.debug("Connected: \(peripheral.name ?? "Unknown peripheral")")
            await continuationManager.continuation(for: .connect(peripheral.identifier))?.resume()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Task {
            let errorToThrow = error ?? TetherError.unknownError
            logger?.warning("Failed to connect: \(peripheral.name ?? "Unknown peripheral")\nError: \(errorToThrow.localizedDescription)")
            await continuationManager.continuation(for: .connect(peripheral.identifier))?.resume(throwing: errorToThrow)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        if let error {
            logger?.warning("Disconnected with error: \(peripheral.name ?? "Unknown peripheral")\nError: \(error.localizedDescription)")
            Task { await continuationManager.continuation(for: .disconnect(peripheral.identifier))?.resume(throwing: error) }
            return
        }
        Task {
            logger?.debug("Disconnected: \(peripheral.name ?? "Unknown peripheral")")
            await continuationManager.continuation(for: .disconnect(peripheral.identifier))?.resume()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if let error {
            logger?.warning("Disconnected(2) with error: \(peripheral.name ?? "Unknown peripheral")\nError: \(error.localizedDescription)")
            Task { await continuationManager.continuation(for: .disconnect(peripheral.identifier))?.resume(throwing: error) }
            return
        }
        Task {
            logger?.debug("Disconnected(2): \(peripheral.name ?? "Unknown peripheral")")
            await continuationManager.continuation(for: .disconnect(peripheral.identifier))?.resume()
        }
    }
}

class PeripheralDelegateHandler: NSObject, @unchecked Sendable {
    let continuationManager: ContinuationManager<Event> = .init()
    var logger: Logger?
}

extension PeripheralDelegateHandler {
    enum Event: Hashable {
        case didDiscoverServices
        case didDiscoverCharacteristicsFor(CBUUID)
        case didDiscoverDescriptorsFor(CBUUID)
        case didUpdateValueFor(CBUUID)
    }
}

extension PeripheralDelegateHandler: CBPeripheralDelegate {

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {

    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {

    }

    func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task {
            let continuation = await continuationManager.continuation(for: .didDiscoverServices)
            if let error {
                logger?.warning("Peripheral \(peripheral.identifier) failed to discover services: \(error.localizedDescription)")
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did discover services")
            continuation?.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        Task {
            let continuation = await continuationManager.continuation(for: .didDiscoverCharacteristicsFor(service.uuid))
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to discover characteristics \
                    for service \(service.uuid) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug(
                """
                Peripheral \(peripheral.identifier) did discover characteristics \
                for service \(service.uuid)
                """
            )
            continuation?.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task {
            let continuation = await continuationManager.readContinuation(for: .didUpdateValueFor(characteristic.uuid))
            if let error {
                logger?.warning("Peripheral \(peripheral.identifier) failed to read value of characteristics \(characteristic.uuid) error: \(error.localizedDescription)")
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did read value of characteristics \(characteristic.uuid)")
            continuation?.resume(returning: characteristic.value)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task {
            let continuation = await continuationManager.continuation(for: .didDiscoverDescriptorsFor(characteristic.uuid))
            if let error {
                logger?.warning("Peripheral \(peripheral.identifier) failed to discover descriptors: \(error.localizedDescription) for \(characteristic.uuid.uuidString) error: \(error.localizedDescription)")
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did discover descriptors for \(characteristic.uuid.uuidString)")
            continuation?.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: (any Error)?) {

    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {

    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: (any Error)?) {

    }
}

enum PeripheralError: Error {
    case noService
    case noCharacteristic
}

public struct Peripheral: Sendable {
    let cbPeripheral: CBPeripheral
    public var identifier: UUID { cbPeripheral.identifier }
    public var name: String? { cbPeripheral.name }
    private let cbPeripheralDelegate: PeripheralDelegateHandler

    init(cbPeripheral: CBPeripheral) {
        cbPeripheralDelegate = PeripheralDelegateHandler()
        cbPeripheralDelegate.logger = .init(subsystem: "sh.dovgo.tether", category: "peripheral")
        cbPeripheral.delegate = cbPeripheralDelegate
        self.cbPeripheral = cbPeripheral
    }

    private func characteristic(for uuid: UUID) throws -> CBCharacteristic {
        guard let cbCharacteristic = cbPeripheral.services?
            .lazy
            .flatMap({ $0.characteristics ?? [] })
            .first(where: { $0.uuid == uuid.coreBluetoothUUID })
        else {
            throw PeripheralError.noCharacteristic
        }
        return cbCharacteristic
    }

    public func discoverServices(_ services: [UUID]? = nil) async throws {
        try await cbPeripheralDelegate.continuationManager.waitForContinuation(for: .didDiscoverServices) {
            self.cbPeripheral.discoverServices(services?.coreBluetoothUUIDs)
        }
    }

    public func discoverCharacteristics(_ characteristics: [UUID]? = nil, for serviceUuid: UUID) async throws {
        guard let cbService = cbPeripheral.services?.first(where: { $0.uuid == serviceUuid.coreBluetoothUUID }) else {
            throw PeripheralError.noService
        }
        try await cbPeripheralDelegate.continuationManager.waitForContinuation(for: .didDiscoverCharacteristicsFor(serviceUuid.coreBluetoothUUID)) {
            self.cbPeripheral.discoverCharacteristics(characteristics?.coreBluetoothUUIDs, for: cbService)
        }
    }

    public func discoverDescriptors(_ characteristicUuid: UUID) async throws {
        let cbCharacteristic = try characteristic(for: characteristicUuid)
        try await cbPeripheralDelegate.continuationManager.waitForContinuation(for: .didDiscoverDescriptorsFor(characteristicUuid.coreBluetoothUUID)) {
            self.cbPeripheral.discoverDescriptors(for: cbCharacteristic)
        }
    }

    public func readValue(for characteristicUuid: UUID) async throws -> Data? {
        let cbCharacteristic = try characteristic(for: characteristicUuid)
        return try await cbPeripheralDelegate.continuationManager.waitForReadContinuation(for: .didUpdateValueFor(characteristicUuid.coreBluetoothUUID)) {
            cbPeripheral.readValue(for: cbCharacteristic)
        }
    }
}

extension Peripheral: CustomDebugStringConvertible {
    public var debugDescription: String {
        "Name: \(name ?? "Unknown"), UUID: \(identifier.uuidString)"
    }
}

public actor TetherCentral {
    private let cbCentral: CBCentralManager
    private let cbCentralDelegate: CentralDelegateHandler
    private let logger: Logger = .init(subsystem: "sh.dovgo.tether", category: "central")
    public var state: State {
        State.from(cbState: cbCentral.state)
    }

    public func isScanning() async -> Bool {
        await cbCentralDelegate.continuationManager.hasStream(for: .scan)
    }

    public init() {
        self.cbCentralDelegate = CentralDelegateHandler(continuationManager: ContinuationManager(), logger: self.logger)
        self.cbCentral = CBCentralManager(delegate: self.cbCentralDelegate, queue: DispatchQueue.global())
    }

    // MARK: - Scanning
    public func scanForPeripherals(withServices services: [UUID]) async throws -> AsyncStream<Peripheral> {
        try await cbCentralDelegate.continuationManager.waitForStream(for: .scan) { continuation in
            continuation.onTermination = { _ in
                self.cbCentral.stopScan()
                Task { await self.cbCentralDelegate.continuationManager.finish(.scan) }
            }
            self.cbCentral.scanForPeripherals(withServices: services.coreBluetoothUUIDs)
        }
    }

    public func stopScan() async {
        await cbCentralDelegate.continuationManager.finish(.scan)
    }

    // MARK: - Connection
    public func connect(to peripheral: Peripheral) async throws {
        try await cbCentralDelegate.continuationManager.waitForContinuation(for: .connect(peripheral.identifier)) {
            self.cbCentral.connect(peripheral.cbPeripheral, options: nil)
        }
    }

    public func disconnect(from peripheral: Peripheral) async throws {
        try await cbCentralDelegate.continuationManager.waitForContinuation(for: .disconnect(peripheral.identifier)) {
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
