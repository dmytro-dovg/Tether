//
//  Descriptor.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-22.
//

@preconcurrency import CoreBluetooth

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
