//
//  ErrorTypes.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-22.
//

public enum TetherError: Error {
    case alreadyScanning
    case alreadyConnected
    case alreadyDisconnecting
    case unknownError
}

public enum PeripheralError: Error {
    case noService
    case noCharacteristic
    case noDescriptor
    case noValue
    case characteristicWrongType
}
