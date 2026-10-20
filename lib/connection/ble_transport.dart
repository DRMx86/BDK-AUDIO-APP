import 'dart:typed_data';

class BleTransportException implements Exception {
  const BleTransportException(this.message, {this.cleanupUncertain = false});
  final String message;
  final bool cleanupUncertain;
  @override
  String toString() => message;
}

/// Advertising is a candidate list. Connection still verifies the GATT service.
class DiscoveredSpeaker {
  const DiscoveredSpeaker({
    required this.id,
    required this.name,
    this.rssi,
    this.services = const [],
  });
  final String id, name;
  final int? rssi;
  final List<String> services;
}

class BleNotification {
  BleNotification(this.characteristic, List<int> bytes)
    : value = Uint8List.fromList(bytes);
  final String characteristic;
  final Uint8List value;
}

class BleDisconnect {
  const BleDisconnect({this.reason, this.nativeCode});
  final String? reason;
  final int? nativeCode;
}

/// Each connect returns a new link with isolated event streams. Implementations
/// must never forward an old link's events into a replacement link.
abstract interface class BleLink {
  String get deviceId;
  int get writeCapacity;
  Stream<BleNotification> get notifications;
  Stream<BleDisconnect> get disconnects;
  Future<void> subscribe(String characteristic);
  Future<void> write(Uint8List value, {bool withResponse = true});
  Future<void> disconnect();
  void dispose();
}

abstract interface class BleTransport {
  Stream<DiscoveredSpeaker> get scanResults;
  Future<void> startScan();
  Future<void> stopScan();
  Future<BleLink> connect(String id);
  void dispose();
}
