import 'dart:async';
import 'dart:typed_data';
import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/connection/speaker_setup_controller.dart';
import 'package:bdk_audio/connection/universal_ble_transport.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/platform/audio_connection_adapter.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

// Hand-checked full status: EQ 0/-1/2, unknown control bit 7, Spectrum,
// brightness 70, speed 50, cyan/purple, horizontal gradient, no sounds, BDK/v1.
const fullStatus = [
  0xf0,
  0,
  255,
  2,
  0x84,
  0,
  70,
  50,
  0x74,
  0xd9,
  0xff,
  0xbc,
  0x9a,
  0xff,
  1,
  0,
  3,
  66,
  68,
  75,
  2,
  118,
  49,
];

class FakeLink implements BleLink {
  FakeLink(this.deviceId, {this.writeCapacity = 244});
  @override
  final String deviceId;
  @override
  final int writeCapacity;
  final notificationController = StreamController<BleNotification>.broadcast(
    sync: true,
  );
  final disconnectController = StreamController<BleDisconnect>.broadcast(
    sync: true,
  );
  final operations = <String>[];
  final writes = <List<int>>[];
  void Function(Uint8List)? onWrite;
  Future<void> Function(String)? onSubscribe;
  Object? writeError;
  Object? disconnectError;
  Completer<void>? writeGate;
  @override
  Stream<BleNotification> get notifications => notificationController.stream;
  @override
  Stream<BleDisconnect> get disconnects => disconnectController.stream;
  @override
  Future<void> subscribe(String characteristic) async {
    operations.add('subscribe:$characteristic');
    await onSubscribe?.call(characteristic);
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    operations.add('write:${value.first}');
    writes.add(value.toList());
    if (writeError != null) throw writeError!;
    onWrite?.call(value);
    await writeGate?.future;
  }

  void status(List<int> p) =>
      notificationController.add(BleNotification(SpeakerProtocol.status, p));
  void meter(List<int> p) => notificationController.add(
    BleNotification(SpeakerProtocol.meterCharacteristic, p),
  );
  @override
  Future<void> disconnect() async {
    operations.add('disconnect');
    if (disconnectError != null) throw disconnectError!;
  }

  // Controllers deliberately survive disposal: delayed native events are tested.
  @override
  void dispose() {}
  Future<void> close() async {
    await notificationController.close();
    await disconnectController.close();
  }
}

class FakeTransport implements BleTransport {
  final scanController = StreamController<DiscoveredSpeaker>.broadcast(
    sync: true,
  );
  final links = <FakeLink>[];
  Object? connectError;
  Completer<void>? scanGate;
  int scanStarts = 0, scanStops = 0;
  @override
  Stream<DiscoveredSpeaker> get scanResults => scanController.stream;
  @override
  Future<void> startScan() async {
    scanStarts++;
    await scanGate?.future;
  }

  @override
  Future<void> stopScan() async {
    scanStops++;
  }

  @override
  Future<BleLink> connect(String id) async {
    if (connectError != null) throw connectError!;
    return links.firstWhere((l) => l.deviceId == id);
  }

  @override
  void dispose() {}
  Future<void> close() async {
    await scanController.close();
    for (final l in links) {
      await l.close();
    }
  }
}

