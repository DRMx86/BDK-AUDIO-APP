import 'dart:async';
import 'dart:typed_data';
import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';

Uint8List soundWav({int dataBytes = 100, int sampleRate = 22050}) {
  final bytes = Uint8List(44 + dataBytes);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, [82, 73, 70, 70]);
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, [87, 65, 86, 69, 102, 109, 116, 32]);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, [100, 97, 116, 97]);
  data.setUint32(40, dataBytes, Endian.little);
  for (var i = 44; i < bytes.length; i++) {
    bytes[i] = i & 255;
  }
  return bytes;
}

class SoundFakeLink implements BleLink {
  SoundFakeLink({
    this.deviceId = 'AA',
    this.writeCapacity = 244,
    this.soundFlags = 15,
  });
  @override
  final String deviceId;
  @override
  final int writeCapacity;
  final notificationsController = StreamController<BleNotification>.broadcast(
    sync: true,
  );
  final disconnectController = StreamController<BleDisconnect>.broadcast(
    sync: true,
  );
  final writes = <List<int>>[];
  final withResponses = <bool>[];
  final operations = <String>[];
  Future<void> Function(Uint8List)? onWrite;
  int soundFlags, disconnectCalls = 0, activeWrites = 0, maxActiveWrites = 0;
  bool autoStatus = true;
  @override
  Stream<BleNotification> get notifications => notificationsController.stream;
  @override
  Stream<BleDisconnect> get disconnects => disconnectController.stream;
  @override
  Future<void> subscribe(String characteristic) async {
    operations.add('subscribe:$characteristic');
  }

  void status(List<int> bytes) => notificationsController.add(
    BleNotification(SpeakerProtocol.status, bytes),
  );
  void fullStatus() => status([
    0xf0,
    0,
    0,
    0,
    4,
    0,
    70,
    50,
    0,
    128,
    255,
    128,
    0,
    255,
    1,
    soundFlags,
    0,
    0,
  ]);
  @override
  Future<void> write(Uint8List bytes, {bool withResponse = true}) async {
    writes.add(List.of(bytes));
    withResponses.add(withResponse);
    operations.add('write:${bytes.first}');
    activeWrites++;
    if (activeWrites > maxActiveWrites) maxActiveWrites = activeWrites;
    try {
      if (bytes.first == 0xf0 && autoStatus) fullStatus();
      await onWrite?.call(bytes);
    } finally {
      activeWrites--;
    }
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    operations.add('disconnect');
  }

  // Keep streams alive so a test can deliver stale native events after disposal.
  @override
  void dispose() {}
  Future<void> close() async {
    await notificationsController.close();
    await disconnectController.close();
  }
}

class SoundFakeTransport implements BleTransport {
  final scans = StreamController<DiscoveredSpeaker>.broadcast(sync: true);
  SoundFakeLink link = SoundFakeLink();
  @override
  Stream<DiscoveredSpeaker> get scanResults => scans.stream;
  @override
  Future<void> startScan() async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<BleLink> connect(String id) async => link;
  @override
  void dispose() {}
}

class SoundTestRig {
  SoundTestRig({int capacity = 244}) {
    transport.link = SoundFakeLink(writeCapacity: capacity);
    links.add(transport.link);
    session = SpeakerSession(
      transport,
      operationTimeout: const Duration(milliseconds: 250),
      syncTimeout: const Duration(milliseconds: 100),
      ackTimeout: const Duration(milliseconds: 100),
    );
  }
  final transport = SoundFakeTransport();
  final links = <SoundFakeLink>[];
  late final SpeakerSession session;
  SoundFakeLink get link => transport.link;
  Future<void> connect() async {
    await session.connect('AA');
    link.writes.clear();
    link.withResponses.clear();
  }

  Future<SoundFakeLink> reconnect() async {
    transport.link = SoundFakeLink();
    links.add(link);
    await connect();
    return link;
  }

  void respondUpload() {
    link.onWrite = (bytes) async {
      if (bytes.first == 0x12 || bytes.first == 0x13) link.status([0x31]);
      if (bytes.first == 0x14) link.status([0x32]);
    };
  }

  Future<void> close() async {
    await session.disconnect();
    session.dispose();
    await transport.scans.close();
    for (final link in links) {
      await link.close();
    }
  }
}
