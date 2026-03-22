//
//  Characteristic.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-22.
//

@preconcurrency import CoreBluetooth

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
