//
//  UUID.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-18.
//

import CoreBluetooth

extension UUID {
    var coreBluetoothUUID: CBUUID { .init(nsuuid: self) }
}

extension Array where Element == UUID {
    var coreBluetoothUUIDs: [CBUUID] { map { $0.coreBluetoothUUID } }
}
