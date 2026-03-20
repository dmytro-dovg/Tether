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

//   func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
//
//   }

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
            Task {
                await continuationManager.continuation(for: .disconnect(peripheral.identifier))?.resume(throwing: error)
            }
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
            Task {
                await continuationManager.continuation(for: .disconnect(peripheral.identifier))?.resume(throwing: error)
            }
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
        case didUpdateValueForCharacteristic(CBUUID)
        case didWriteValueForCharacteristic(CBUUID)
        case didUpdateValueForDescriptor(CBUUID)
        case didUpdateNotificationStateFor(CBUUID)
        case notification(CBUUID)
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
            let continuation = await continuationManager
                .continuation(for: .didDiscoverServices, as: [Service].self)
            if let error {
                logger?.warning("Peripheral \(peripheral.identifier) failed to discover services: \(error.localizedDescription)")
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did discover services")

            continuation?.resume(returning: peripheral.services?.compactMap({ Service(cbService: $0) }) ?? [])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .continuation(for: .didDiscoverCharacteristicsFor(service.uuid), as: [Characteristic].self)
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
            continuation?.resume(returning: service.characteristics?.compactMap({ Characteristic(cbCharacteristic: $0) }) ?? [])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        // Capture value before Task
        let data = characteristic.value
        Task {
            if let readContinuation = await continuationManager.continuation(
                for: .didUpdateValueForCharacteristic(characteristic.uuid), as: Data.self) {
                if let error {
                    logger?.warning(
                        """
                        Peripheral \(peripheral.identifier) failed to read value \
                        of characteristics \(characteristic.uuid) error: \(error.localizedDescription)
                        """
                    )
                    readContinuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    readContinuation.resume(throwing: PeripheralError.noValue)
                    return
                }
                logger?.debug("Peripheral \(peripheral.identifier) did read value of characteristics \(characteristic.uuid)")
                readContinuation.resume(returning: data)
            } else {
                if let error {
                    logger?.warning(
                        """
                        Peripheral \(peripheral.identifier) notification value failure \
                        of characteristics \(characteristic.uuid) error: \(error.localizedDescription)
                        """
                    )
                    return
                }
                logger?.debug("Peripheral \(peripheral.identifier) did receive notification for characteristics \(characteristic.uuid)")
                guard let data else {
                    // Nothing to yield
                    return
                }
                await continuationManager.yield(data, for: .notification(characteristic.uuid))
            }

        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .continuation(for: .didWriteValueForCharacteristic(characteristic.uuid))
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to write value \
                    of characteristics \(characteristic.uuid) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did write value of characteristics \(characteristic.uuid)")
            continuation?.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .continuation(for: .didUpdateNotificationStateFor(characteristic.uuid))
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to update notification state \
                    of characteristics \(characteristic.uuid) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("""
                    Peripheral \(peripheral.identifier) did update notification state \
                    (\(characteristic.isNotifying ? "on" : "off")) \(characteristic.uuid)
                    """
            )
            continuation?.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .continuation(for: .didDiscoverDescriptorsFor(characteristic.uuid), as: [Descriptor].self)
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to discover descriptors \
                    for \(characteristic.uuid.uuidString) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did discover descriptors for \(characteristic.uuid.uuidString)")
            continuation?.resume(returning: characteristic.descriptors?.compactMap({ Descriptor(cbDescriptor: $0) }) ?? [])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .continuation(for: .didUpdateValueForDescriptor(descriptor.uuid), as: Descriptor.Value.self)
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to read value \
                    of descriptor \(descriptor.uuid) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did read value of descriptor \(descriptor.uuid)")
            continuation?.resume(returning: Descriptor.Value(cbDescriptor: descriptor))
        }
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
    case noDescriptor
    case noValue
    case characteristicWrongType
}

public struct Service: Sendable, Hashable {
    public let identifier: UUID
}

extension Service {
    init?(cbService: CBService) {
        guard let uuid = cbService.uuid.toFoundationUUID else {
            return nil
        }
        self.init(identifier: uuid)
    }
}

