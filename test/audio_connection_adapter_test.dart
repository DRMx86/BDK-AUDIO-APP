import 'dart:async';
import 'package:bdk_audio/platform/audio_connection_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowsChannel = MethodChannel('bdk_audio/audio_connection');
  const adapter = SystemAudioConnectionAdapter();
  var windowsCalls = 0, androidCalls = 0;
  Map<String, Object?> response = {};
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    windowsCalls = 0;
    androidCalls = 0;
    response = {
      'protocolVersion': 1,
      'state': 'ready',
      'canVerifyIdentity': true,
      'devices': <Object>[],
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowsChannel, (call) async {
          windowsCalls++;
          expect(call.method, 'snapshot');
          return response;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemAudioConnectionAdapter.channel, (
          call,
        ) async {
          androidCalls++;
          return {
            'state': 'ready',
            'devices': [
              {'id': 'A1:B2:C3:D4:E5:F6', 'name': 'BDK Android test'},
            ],
          };
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemAudioConnectionAdapter.channel, null);
  });
  test(
    'Windows uses native verified route snapshot and canonical BLE-compatible identity',
    () async {
      response['devices'] = [
        {'id': 'A1B2C3D4E5F6', 'name': 'BDK synthetic route'},
      ];
      final snapshot = await adapter.snapshot();
      expect(windowsCalls, 1);
      expect(androidCalls, 0);
      expect(snapshot.canVerifyIdentity, isTrue);
      expect(snapshot.devices.single.id, 'a1:b2:c3:d4:e5:f6');
      expect(snapshot.devices.single.name, 'BDK synthetic route');
      expect(() => snapshot.devices.clear(), throwsUnsupportedError);
    },
  );
  test(
    'verified empty Windows snapshot cannot enable manual audio confirmation',
    () async {
      final snapshot = await adapter.snapshot();
      expect(snapshot.canVerifyIdentity, isTrue);
      expect(snapshot.devices, isEmpty);
      expect(snapshot.permissionRequired, isFalse);
      expect(windowsCalls, 1);
    },
  );
  test(
    'unsupported driver is explicit and still enforces native identity gate',
    () async {
      response = {
        'protocolVersion': 1,
        'state': 'unsupported',
        'canVerifyIdentity': false,
        'devices': <Object>[],
        'message':
            'This Windows driver does not expose a verified Bluetooth audio identity.',
      };
      final snapshot = await adapter.snapshot();
      expect(snapshot.canVerifyIdentity, isTrue);
      expect(snapshot.devices, isEmpty);
      expect(snapshot.message, contains('does not expose'));
      expect(snapshot.permissionRequired, isFalse);
    },
  );
  test(
    'native incomplete enumeration fails closed instead of manual fallback',
    () async {
      response = {
        'protocolVersion': 1,
        'state': 'unavailable',
        'canVerifyIdentity': false,
        'devices': <Object>[],
      };
      await expectLater(
        adapter.snapshot(),
        throwsA(isA<AudioConnectionException>()),
      );
    },
  );
  test(
    'malformed identities unknown schema and inconsistent ready flags cannot authorize BLE',
    () async {
      for (final change in [
        {'protocolVersion': 2},
        {'canVerifyIdentity': false},
        {'devices': 'not a list'},
        {
          'devices': [
            {'id': 'an endpoint GUID', 'name': 'BDK synthetic route'},
          ],
        },
        {
          'devices': [
            {'id': '000000000000', 'name': 'BDK synthetic route'},
          ],
        },
        {
          'devices': [
            {'id': 'ffffffffffff', 'name': 'BDK synthetic route'},
          ],
        },
        {
          'devices': [
            {'id': 'a1:b2-c3:d4:e5:f6', 'name': 'BDK synthetic route'},
          ],
        },
        {
          'devices': [
            {'id': 'a1:b2:c3:d4:e5:f6', 'name': false},
          ],
        },
      ]) {
        response = {
          'protocolVersion': 1,
          'state': 'ready',
          'canVerifyIdentity': true,
          'devices': <Object>[],
          ...change,
        };
        await expectLater(
          adapter.snapshot(),
          throwsA(isA<AudioConnectionException>()),
        );
      }
    },
  );
  test(
    'missing Windows plugin never reverts to silent manual bypass',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowsChannel, null);
      await expectLater(
        adapter.snapshot(),
        throwsA(isA<AudioConnectionException>()),
      );
    },
  );
  test(
    'bounded Windows channel timeout fails closed and ignores its late result',
    () async {
      final delayed = Completer<Map<String, Object?>>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowsChannel, (call) => delayed.future);
      const bounded = SystemAudioConnectionAdapter(
        windowsTimeout: Duration(milliseconds: 10),
      );
      await expectLater(
        bounded.snapshot(),
        throwsA(isA<AudioConnectionException>()),
      );
      delayed.complete({
        'protocolVersion': 1,
        'state': 'ready',
        'canVerifyIdentity': true,
        'devices': [
          {'id': 'a1:b2:c3:d4:e5:f6', 'name': 'Old synthetic route'},
        ],
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowsChannel, (call) async => response);
      final fresh = await bounded.snapshot();
      expect(fresh.devices, isEmpty);
      expect(fresh.canVerifyIdentity, isTrue);
    },
  );
  test(
    'Android keeps existing codec-channel connection and permission behavior',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final snapshot = await adapter.snapshot();
      expect(androidCalls, 1);
      expect(windowsCalls, 0);
      expect(snapshot.devices.single.id, 'A1:B2:C3:D4:E5:F6');
      expect(snapshot.canVerifyIdentity, isTrue);
      await adapter.requestPermission();
      expect(androidCalls, 2);
      expect(windowsCalls, 0);
    },
  );
  test(
    'Windows permission check never invokes Android or mutates native OS state',
    () async {
      await adapter.requestPermission();
      expect(androidCalls, 0);
      expect(windowsCalls, 0);
    },
  );
  test(
    'other unsupported platforms preserve explicit OS-managed confirmation contract',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final snapshot = await adapter.snapshot();
      expect(snapshot.canVerifyIdentity, isFalse);
      expect(windowsCalls, 0);
      expect(androidCalls, 0);
    },
  );
}
