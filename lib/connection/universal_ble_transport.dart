import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';
import '../protocol/speaker_protocol.dart';
import 'ble_transport.dart';
export 'ble_transport.dart' show BleTransportException;

class UniversalBleTransport implements BleTransport {
  UniversalBleTransport({this.timeout = const Duration(seconds: 10)});
  final Duration timeout;
  final _links = <_UniversalBleLink>{};
  final _devices = <String, _DeviceConnectionOwner>{};
  bool _disposed = false;

  @override
  Stream<DiscoveredSpeaker> get scanResults => UniversalBle.scanStream.map(
    (device) => DiscoveredSpeaker(
      id: device.deviceId,
      name: device.rawName ?? device.name ?? 'Unnamed speaker',
      rssi: device.rssi,
      services: List.unmodifiable(device.services),
    ),
  );

  void _checkAlive() {
    if (_disposed) {
      throw const BleTransportException('Bluetooth transport is closed.');
    }
  }

  Future<void> _ensureAvailable() async {
    _checkAlive();
    if (!await UniversalBle.hasPermissions().timeout(timeout)) {
      await UniversalBle.requestPermissions().timeout(timeout);
      if (!await UniversalBle.hasPermissions().timeout(timeout)) {
        throw const BleTransportException(
          'Allow Bluetooth / Nearby devices permission in system settings, then try again.',
        );
      }
    }
    final availability = await UniversalBle.getBluetoothAvailabilityState()
        .timeout(timeout);
    if (availability != AvailabilityState.poweredOn) {
      throw BleTransportException(switch (availability) {
        AvailabilityState.poweredOff =>
          'Turn on Bluetooth in system settings, then try again.',
        AvailabilityState.unauthorized =>
          'Allow Bluetooth access in system settings, then try again.',
        AvailabilityState.unsupported =>
          'Bluetooth Low Energy is unavailable on this device or adapter.',
        _ =>
          'Bluetooth is ${availability.name}; wait for the adapter and try again.',
      });
    }
  }

  @override
  Future<void> startScan() async {
    await _ensureAvailable();
    // Filtering in the session allows service advertisements and legacy BDK
    // names; neither path silently selects one of multiple candidates.
    // Foreground setup owns the scan lifetime and stops it on exit/background.
    // Android otherwise defaults to low-power discovery rather than prompt setup.
    await UniversalBle.startScan(
      platformConfig: PlatformConfig(
        android: AndroidOptions(
          scanMode: AndroidScanMode.lowLatency,
          reportDelayMillis: 0,
        ),
      ),
    ).timeout(timeout);
  }

  @override
  Future<void> stopScan() async {
    _checkAlive();
    await UniversalBle.stopScan().timeout(timeout);
  }

  @override
  Future<BleLink> connect(String id) {
    _checkAlive();
    final key = UniversalBle.canonicalDeviceId(id);
    final owner = _devices.putIfAbsent(key, _DeviceConnectionOwner.new);
    return owner.run(() => _connectOwned(id, owner));
  }

