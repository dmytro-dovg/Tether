//
//  CentralDelegateHandler.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-22.
//

@preconcurrency import CoreBluetooth
import OSLog

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
        case state(UUID)
        case scan
        case connect(UUID)
        case disconnect(UUID)
    }
}

extension CentralDelegateHandler.Event {
    var isState: Bool {
            if case .state = self {
                return true
            }
            return false
    }
}

extension CentralDelegateHandler: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = TetherCentral.State(central.state)
        Task {
            await self.continuationManager.yield(state, where: \.isState)
        }
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
            await continuationManager.removeContinuation(for: .connect(peripheral.identifier))?.resume()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Task {
            let errorToThrow = error ?? TetherError.unknownError
            logger?.warning("Failed to connect: \(peripheral.name ?? "Unknown peripheral")\nError: \(errorToThrow.localizedDescription)")
            await continuationManager.removeContinuation(for: .connect(peripheral.identifier))?.resume(throwing: errorToThrow)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        if let error {
            logger?.warning("Disconnected with error: \(peripheral.name ?? "Unknown peripheral")\nError: \(error.localizedDescription)")
            Task {
                await continuationManager.removeContinuation(for: .disconnect(peripheral.identifier))?.resume(throwing: error)
            }
            return
        }
        Task {
            logger?.debug("Disconnected: \(peripheral.name ?? "Unknown peripheral")")
            await continuationManager.removeContinuation(for: .disconnect(peripheral.identifier))?.resume()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if let error {
            logger?.warning("Disconnected(2) with error: \(peripheral.name ?? "Unknown peripheral")\nError: \(error.localizedDescription)")
            Task {
                await continuationManager.removeContinuation(for: .disconnect(peripheral.identifier))?.resume(throwing: error)
            }
            return
        }
        Task {
            logger?.debug("Disconnected(2): \(peripheral.name ?? "Unknown peripheral")")
            await continuationManager.removeContinuation(for: .disconnect(peripheral.identifier))?.resume()
        }
    }
}
