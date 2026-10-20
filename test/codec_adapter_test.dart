import 'package:bdk_audio/features/codec/codec_adapter.dart';
import 'package:bdk_audio/features/codec/codec_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> nativeSnapshot() => {
  'state': 'ready',
  'devices': [
    {'id': 'AA', 'name': 'BDK SPEAKER', 'associated': true},
  ],
  'selectedDeviceId': 'AA',
  'canApply': true,
  'source': 'direct',
  'observedAtMs': 10000,
  'active': {
    'codecType': 4,
    'codecName': 'LDAC',
    'sampleRateMask': 8,
    'bitsMask': 2,
    'channelMask': 2,
    'cs1': 1003,
    'cs2': -7,
    'cs3': 0,
    'cs4': 0,
  },
  'capabilities': [
    {
      'codecType': 4,
      'codecName': 'LDAC',
      'sampleRateMask': 10,
      'bitsMask': 3,
      'channelMask': 2,
      'cs1': 0,
      'cs2': 0,
      'cs3': 0,
      'cs4': 0,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/bdk_codec');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'Android adapter reads only the selected audio identity through the existing bridge',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return nativeSnapshot();
      });
      final adapter = SystemCodecAdapter(
        platform: TargetPlatform.android,
        channel: channel,
      );
      final snapshot = await adapter.snapshot(deviceId: 'AA');
      expect(snapshot.active!.codecName, 'LDAC');
      expect(snapshot.active!.cs2, -7);
      expect(calls.single.method, 'snapshot');
      expect(calls.single.arguments, {'deviceId': 'AA'});
      adapter.dispose();
    },
  );

  test(
    'apply sends explicit masks and all preserved signed codec fields exactly once',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'submitted': true};
      });
      final adapter = SystemCodecAdapter(
        platform: TargetPlatform.android,
        channel: channel,
      );
      const config = CodecConfiguration(
        codecType: 4,
        codecName: 'LDAC',
        sampleRateMask: 8,
        bitsMask: 2,
        channelMask: 2,
        cs1: 1003,
        cs2: -7,
        cs3: 55,
        cs4: 66,
      );
      expect(
        await adapter.apply(deviceId: 'AA', configuration: config),
        isTrue,
      );
      expect(calls.single.method, 'apply');
      expect(calls.single.arguments, {
        'deviceId': 'AA',
        'codecType': 4,
        'sampleRateMask': 8,
        'bitsMask': 2,
        'channelMask': 2,
        'cs1': 1003,
        'cs2': -7,
        'cs3': 55,
        'cs4': 66,
      });
      adapter.dispose();
    },
  );

  test(
    'unsupported platforms never call Android methods or advertise available controls',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return nativeSnapshot();
      });
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        final adapter = SystemCodecAdapter(
          platform: platform,
          channel: channel,
        );
        final snapshot = await adapter.snapshot();
        expect(snapshot.access, CodecAccess.unsupportedPlatform);
        expect(snapshot.active, isNull);
        expect(snapshot.canApply, isFalse);
        expect(snapshot.capabilities, isEmpty);
        adapter.dispose();
      }
      expect(calls, isEmpty);
    },
  );

  test('malformed acknowledgment does not become submitted success', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'submitted': 'true'},
    );
    final adapter = SystemCodecAdapter(
      platform: TargetPlatform.android,
      channel: channel,
    );
    await expectLater(
      adapter.apply(
        deviceId: 'AA',
        configuration: const CodecConfiguration(
          codecType: 4,
          codecName: 'LDAC',
          sampleRateMask: 8,
          bitsMask: 2,
          channelMask: 2,
        ),
      ),
      throwsA(isA<CodecAdapterException>()),
    );
    adapter.dispose();
  });

  test(
    'native errors preserve their diagnostic code without claiming success',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'codecUnavailable',
          message: 'SecurityException: OEM restriction',
        ),
      );
      final adapter = SystemCodecAdapter(
        platform: TargetPlatform.android,
        channel: channel,
      );
      await expectLater(
        adapter.snapshot(deviceId: 'AA'),
        throwsA(
          isA<CodecAdapterException>()
              .having((error) => error.code, 'code', 'codecUnavailable')
              .having(
                (error) => error.details,
                'details',
                contains('SecurityException'),
              ),
        ),
      );
      adapter.dispose();
    },
  );

  test(
    'permission and association use their existing consent methods and explicit identity',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return nativeSnapshot();
      });
      final adapter = SystemCodecAdapter(
        platform: TargetPlatform.android,
        channel: channel,
      );
      await adapter.requestPermission();
      await adapter.associate('AA');
      await adapter.openBluetoothSettings();
      expect(calls.map((call) => call.method), [
        'requestPermission',
        'associate',
        'openBluetoothSettings',
      ]);
      expect(calls[1].arguments, {'deviceId': 'AA'});
      adapter.dispose();
    },
  );

  test(
    'disposed adapter refuses new requests without touching the bridge',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return nativeSnapshot();
      });
      final adapter = SystemCodecAdapter(
        platform: TargetPlatform.android,
        channel: channel,
      )..dispose();
      await expectLater(adapter.snapshot(), throwsStateError);
      expect(calls, 0);
    },
  );
}