  Future<BleLink> _connectOwned(String id, _DeviceConnectionOwner owner) async {
    await _ensureAvailable();
    _checkAlive();
    final previous = owner.link;
    if (previous != null) {
      // Runs inside the same per-device gate as connect/disconnect. Complete
      // old native cleanup before a replacement can own this device ID.
      await previous._disconnectNativeIfOwner();
      previous.dispose();
    }
    final link = _UniversalBleLink(id, timeout, owner, () {});
    owner.link = link;
    link.onDisposed = () => _links.remove(link);
    _links.add(link);
    try {
      await UniversalBle.connect(id, timeout: timeout).timeout(timeout);
      final services = await UniversalBle.discoverServices(
        id,
        timeout: timeout,
      ).timeout(timeout);
      final matching = services
          .where((s) => s.uuid.toLowerCase() == SpeakerProtocol.service)
          .toList();
      if (matching.length != 1) {
        throw const BleTransportException(
          'This device does not expose one compatible BDK speaker service. Select a compatible speaker.',
        );
      }
      final service = matching.single;
      void requireCharacteristic(String uuid, CharacteristicProperty property) {
        final matches = service.characteristics
            .where((c) => c.uuid.toLowerCase() == uuid)
            .toList();
        if (matches.length != 1 ||
            !matches.single.properties.contains(property)) {
          throw BleTransportException(
            'Speaker is missing the required $property characteristic $uuid. Check firmware compatibility.',
          );
        }
      }

      requireCharacteristic(
        SpeakerProtocol.command,
        CharacteristicProperty.write,
      );
      requireCharacteristic(
        SpeakerProtocol.status,
        CharacteristicProperty.notify,
      );
      requireCharacteristic(
        SpeakerProtocol.meterCharacteristic,
        CharacteristicProperty.notify,
      );
      final mtu = await UniversalBle.requestMtu(
        id,
        247,
        timeout: timeout,
      ).timeout(timeout);
      if (mtu < 23) {
        throw BleTransportException(
          'Bluetooth reported an invalid MTU of $mtu. Reconnect the speaker.',
        );
      }
      // This is the returned value, not the requested MTU. ATT's three-byte
      // header and the 512-byte characteristic-value limit both apply.
      link.capacity = math.min(mtu - 3, 512);
      link.checkConnected();
      return link;
    } catch (error, stack) {
      Object? cleanupError;
      try {
        await link._disconnectNativeIfOwner();
      } catch (failure) {
        cleanupError = failure;
      }
      link.dispose();
      if (cleanupError != null) {
        Error.throwWithStackTrace(
          BleTransportException(
            '$error Native disconnect could not be confirmed: $cleanupError',
            cleanupUncertain: true,
          ),
          stack,
        );
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(UniversalBle.stopScan().timeout(timeout).catchError((_) {}));
    for (final link in _links.toList()) {
      unawaited(link.disconnect().catchError((_) {}));
      link.dispose();
    }
  }
}

/// Native Bluetooth APIs identify operations by device ID, not by our session
/// generation. Serialize lifecycle operations for that ID and retain the exact
/// owning link so a delayed cleanup cannot close a newer native connection.
class _DeviceConnectionOwner {
  _UniversalBleLink? link;
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }
}

class _UniversalBleLink implements BleLink {
  _UniversalBleLink(this.deviceId, this.timeout, this._owner, this.onDisposed) {
    // Device-filtered native streams are bound once to this link instance.
    // Cancellation and a closed flag stop prior subscriptions forwarding events.
    for (final characteristic in [
      SpeakerProtocol.status,
      SpeakerProtocol.meterCharacteristic,
    ]) {
      _subscriptions.add(
        UniversalBle.characteristicValueStream(deviceId, characteristic).listen(
          (value) {
            if (!_disposed && _connected && identical(_owner.link, this)) {
              _notifications.add(BleNotification(characteristic, value));
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!_disposed && identical(_owner.link, this)) {
              _notifications.addError(error, stack);
            }
          },
        ),
      );
    }
    _subscriptions.add(
      UniversalBle.connectionChangeStream(deviceId).listen(
        (change) {
          if (_disposed || !identical(_owner.link, this)) return;
          _connected = change.isConnected;
          if (!change.isConnected) {
            _lost = BleDisconnect(
              reason: change.error ?? change.errorCode?.name,
              nativeCode: change.nativeErrorCode,
            );
            _disconnects.add(_lost!);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!_disposed && identical(_owner.link, this)) {
            _connected = false;
            _lost = BleDisconnect(reason: error.toString());
            _disconnects.addError(error, stack);
          }
        },
      ),
    );
  }
  @override
  final String deviceId;
  final Duration timeout;
  final _DeviceConnectionOwner _owner;
  void Function() onDisposed;
  int capacity = 20;
  @override
  int get writeCapacity => capacity;
  final _notifications = StreamController<BleNotification>.broadcast(
    sync: true,
  );
  final _disconnects = StreamController<BleDisconnect>.broadcast(sync: true);
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _disposed = false, _connected = true;
  BleDisconnect? _lost;
  Future<void>? _disconnecting;
  @override
  Stream<BleNotification> get notifications => _notifications.stream;
  @override
  Stream<BleDisconnect> get disconnects => _disconnects.stream;

  void checkConnected() {
    if (_disposed || !_connected || !identical(_owner.link, this)) {
      throw BleTransportException(
        'Speaker link is closed: ${_lost?.reason ?? 'disconnected'}. Reconnect the speaker.',
      );
    }
  }

  @override
  Future<void> subscribe(String characteristic) async {
    checkConnected();
    if (characteristic != SpeakerProtocol.status &&
        characteristic != SpeakerProtocol.meterCharacteristic) {
      throw const BleTransportException(
        'Unsupported speaker notification characteristic.',
      );
    }
    await UniversalBle.subscribeNotifications(
      deviceId,
      SpeakerProtocol.service,
      characteristic,
      timeout: timeout,
    ).timeout(timeout);
    checkConnected();
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    checkConnected();
    if (value.isEmpty || value.length > capacity) {
      throw BleTransportException(
        'Command needs ${value.length} bytes; negotiated BLE capacity is $capacity.',
      );
    }
    await UniversalBle.write(
      deviceId,
      SpeakerProtocol.service,
      SpeakerProtocol.command,
      value,
      withoutResponse: !withResponse,
      timeout: timeout,
    ).timeout(timeout);
    checkConnected();
  }

  @override
  Future<void> disconnect() =>
      _disconnecting ??= _owner.run(_disconnectNativeIfOwner);
  Future<void> _disconnectNativeIfOwner() async {
    if (!identical(_owner.link, this)) return;
    try {
      await UniversalBle.disconnect(
        deviceId,
        timeout: timeout,
      ).timeout(timeout);
      // Some native failures are caught internally; verify the returned state.
      final current = await UniversalBle.getConnectionState(
        deviceId,
      ).timeout(timeout);
      if (current != BleConnectionState.disconnected) {
        throw BleTransportException(
          'Native Bluetooth still reports ${current.name} after disconnect. Retry from system Bluetooth settings.',
          cleanupUncertain: true,
        );
      }
    } catch (error) {
      if (error is BleTransportException && error.cleanupUncertain) rethrow;
      throw BleTransportException(
        'Native disconnect could not be confirmed: $error',
        cleanupUncertain: true,
      );
    }
    _connected = false;
    _owner.link = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_notifications.close());
    unawaited(_disconnects.close());
    onDisposed();
  }
}
