import 'dart:async';
import 'package:bdk_audio/features/codec/audio_config_summary_controller.dart';
import 'package:bdk_audio/features/codec/codec_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'codec_test_support.dart';

CodecSnapshot summaryFixture({
  String id = 'AA',
  int stamp = 100000,
  int quality = 1000,
}) => CodecSnapshot(
  access: CodecAccess.ready,
  devices: [CodecAudioDevice(id: id, name: 'BDK SPEAKER')],
  selectedDeviceId: id,
  active: CodecConfiguration(
    codecType: 4,
    codecName: 'LDAC',
    sampleRateMask: 8,
    bitsMask: 4,
    channelMask: 2,
    cs1: quality,
  ),
  source: 'direct',
  observedAtMs: stamp,
);

void main() {
  testWidgets(
    'inconsistent LHDC lossless fixed fields do not advertise a nominal target',
    (tester) async {
      final adapter = FakeCodecAdapter()
        ..onSnapshot = (_) async => lhdcV5Fixture(cs1: 0x8008, cs3: 0x5c000080);
      final controller = AudioConfigSummaryController(
        adapter: adapter,
        now: () => DateTime.fromMillisecondsSinceEpoch(100000),
      );
      addTearDown(controller.dispose);
      controller.configure(deviceId: 'AA', active: true);
      await tester.pump();
      expect(controller.text, 'LHDC V5 · 192 kHz · 24-bit');
      expect(controller.text, isNot(contains('1000')));
      controller.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'audio summary shows the probed LHDC nominal target without calling it actual bitrate',
    (tester) async {
      final adapter = FakeCodecAdapter()
        ..onSnapshot = (_) async => lhdcV5Fixture();
      final controller = AudioConfigSummaryController(
        adapter: adapter,
        now: () => DateTime.fromMillisecondsSinceEpoch(100000),
      );
      addTearDown(controller.dispose);
      controller.configure(deviceId: 'AA', active: true);
      await tester.pump();
      expect(controller.text, 'LHDC V5 · 192 kHz · 24-bit · 1000 kbps');
      expect(controller.hasFreshObservation, isTrue);
      expect(adapter.writes, isEmpty);
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'audio summary uses current identity and explicit nominal target',
    (tester) async {
      final adapter = FakeCodecAdapter()
        ..onSnapshot = (_) async => summaryFixture();
      final controller = AudioConfigSummaryController(
        adapter: adapter,
        now: () => DateTime.fromMillisecondsSinceEpoch(100000),
      );
      addTearDown(controller.dispose);
      controller.configure(deviceId: 'AA', active: true);
      await tester.pump();

      expect(controller.text, 'LDAC · 96 kHz · 32-bit · 990 kbps');
      expect(controller.hasFreshObservation, isTrue);
      expect(adapter.events, ['snapshot:AA']);
      expect(adapter.writes, isEmpty);
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets('audio summary never invents bitrate for adaptive quality', (
    tester,
  ) async {
    final adapter = FakeCodecAdapter()
      ..onSnapshot = (_) async => summaryFixture(quality: 1003);
    final controller = AudioConfigSummaryController(
      adapter: adapter,
      now: () => DateTime.fromMillisecondsSinceEpoch(100000),
    );
    addTearDown(controller.dispose);
    controller.configure(deviceId: 'AA', active: true);
    await tester.pump();

    expect(controller.text, 'LDAC · 96 kHz · 32-bit · Adaptive');
    expect(controller.text, isNot(contains('kbps')));
    expect(adapter.writes, isEmpty);
    controller.dispose();
    await tester.pump();
  });

  testWidgets(
    'audio summary rejects a fresh snapshot for another audio device',
    (tester) async {
      final adapter = FakeCodecAdapter()
        ..onSnapshot = (_) async => summaryFixture(id: 'BB');
      final controller = AudioConfigSummaryController(
        adapter: adapter,
        now: () => DateTime.fromMillisecondsSinceEpoch(100000),
      );
      addTearDown(controller.dispose);
      controller.configure(deviceId: 'AA', active: true);
      await tester.pump();

      expect(controller.text, 'Audio quality');
      expect(controller.hasFreshObservation, isFalse);
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'audio summary expires observation instead of retaining live values',
    (tester) async {
      var clock = DateTime.fromMillisecondsSinceEpoch(100000);
      final adapter = FakeCodecAdapter()
        ..onSnapshot = (_) async => summaryFixture();
      final controller = AudioConfigSummaryController(
        adapter: adapter,
        now: () => clock,
      );
      addTearDown(controller.dispose);
      controller.configure(deviceId: 'AA', active: true);
      await tester.pump();
      expect(controller.hasFreshObservation, isTrue);

      clock = DateTime.fromMillisecondsSinceEpoch(105001);
      await tester.pump(const Duration(milliseconds: 5001));
      await tester.pump();

      expect(controller.hasFreshObservation, isFalse);
      expect(controller.text, contains('stale'));
      expect(controller.text, isNot(contains('96 kHz')));
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'audio summary configuration is idempotent and pauses in background',
    (tester) async {
      var clock = DateTime.fromMillisecondsSinceEpoch(100000);
      final adapter = FakeCodecAdapter()
        ..onSnapshot = (_) async =>
            summaryFixture(stamp: clock.millisecondsSinceEpoch);
      final controller = AudioConfigSummaryController(
        adapter: adapter,
        now: () => clock,
      );
      addTearDown(controller.dispose);
      controller.configure(deviceId: 'AA', active: true);
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        controller.configure(deviceId: 'AA', active: true);
      }
      await tester.pump();
      expect(adapter.events, ['snapshot:AA']);

      clock = clock.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(adapter.events, ['snapshot:AA', 'snapshot:AA']);

      controller.configure(deviceId: 'AA', active: false);
      clock = clock.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(adapter.events, ['snapshot:AA', 'snapshot:AA']);
      expect(controller.hasFreshObservation, isFalse);
      expect(controller.text, 'Audio quality');
      controller.configure(deviceId: null, active: true);
      await tester.pump();
      expect(adapter.events, ['snapshot:AA', 'snapshot:AA']);
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'audio summary timeout retains native lease and rejects late old identity',
    (tester) async {
      final gate = Completer<CodecSnapshot>();
      final adapter = FakeCodecAdapter()
        ..onSnapshot = (id) async {
          if (id == 'AA') return await gate.future;
          return summaryFixture(id: 'BB');
        };
      final controller = AudioConfigSummaryController(
        adapter: adapter,
        requestTimeout: const Duration(seconds: 1),
        now: () => DateTime.fromMillisecondsSinceEpoch(100000),
      );
      addTearDown(controller.dispose);
      controller.configure(deviceId: 'AA', active: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      controller.configure(deviceId: 'BB', active: true);
      await tester.pump(const Duration(seconds: 10));
      expect(adapter.events, ['snapshot:AA']);
      expect(adapter.maxActiveCalls, 1);
      expect(controller.hasFreshObservation, isFalse);

      gate.complete(summaryFixture());
      await tester.pump();
      await tester.pump();
      expect(adapter.events, ['snapshot:AA', 'snapshot:BB']);
      expect(adapter.maxActiveCalls, 1);
      expect(controller.snapshot?.selectedDeviceId, 'BB');
      expect(controller.hasFreshObservation, isTrue);
      expect(adapter.writes, isEmpty);
      controller.dispose();
      await tester.pump();
    },
  );
}
