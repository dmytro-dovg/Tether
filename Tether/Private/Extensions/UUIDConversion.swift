//
//  UUID.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-18.
//

import CoreBluetooth

extension UUID {
    var cbUUID: CBUUID { .init(nsuuid: self) }
}

extension CBUUID {
    var nsUUID: UUID? { .init(uuidString: uuidString) }
}

extension Array where Element == UUID {
    var cbUUIDs: [CBUUID] { map { $0.cbUUID } }
}
