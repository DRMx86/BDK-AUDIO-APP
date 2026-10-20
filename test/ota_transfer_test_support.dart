import 'dart:convert';
import 'dart:async';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'sound_transfer_test_support.dart';

class OtaFakeLink extends SoundFakeLink {
  OtaFakeLink({super.deviceId, super.writeCapacity, this.version = '1.0.0'});
  String version;
  Completer<void>? closeGate;
  @override
  Future<void> disconnect() async {
    await super.disconnect();
    await closeGate?.future;
  }

  @override
  void fullStatus() {
    final text = utf8.encode(version);
    status([
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
      text.length,
      ...text,
    ]);
  }
}

class OtaTestRig {
  OtaTestRig({int capacity = 244}) {
    transport.link = OtaFakeLink(writeCapacity: capacity);
    links.add(link);
    session = SpeakerSession(
      transport,
      operationTimeout: const Duration(milliseconds: 250),
      syncTimeout: const Duration(milliseconds: 100),
    );
  }
  final transport = SoundFakeTransport();
  final links = <OtaFakeLink>[];
  late final SpeakerSession session;
  OtaFakeLink get link => transport.link as OtaFakeLink;
  Future<void> connect() async {
    await session.connect(link.deviceId);
    link.writes.clear();
    link.withResponses.clear();
  }

  Future<OtaFakeLink> reconnect({
    String id = 'AA',
    String version = '2.4.0',
  }) async {
    transport.link = OtaFakeLink(deviceId: id, version: version);
    links.add(link);
    await connect();
    return link;
  }

  void respondTransfer() {
    link.onWrite = (packet) async {
      if (packet.first == 0x20) link.status([0x21]);
      if (packet.first == 0x22) link.status([0x22]);
      if (packet.first == 0x23) link.status([0x10, 0x23]);
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
