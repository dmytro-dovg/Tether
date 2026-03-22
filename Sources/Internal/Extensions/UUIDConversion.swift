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
    private static let bluetoothBaseSuffix = "-0000-1000-8000-00805F9B34FB"

    var toFoundationUUID: UUID? {
        if let uuid = UUID(uuidString: uuidString) { return uuid }

        let expanded: String
        switch uuidString.count {
            // 16-bit
        case 4: expanded = "0000\(uuidString)\(Self.bluetoothBaseSuffix)"
            // 32-bit
        case 8: expanded = "\(uuidString)\(Self.bluetoothBaseSuffix)"
        default: return nil
        }
        return UUID(uuidString: expanded)
    }
}

extension Array where Element == UUID {
    var cbUUIDs: [CBUUID] { map { $0.cbUUID } }
}
