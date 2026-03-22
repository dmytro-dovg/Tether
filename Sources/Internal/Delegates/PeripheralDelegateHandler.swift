//
//  PeripheralDelegateHandler.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-22.
//

@preconcurrency import CoreBluetooth
import OSLog

class PeripheralDelegateHandler: NSObject, @unchecked Sendable {
    let continuationManager: ContinuationManager<Event> = .init()
    var logger: Logger?
}

extension PeripheralDelegateHandler {
    enum Event: Hashable {
        case didDiscoverServices
        case didDiscoverCharacteristicsFor(CBUUID)
        case didDiscoverDescriptorsFor(CBUUID)
        case didUpdateValueForCharacteristic(CBUUID)
        case didWriteValueForCharacteristic(CBUUID)
        case didUpdateValueForDescriptor(CBUUID)
        case didUpdateNotificationStateFor(CBUUID)
        case notification(CBUUID)
    }
}

extension PeripheralDelegateHandler: CBPeripheralDelegate {

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {

    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {

    }

    func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .removeContinuation(for: .didDiscoverServices, as: [Service].self)
            if let error {
                logger?.warning("Peripheral \(peripheral.identifier) failed to discover services: \(error.localizedDescription)")
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did discover services")

            continuation?.resume(returning: peripheral.services?.compactMap({ Service(cbService: $0) }) ?? [])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: (any Error)?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .removeContinuation(for: .didDiscoverCharacteristicsFor(service.uuid), as: [Characteristic].self)
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to discover characteristics \
                    for service \(service.uuid) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug(
                """
                Peripheral \(peripheral.identifier) did discover characteristics \
                for service \(service.uuid)
                """
            )
            continuation?.resume(returning: service.characteristics?.compactMap({ Characteristic(cbCharacteristic: $0) }) ?? [])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        // Capture value before Task
        let data = characteristic.value
        Task {
            if let readContinuation = await continuationManager
                .removeContinuation(
                for: .didUpdateValueForCharacteristic(characteristic.uuid), as: Data.self) {
                if let error {
                    logger?.warning(
                        """
                        Peripheral \(peripheral.identifier) failed to read value \
                        of characteristics \(characteristic.uuid) error: \(error.localizedDescription)
                        """
                    )
                    readContinuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    readContinuation.resume(throwing: Peripheral.Error.noValue)
                    return
                }
                logger?.debug("Peripheral \(peripheral.identifier) did read value of characteristics \(characteristic.uuid)")
                readContinuation.resume(returning: data)
            } else {
                if let error {
                    logger?.warning(
                        """
                        Peripheral \(peripheral.identifier) notification value failure \
                        of characteristics \(characteristic.uuid) error: \(error.localizedDescription)
                        """
                    )
                    return
                }
                logger?.debug("Peripheral \(peripheral.identifier) did receive notification for characteristics \(characteristic.uuid)")
                guard let data else {
                    // Nothing to yield
                    return
                }
                await continuationManager.yield(data, for: .notification(characteristic.uuid))
            }

        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .removeContinuation(for: .didWriteValueForCharacteristic(characteristic.uuid))
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to write value \
                    of characteristics \(characteristic.uuid) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did write value of characteristics \(characteristic.uuid)")
            continuation?.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .removeContinuation(for: .didUpdateNotificationStateFor(characteristic.uuid))
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to update notification state \
                    of characteristics \(characteristic.uuid) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("""
                    Peripheral \(peripheral.identifier) did update notification state \
                    (\(characteristic.isNotifying ? "on" : "off")) \(characteristic.uuid)
                    """
            )
            continuation?.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .removeContinuation(for: .didDiscoverDescriptorsFor(characteristic.uuid), as: [Descriptor].self)
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to discover descriptors \
                    for \(characteristic.uuid.uuidString) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did discover descriptors for \(characteristic.uuid.uuidString)")
            continuation?.resume(returning: characteristic.descriptors?.compactMap({ Descriptor(cbDescriptor: $0) }) ?? [])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: (any Error)?) {
        Task {
            let continuation = await continuationManager
                .removeContinuation(for: .didUpdateValueForDescriptor(descriptor.uuid), as: Descriptor.Value.self)
            if let error {
                logger?.warning(
                    """
                    Peripheral \(peripheral.identifier) failed to read value \
                    of descriptor \(descriptor.uuid) error: \(error.localizedDescription)
                    """
                )
                continuation?.resume(throwing: error)
                return
            }
            logger?.debug("Peripheral \(peripheral.identifier) did read value of descriptor \(descriptor.uuid)")
            continuation?.resume(returning: Descriptor.Value(cbDescriptor: descriptor))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: (any Error)?) {

    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {

    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: (any Error)?) {

    }
}