// The plugin's real command queue, streams and event normalization remain in
// use; only the physical OS interface is replaced.
class NativePlatform extends UniversalBlePlatform {
  AvailabilityState availability = AvailabilityState.poweredOn;
  List<BleService> services = [
    BleService(SpeakerProtocol.service, [
      BleCharacteristic(SpeakerProtocol.command, [
        CharacteristicProperty.write,
      ], []),
      BleCharacteristic(SpeakerProtocol.status, [
        CharacteristicProperty.notify,
      ], []),
      BleCharacteristic(SpeakerProtocol.meterCharacteristic, [
        CharacteristicProperty.notify,
      ], []),
    ]),
  ];
  final writes = <List<int>>[];
  int mtu = 247, connections = 0, disconnectCalls = 0;
  final scanConfigs = <PlatformConfig?>[];
  int scanStops = 0;
  Completer<void>? firstConnectGate;
  bool respondToCommands = false;
  BleConnectionState connectionState = BleConnectionState.disconnected;
  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      availability;
  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    scanConfigs.add(platformConfig);
  }

  @override
  Future<void> stopScan() async {
    scanStops++;
  }

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    connections++;
    if (connections == 1) await firstConnectGate?.future;
    connectionState = BleConnectionState.connected;
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectCalls++;
    connectionState = BleConnectionState.disconnected;
    updateConnection(deviceId, false);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      connectionState;
  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async => services;
  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => mtu;
  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {}
  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    if (connectionState != BleConnectionState.connected) {
      throw Exception('native link is disconnected');
    }
    writes.add(value.toList());
    if (respondToCommands) {
      updateCharacteristicValue(
        deviceId,
        SpeakerProtocol.status,
        Uint8List.fromList(
          value.first == 0xf0 ? fullStatus : [0x10, value.first],
        ),
        null,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NativeVerifiedAudio implements AudioConnectionAdapter {
  @override
  Future<AudioConnectionSnapshot> snapshot() async =>
      const AudioConnectionSnapshot(
        devices: [
          AudioDeviceIdentity(id: 'aa:bb:cc:dd:ee:01', name: 'BDK SPEAKER'),
        ],
      );
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openBluetoothSettings() async {}
}

void main() {
  late FakeTransport transport;
  late SpeakerSession session;
  late FakeLink link;
  setUp(() {
    transport = FakeTransport();
    link = FakeLink('speaker-a');
    transport.links.add(link);
    session = SpeakerSession(
      transport,
      operationTimeout: const Duration(milliseconds: 60),
      syncTimeout: const Duration(milliseconds: 30),
      ackTimeout: const Duration(milliseconds: 30),
    );
  });
  tearDown(() async {
    session.dispose();
    await transport.close();
  });
  Future<void> ready() async {
    link.onWrite = (p) {
      if (p[0] == 0xf0) link.status(fullStatus);
    };
    await session.connect(link.deviceId);
  }

  test(
    'sync subscribes first, requests status only, and requires full packet',
    () async {
      final connected = session.connect(link.deviceId);
      await Future<void>.delayed(Duration.zero);
      expect(session.state.value.phase, ConnectionPhase.synchronizing);
      expect(link.operations, [
        'subscribe:${SpeakerProtocol.status}',
        'subscribe:${SpeakerProtocol.meterCharacteristic}',
        'write:240',
      ]);
      link.status([1, 1, 2, 3]);
      expect(session.state.value.connected, isFalse);
      link.status(fullStatus);
      await connected;
      expect(session.state.value.connected, isTrue);
      expect(session.state.value.eq.values, [0, -1, 2]);
      expect(session.state.value.writeCapacity, 244);
      expect(link.writes, [
        [0xf0],
      ]);
      expect(session.state.value.meter, isNull);
    },
  );

  test(
    'full status with persisted Off completes synchronization without a setter',
    () async {
      final off = List<int>.of(fullStatus)..[5] = 255;
      link.onWrite = (packet) {
        if (packet[0] == 0xf0) link.status(off);
      };
      await session.connect(link.deviceId);
      expect(session.state.value.connected, isTrue);
      expect(session.state.value.led.effect, 255);
      expect(session.state.value.led.brightness, 70);
      expect(link.writes, [
        [0xf0],
      ]);
    },
  );

  test('truncated full status and timeout never become ready', () async {
    link.onWrite = (_) => link.status(fullStatus.sublist(0, 20));
    await expectLater(
      session.connect(link.deviceId),
      throwsA(isA<Exception>()),
    );
    expect(session.state.value.phase, ConnectionPhase.error);
    expect(session.state.value.message, contains('status'));
    expect(link.operations, contains('disconnect'));
  });

  test('small MTU refuses unsafe unframed sync without writing', () async {
    final small = FakeLink('small', writeCapacity: 20);
    transport.links.add(small);
    await expectLater(session.connect('small'), throwsA(isA<Exception>()));
    expect(session.state.value.connected, isFalse);
    expect(session.state.value.message, contains('capacity'));
    expect(small.writes, isEmpty);
  });

  test(
    'ATT write alone does not apply EQ and ACK acceptance stays unverified',
    () async {
      await ready();
      final write = session.setEq(EqGains(6, 0, -2));
      await Future<void>.delayed(Duration.zero);
      expect(session.state.value.eq.values, [0, -1, 2]);
      link.status([0x10, 1]);
      await write;
      expect(session.state.value.eq.values, [6, 0, -2]);
      expect(session.state.value.message, contains('accepted'));
      link.status(
        fullStatus,
      ); // Known firmware cache is stale after own writes.
      expect(session.state.value.eq.values, [6, 0, -2]);
      expect(link.writes, [
        [0xf0],
        [1, 6, 0, 254],
      ]);
    },
  );

  test(
    'ACK error preserves last state and exposes command and raw error',
    () async {
      await ready();
      final write = session.setLed(const LedSettings(effect: 21));
      await Future<void>.delayed(Duration.zero);
      link.status([0x11, 5, 3]);
      await expectLater(write, throwsA(isA<Exception>()));
      expect(session.state.value.led.effect, 0);
      expect(session.state.value.message, contains('0x03'));
      expect(session.state.value.connected, isTrue);
    },
  );

  test(
    'ACK timeout invalidates link so late ACK cannot confirm a later write',
    () async {
      await ready();
      await expectLater(
        session.setEq(EqGains(3, 0, 0)),
        throwsA(isA<Exception>()),
      );
      expect(session.state.value.phase, ConnectionPhase.error);
      expect(session.state.value.eq.values, [0, -1, 2]);
      expect(session.state.value.message, contains('confirm'));
      link.status([0x10, 1]);
      await expectLater(
        session.setEq(EqGains(4, 0, 0)),
        throwsA(isA<Exception>()),
      );
      expect(link.writes.length, 2);
    },
  );

  test(
    'slider queue sends first and final values while serializing ACKs',
    () async {
      await ready();
      final first = session.setEq(EqGains(1, 0, 0));
      await Future<void>.delayed(Duration.zero);
      final middle = session.setEq(EqGains(2, 0, 0));
      final last = session.setEq(EqGains(3, 0, 0));
      await Future<void>.delayed(Duration.zero);
      expect(link.writes, [
        [0xf0],
        [1, 1, 0, 0],
      ]);
      link.status([0x10, 1]);
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(link.writes, [
        [0xf0],
        [1, 1, 0, 0],
        [1, 3, 0, 0],
      ]);
      link.status([0x10, 1]);
      await Future.wait([middle, last]);
      expect(session.state.value.eq.bass, 3);
    },
  );

  test(
    'native write failure retains confirmed state and native error',
    () async {
      await ready();
      link.writeError = Exception('GATT 133 permission denied');
      await expectLater(
        session.setEq(EqGains(6, 0, 0)),
        throwsA(isA<Exception>()),
      );
      expect(session.state.value.eq.values, [0, -1, 2]);
      expect(session.state.value.phase, ConnectionPhase.error);
      expect(session.state.value.message, contains('GATT 133'));
    },
  );

  test(
    'old link notifications and disconnect cannot affect replacement',
    () async {
      await ready();
      final second = FakeLink('speaker-b');
      transport.links.add(second);
      second.onWrite = (_) => second.status(fullStatus);
      await session.connect(second.deviceId);
      link.status([1, 12, 12, 12]);
      link.meter([100, 100, 100]);
      link.disconnectController.add(
        const BleDisconnect(reason: 'old link lost'),
      );
      expect(session.state.value.deviceId, 'speaker-b');
      expect(session.state.value.connected, isTrue);
      expect(session.state.value.eq.values, [0, -1, 2]);
      expect(session.state.value.meter, isNull);
    },
  );

  test(
    'disconnect cancels current and queued commands and clears meters',
    () async {
      await ready();
      link.meter([0, 50, 100]);
      expect(session.state.value.meter!.db, [-60, -30, 0]);
      final first = session.setEq(EqGains(1, 0, 0));
      final queued = session.setLed(const LedSettings(effect: 21));
      final firstFailure = expectLater(first, throwsA(isA<Exception>()));
      final queuedFailure = expectLater(queued, throwsA(isA<Exception>()));
      await session.disconnect();
      await Future.wait([firstFailure, queuedFailure]);
      expect(session.state.value.phase, ConnectionPhase.disconnected);
      expect(session.state.value.meter, isNull);
      expect(link.writes.where((p) => p.first == 5), isEmpty);
    },
  );

  test('control setters preserve unknown firmware bits', () async {
    await ready();
    final write = session.setControl(1);
    await Future<void>.delayed(Duration.zero);
    expect(link.writes.last, [3, 0x81]);
    link.status([0x10, 3]);
    await write;
    expect(session.state.value.controlFlags, 0x81);
  });

  test(
    'discovery filters candidates, deduplicates, and never auto connects',
    () async {
      await session.scan();
      transport.scanController.add(
        const DiscoveredSpeaker(id: 'unrelated', name: 'Earbuds'),
      );
      transport.scanController.add(
        const DiscoveredSpeaker(id: 'name', name: 'BDK SPEAKER BLE'),
      );
      transport.scanController.add(
        const DiscoveredSpeaker(
          id: 'service',
          name: 'Kitchen',
          services: [SpeakerProtocol.service],
        ),
      );
      transport.scanController.add(
        const DiscoveredSpeaker(id: 'name', name: 'BDK SPEAKER BLE', rssi: -40),
      );
      expect(session.devices.value.map((d) => d.id), ['name', 'service']);
      expect(session.devices.value.first.rssi, -40);
      expect(link.operations, isEmpty);
      await session.stopScan();
      expect(session.state.value.phase, ConnectionPhase.disconnected);
    },
  );

  test(
    'a stopped scan cannot overwrite subsequent state with a late error',
    () async {
      transport.scanGate = Completer<void>();
      final scanning = session.scan();
      final failure = expectLater(scanning, throwsA(isA<Exception>()));
      await session.stopScan();
      transport.scanGate!.completeError(Exception('late native scan failure'));
      await failure;
      expect(session.state.value.phase, ConnectionPhase.disconnected);
    },
  );

  test(
    'late native scan start after timeout is stopped without reviving UI',
    () async {
      transport.scanGate = Completer<void>();
      await expectLater(session.scan(), throwsA(isA<Exception>()));
      expect(session.state.value.phase, ConnectionPhase.error);
      transport.scanGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(session.state.value.phase, ConnectionPhase.error);
      expect(transport.scanStops, greaterThan(0));
    },
  );

  test(
    'full status before both subscriptions and F0 cannot satisfy sync',
    () async {
      final subscribed = Completer<void>();
      link.onSubscribe = (characteristic) async {
        if (characteristic == SpeakerProtocol.meterCharacteristic) {
          link.status(fullStatus);
          await subscribed.future;
        }
      };
      final connecting = session.connect(link.deviceId);
      await Future<void>.delayed(Duration.zero);
      expect(session.state.value.connected, isFalse);
      subscribed.complete();
      await Future<void>.delayed(Duration.zero);
      link.status(fullStatus);
      await connecting;
      expect(session.state.value.connected, isTrue);
    },
  );

  test(
    'disconnect during sync reports link loss without a null-completer crash',
    () async {
      link.onWrite = (_) => link.disconnectController.add(
        const BleDisconnect(reason: 'supervision timeout', nativeCode: 8),
      );
      await expectLater(
        session.connect(link.deviceId),
        throwsA(predicate((e) => e is Exception)),
      );
      expect(session.state.value.phase, ConnectionPhase.error);
      expect(session.state.value.message, contains('supervision timeout'));
      expect(session.state.value.message, contains('native 8'));
    },
  );

  test('same acknowledged LED settings do not reset firmware effect', () async {
    await ready();
    const ambient = LedSettings(effect: 21);
    final first = session.setLed(ambient);
    await Future<void>.delayed(Duration.zero);
    link.status([0x10, 5]);
    await first;
    await session.setLed(ambient);
    expect(link.writes.where((p) => p.first == 5).length, 1);
  });

  test(
    'queued control change preserves latest unknown bits at execution',
    () async {
      await ready();
      final first = session.setEq(EqGains(1, 0, 0));
      final control = session.setControl(1);
      link.status([2, 0xc4]);
      link.status([0x10, 1]);
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(link.writes.last, [3, 0xc1]);
      link.status([0x10, 3]);
      await control;
    },
  );

  test(
    'lease excludes setters and raw write waits only for ATT completion',
    () async {
      await ready();
      final release = Completer<void>();
      final sent = Completer<void>();
      final responseEvents = <int>[];
      final subscription = session.responses.listen(
        (event) => responseEvents.add(event.id),
      );
      final transfer = session.withExclusiveWriter((writer) async {
        await writer.write(Uint8List.fromList([0x12, 0, 44, 0, 0]));
        sent.complete();
        await release.future;
        return 7;
      });
      await sent.future;
      await expectLater(
        session.setEq(EqGains(1, 0, 0)),
        throwsA(
          predicate(
            (e) =>
                e is SpeakerSessionException &&
                e.toString().contains('transfer'),
          ),
        ),
      );
      link.status([0x31]);
      expect(responseEvents, contains(0x31));
      expect(link.writes.last, [0x12, 0, 44, 0, 0]);
      release.complete();
      expect(await transfer, 7);
      await subscription.cancel();
    },
  );

  test(
    'lease releases after action error and ordinary setters can proceed',
    () async {
      await ready();
      await expectLater(
        session.withExclusiveWriter<void>((writer) async {
          throw Exception('bad local WAV');
        }),
        throwsA(isA<Exception>()),
      );
      final eq = session.setEq(EqGains(1, 0, 0));
      await Future<void>.delayed(Duration.zero);
      link.status([0x10, 1]);
      await eq;
      expect(session.state.value.eq.bass, 1);
    },
  );

  test(
    'disconnect aborts waiting lease and invalidates an escaped writer',
    () async {
      await ready();
      final waiting = Completer<void>();
      SessionWriter? escaped;
      final transfer = session.withExclusiveWriter((writer) async {
        escaped = writer;
        await waiting.future;
      });
      final failure = expectLater(
        transfer.timeout(const Duration(milliseconds: 100)),
        throwsA(isA<SpeakerSessionException>()),
      );
      await session.disconnect();
      await failure;
      await expectLater(
        escaped!.write(Uint8List.fromList([0x13, 0, 1, 2])),
        throwsA(isA<Exception>()),
      );
      expect(link.writes, [
        [0xf0],
      ]);
      waiting.complete();
    },
  );

  test(
    'explicit disconnect reports native failure instead of claiming it succeeded',
    () async {
      await ready();
      link.disconnectError = Exception('native adapter remains connected');
      await session.disconnect();
      expect(session.state.value.connected, isFalse);
      expect(
        session.state.value.message,
        contains('native adapter remains connected'),
      );
    },
  );

  test(
    'one writer rejects overlapping raw packets and never retries',
    () async {
      await ready();
      link.writeGate = Completer<void>();
      final transfer = session.withExclusiveWriter((writer) async {
        final first = writer.write(Uint8List.fromList([0x13, 0, 1, 2]));
        await expectLater(
          writer.write(Uint8List.fromList([0x13, 1, 3, 4])),
          throwsA(isA<SpeakerSessionException>()),
        );
        expect(link.writes, [
          [0xf0],
          [0x13, 0, 1, 2],
        ]);
        link.writeGate!.complete();
        await first;
      });
      await transfer;
    },
  );

  group('native adapter contract', () {
    late NativePlatform native;
    late UniversalBleTransport adapter;
    setUp(() {
      native = NativePlatform();
      UniversalBle.setInstance(native);
      adapter = UniversalBleTransport(
        timeout: const Duration(milliseconds: 100),
      );
    });
    tearDown(() {
      adapter.dispose();
    });

    test(
      'foreground discovery requests low latency without report batching',
      () async {
        await adapter.startScan();
        expect(native.scanConfigs, hasLength(1));
        final android = native.scanConfigs.single?.android;
        expect(
          android?.scanMode,
          AndroidScanMode.lowLatency,
          reason:
              'foreground connection setup needs an active discovery duty cycle',
        );
        expect(
          android?.reportDelayMillis,
          0,
          reason: 'a discovered candidate should reach setup without batching',
        );
        await adapter.stopScan();
        expect(native.scanStops, 1);
      },
    );

    test(
      'leaving foreground setup stops native discovery without restarting',
      () async {
        final realSession = SpeakerSession(adapter);
        final setup = SpeakerSetupController(
          realSession,
          _NativeVerifiedAudio(),
          autoDiscoverEnabled: true,
          pollInterval: Duration.zero,
        );
        try {
          setup.setActive(true);
          await Future<void>.delayed(Duration.zero);
          expect(native.scanConfigs, hasLength(1));
          expect(realSession.state.value.phase, ConnectionPhase.scanning);
          setup.setActive(false);
          await Future<void>.delayed(Duration.zero);
          expect(native.scanStops, 1);
          expect(realSession.state.value.phase, ConnectionPhase.disconnected);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(native.scanConfigs, hasLength(1));
          expect(native.connections, 0);
        } finally {
          setup.dispose();
          realSession.dispose();
        }
      },
    );

    test(
      'late old same-device connection cannot disconnect its replacement',
      () async {
        const id = 'aa:bb:cc:dd:ee:01';
        native.firstConnectGate = Completer<void>();
        final first = adapter.connect(id);
        await Future<void>.delayed(Duration.zero);
        final second = adapter.connect(id);
        await Future<void>.delayed(Duration.zero);
        final simultaneousNativeAttempts = native.connections;
        native.firstConnectGate!.complete();
        final stale = await first;
        final replacement = await second;
        try {
          await stale.disconnect(); // Cleanup from the superseded session.
          stale.dispose();
          await replacement.write(Uint8List.fromList([0xf0]));
          expect(simultaneousNativeAttempts, 1);
          expect(native.connectionState, BleConnectionState.connected);
          expect(native.writes, [
            [0xf0],
          ]);
        } finally {
          await replacement.disconnect();
          replacement.dispose();
        }
      },
    );

    test(
      'two rapid session connects to same ID leave replacement usable',
      () async {
        const id = 'aa:bb:cc:dd:ee:01';
        native.firstConnectGate = Completer<void>();
        native.respondToCommands = true;
        final realSession = SpeakerSession(
          adapter,
          operationTimeout: const Duration(milliseconds: 500),
          syncTimeout: const Duration(milliseconds: 200),
          ackTimeout: const Duration(milliseconds: 200),
        );
        try {
          final first = realSession.connect(id);
          final obsolete = expectLater(
            first,
            throwsA(isA<SpeakerSessionException>()),
          );
          await Future<void>.delayed(Duration.zero);
          final replacement = realSession.connect(id);
          await Future<void>.delayed(Duration.zero);
          native.firstConnectGate!.complete();
          await obsolete;
          await replacement;
          await Future<void>.delayed(Duration.zero);
          expect(realSession.state.value.connected, isTrue);
          await realSession.setEq(EqGains(6, 0, -2));
          expect(realSession.state.value.eq.values, [6, 0, -2]);
          expect(native.connectionState, BleConnectionState.connected);
        } finally {
          realSession.dispose();
        }
      },
    );

    test('Bluetooth off blocks discovery with an actionable error', () async {
      native.availability = AvailabilityState.poweredOff;
      await expectLater(
        adapter.startScan(),
        throwsA(predicate((e) => e.toString().contains('Bluetooth'))),
      );
      expect(native.connections, 0);
    });

    test(
      'verifies service before exposing a link and closes incompatible devices',
      () async {
        native.services = [];
        await expectLater(
          adapter.connect('aa:bb:cc:dd:ee:01'),
          throwsA(isA<Exception>()),
        );
        expect(native.connections, 1);
        expect(native.disconnectCalls, 1);
      },
    );

    test(
      'reports negotiated capacity and writes commands through the native API',
      () async {
        final connected = await adapter.connect('aa:bb:cc:dd:ee:01');
        expect(connected.writeCapacity, 244);
        await connected.subscribe(SpeakerProtocol.status);
        await connected.write(Uint8List.fromList([0xf0]));
        expect(native.writes, [
          [0xf0],
        ]);
        await connected.disconnect();
        connected.dispose();
      },
    );
  });
}
