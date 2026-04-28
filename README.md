# Tether

An async/await CoreBluetooth wrapper for iOS, built with Swift 6 strict concurrency.

## Overview

Tether replaces CoreBluetooth's delegate-based API with a modern Swift concurrency interface. Scanning, connecting, service/characteristic discovery, reads, writes, and notifications all become `async` calls or `AsyncStream`s — no delegate boilerplate required.

## Requirements

- iOS 16+
- Swift 6.2+

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/dmytro-dovg/Tether", from: "0.1.0")
```

## Usage

```swift
let central = TetherCentral()

// Wait for Bluetooth to power on
await central.wait(for: .poweredOn)

// Scan for peripherals
let stream = try central.scanForPeripherals(withServices: [myServiceUUID])
for await peripheral in stream {
    central.stopScan()

    // Connect and discover
    try await central.connect(to: peripheral)
    let services = try await peripheral.discoverServices()
    let characteristics = try await peripheral.discoverCharacteristics(for: services[0].uuid)

    // Read / write
    let data = try await peripheral.readValue(for: characteristicUUID)
    try await peripheral.writeValue(data, for: characteristicUUID)

    // Subscribe to notifications
    let notifications = try await peripheral.notificationStream(for: characteristicUUID)
    for await value in notifications { /* handle */ }
}
```

## License

[MIT](LICENSE)