public struct Characteristic: Sendable, Hashable {
    public let identifier: UUID
    public let properties: Properties
}

extension Characteristic {
    init?(cbCharacteristic: CBCharacteristic) {
        guard let uuid = cbCharacteristic.uuid.toFoundationUUID else {
            return nil
        }
        self.init(identifier: uuid, properties: Properties(rawValue: UInt(cbCharacteristic.properties.rawValue)))
    }
}

public struct Descriptor: Sendable, Hashable {
    public let identifier: UUID
}

extension Descriptor {
    init?(cbDescriptor: CBDescriptor) {
        guard let uuid = cbDescriptor.uuid.toFoundationUUID else {
            return nil
        }
        self.init(identifier: uuid)
    }
}
public extension Descriptor {
    enum Value: Sendable {
        case string(String)
        case number(UInt16)
        case data(Data)
        case unknown
    }
}

extension Descriptor.Value: Hashable {
    init(cbDescriptor: CBDescriptor) {
        switch cbDescriptor.uuid.uuidString {
        case CBUUIDCharacteristicUserDescriptionString:
            self = (cbDescriptor.value as? String).map { .string($0) } ?? .unknown
        case CBUUIDClientCharacteristicConfigurationString,
             CBUUIDServerCharacteristicConfigurationString,
             CBUUIDCharacteristicExtendedPropertiesString:
            self = (cbDescriptor.value as? NSNumber).map { .number($0.uint16Value) } ?? .unknown
        case CBUUIDCharacteristicFormatString,
             CBUUIDCharacteristicAggregateFormatString:
            self = (cbDescriptor.value as? Data).map { .data($0) } ?? .unknown
        default:
            self = .unknown
        }
    }
}

