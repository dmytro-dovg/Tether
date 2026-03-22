//
//  Peripheral.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-22.
//

@preconcurrency import CoreBluetooth

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
            .continuationWithResult(for: .didDiscoverServices) {
                self.cbPeripheral.discoverServices(services?.cbUUIDs)
            }
    }

    public func discoverCharacteristics(_ characteristics: [UUID]? = nil, for serviceUuid: UUID) async throws -> [Characteristic] {
        guard let cbService = cbPeripheral.services?.first(where: { $0.uuid == serviceUuid.cbUUID }) else {
            throw PeripheralError.noService
        }
        return try await cbPeripheralDelegate
            .continuationManager
            .continuationWithResult(for: .didDiscoverCharacteristicsFor(serviceUuid.cbUUID)) {
                self.cbPeripheral.discoverCharacteristics(characteristics?.cbUUIDs, for: cbService)
            }
    }

    public func discoverDescriptors(_ characteristicUuid: UUID) async throws -> [Descriptor] {
        let cbCharacteristic = try characteristic(for: characteristicUuid)
        return try await cbPeripheralDelegate
            .continuationManager
            .continuationWithResult(for: .didDiscoverDescriptorsFor(characteristicUuid.cbUUID)) {
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
            .continuationWithResult(for: .didUpdateValueForDescriptor(descriptorUuid.cbUUID)) {
                cbPeripheral.readValue(for: cbDescriptor)
            }
    }

    public func readValue(for characteristicUuid: UUID) async throws -> Data {
        let cbCharacteristic = try characteristic(for: characteristicUuid)
        return try await cbPeripheralDelegate
            .continuationManager
            .continuationWithResult(for: .didUpdateValueForCharacteristic(characteristicUuid.cbUUID)) {
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
            .continuation(for: .didWriteValueForCharacteristic(characteristicUuid.cbUUID)) {
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
            .continuation(for: .didUpdateNotificationStateFor(characteristicUuid.cbUUID)) {
                cbPeripheral.setNotifyValue(true, for: cbCharacteristic)
            }
        return try await cbPeripheralDelegate
            .continuationManager
            .stream(for: .notification(characteristicUuid.cbUUID)) { continuation in
                continuation.onTermination = { _ in
                    cbPeripheral.setNotifyValue(false, for: cbCharacteristic)
                    Task {
                        await self.cbPeripheralDelegate.continuationManager.finish(.notification(characteristicUuid.cbUUID))
                    }
                }
            }
    }
}
