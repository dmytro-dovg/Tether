//
//  Service.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-22.
//

@preconcurrency import CoreBluetooth

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