public extension Characteristic {
    struct Properties: OptionSet, Hashable, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let broadcast = Self(rawValue: 0x01)
        public static let read = Self(rawValue: 0x02)
        public static let writeWithoutResponse = Self(rawValue: 0x04)
        public static let write = Self(rawValue: 0x08)
        public static let notify = Self(rawValue: 0x10)
        public static let indicate = Self(rawValue: 0x20)
        public static let authenticatedSignedWrites = Self(rawValue: 0x40)
        public static let extendedProperties = Self(rawValue: 0x80)
        public static let notifyEncryptionRequired = Self(rawValue: 0x100)
        public static let indicateEncryptionRequired = Self(rawValue: 0x200)
    }
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
            .first(where: { $0.uuid == uuid.cbUUID })
        else {
            throw PeripheralError.noCharacteristic
        }
        return cbCharacteristic
    }

    public func discoverServices(_ services: [UUID]? = nil) async throws -> [Service] {
        try await cbPeripheralDelegate
            .continuationManager
            .waitForContinuationWithResult(for: .didDiscoverServices) {
                self.cbPeripheral.discoverServices(services?.cbUUIDs)
            }
    }

    public func discoverCharacteristics(_ characteristics: [UUID]? = nil, for serviceUuid: UUID) async throws -> [Characteristic] {
        guard let cbService = cbPeripheral.services?.first(where: { $0.uuid == serviceUuid.cbUUID }) else {
            throw PeripheralError.noService
        }
        return try await cbPeripheralDelegate
            .continuationManager
            .waitForContinuationWithResult(for: .didDiscoverCharacteristicsFor(serviceUuid.cbUUID)) {
                self.cbPeripheral.discoverCharacteristics(characteristics?.cbUUIDs, for: cbService)
            }
    }

    public func discoverDescriptors(_ characteristicUuid: UUID) async throws -> [Descriptor] {
        let cbCharacteristic = try characteristic(for: characteristicUuid)
        return try await cbPeripheralDelegate
            .continuationManager
            .waitForContinuationWithResult(for: .didDiscoverDescriptorsFor(characteristicUuid.cbUUID)) {
                self.cbPeripheral.discoverDescriptors(for: cbCharacteristic)
            }
    }

    public func readValue(for descriptorUuid: UUID, of characteristicUuid: UUID) async throws -> Descriptor.Value {
        let cbCharacteristic = try characteristic(for: characteristicUuid)
        guard let cbDescriptor = cbCharacteristic.descriptors?.first(where: { $0.uuid.toFoundationUUID == descriptorUuid }) else {
            throw PeripheralError.noDescriptor
        }
        return try await cbPeripheralDelegate
            .continuationManager
            .waitForContinuationWithResult(for: .didUpdateValueForDescriptor(descriptorUuid.cbUUID)) {
                cbPeripheral.readValue(for: cbDescriptor)
            }
    }

    public func readValue(for characteristicUuid: UUID) async throws -> Data {
        let cbCharacteristic = try characteristic(for: characteristicUuid)
        return try await cbPeripheralDelegate
            .continuationManager
            .waitForContinuationWithResult(for: .didUpdateValueForCharacteristic(characteristicUuid.cbUUID)) {
                cbPeripheral.readValue(for: cbCharacteristic)
            }
    }

    public func writeValue(_ value: Data, for characteristicUuid: UUID) async throws {
        let cbCharacteristic = try characteristic(for: characteristicUuid)
        guard cbCharacteristic.properties.contains(.write) else {
            throw PeripheralError.characteristicWrongType
        }
        try await cbPeripheralDelegate
            .continuationManager
            .waitForContinuation(for: .didWriteValueForCharacteristic(characteristicUuid.cbUUID)) {
                cbPeripheral.writeValue(value, for: cbCharacteristic, type: .withResponse)
            }
    }

    public func writeValueWithoutResponse(_ value: Data, for characteristicUuid: UUID) throws {
        let cbCharacteristic = try characteristic(for: characteristicUuid)

        guard cbCharacteristic.properties.contains(.writeWithoutResponse) else {
            throw PeripheralError.characteristicWrongType
        }
        cbPeripheral.writeValue(value, for: cbCharacteristic, type: .withoutResponse)
    }

    public func notificationStream(for characteristicUuid: UUID) async throws -> AsyncStream<Data> {
        let cbCharacteristic = try characteristic(for: characteristicUuid)
        guard cbCharacteristic.properties.contains(.notify) ||
                cbCharacteristic.properties.contains(.indicate) else {
            throw PeripheralError.characteristicWrongType
        }
        try await cbPeripheralDelegate.continuationManager
            .waitForContinuation(for: .didUpdateNotificationStateFor(characteristicUuid.cbUUID)) {
                cbPeripheral.setNotifyValue(true, for: cbCharacteristic)
            }
        return try await cbPeripheralDelegate
            .continuationManager
            .waitForStream(for: .notification(characteristicUuid.cbUUID)) { continuation in
                continuation.onTermination = { _ in
                    cbPeripheral.setNotifyValue(false, for: cbCharacteristic)
                    Task {
                        await self.cbPeripheralDelegate.continuationManager.finish(.notification(characteristicUuid.cbUUID))
                    }
                }
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
        try await cbCentralDelegate
            .continuationManager
            .waitForStream(for: .scan) { continuation in
                continuation.onTermination = { _ in
                    self.cbCentral.stopScan()
                    Task {
                        await self.cbCentralDelegate.continuationManager.finish(.scan)
                    }
                }
                self.cbCentral.scanForPeripherals(withServices: services.cbUUIDs)
            }
    }

    public func stopScan() async {
        await cbCentralDelegate.continuationManager.finish(.scan)
    }

    // MARK: - Connection
    public func connect(to peripheral: Peripheral) async throws {
        try await cbCentralDelegate
            .continuationManager
            .waitForContinuation(for: .connect(peripheral.identifier)) {
                self.cbCentral.connect(peripheral.cbPeripheral, options: nil)
            }
    }

    public func disconnect(from peripheral: Peripheral) async throws {
        try await cbCentralDelegate
            .continuationManager
            .waitForContinuation(for: .disconnect(peripheral.identifier)) {
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
