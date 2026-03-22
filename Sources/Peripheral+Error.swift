//
//  ErrorTypes.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-22.
//

public extension Peripheral {
    enum Error: Swift.Error {
        case alreadyInProgress
        case noService
        case noCharacteristic
        case noDescriptor
        case noValue
        case characteristicWrongType
    }
}
