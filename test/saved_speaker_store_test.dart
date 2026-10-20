import 'dart:async';
import 'dart:convert';

import 'package:bdk_audio/persistence/profile_store.dart';
import 'package:bdk_audio/persistence/saved_speaker_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The plugin's platform fake keeps the production preferences API under test.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late _PreferencesPlatform platform;
  late SharedPreferencesAsync preferences;
  late SharedPreferencesSavedSpeakerStore store;
  late SharedPreferencesAsyncPlatform? originalPlatform;

  setUp(() {
    originalPlatform = SharedPreferencesAsyncPlatform.instance;
    platform = _PreferencesPlatform();
    SharedPreferencesAsyncPlatform.instance = platform;
    preferences = SharedPreferencesAsync();
    store = SharedPreferencesSavedSpeakerStore(preferences);
  });
  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = originalPlatform;
  });

  test(
    'absent speaker loads as null without changing preset storage',
    () async {
      await preferences.setString(ProfileStore.key, 'presets remain here');
      expect(await store.load(), isNull);
      expect(
        await preferences.getString(ProfileStore.key),
        'presets remain here',
      );
      expect(
        await preferences.getString(SharedPreferencesSavedSpeakerStore.key),
        isNull,
      );
    },
  );

  test(
    'successful save survives a fresh store and encodes version one',
    () async {
      await preferences.setString(ProfileStore.key, 'presets remain here');
      await store.save(SavedSpeaker('AA:BB:CC:DD:EE:FF', 'Loa phòng khách'));
      final fresh = SharedPreferencesSavedSpeakerStore(preferences);
      final saved = await fresh.load();
      expect(saved?.id, 'AA:BB:CC:DD:EE:FF');
      expect(saved?.name, 'Loa phòng khách');
      expect(
        jsonDecode(
          (await preferences.getString(
            SharedPreferencesSavedSpeakerStore.key,
          ))!,
        ),
        {'version': 1, 'id': 'AA:BB:CC:DD:EE:FF', 'name': 'Loa phòng khách'},
      );
      expect(
        await preferences.getString(ProfileStore.key),
        'presets remain here',
      );
    },
  );

  test(
    'a valid saved speaker can be replaced after a later successful connection',
    () async {
      await preferences.setString(
        SharedPreferencesSavedSpeakerStore.key,
        '{"version":1,"id":"old","name":"Old speaker"}',
      );
      await store.save(SavedSpeaker('new', 'New speaker'));
      expect((await store.load())?.id, 'new');
    },
  );

  for (final raw in <String>[
    '',
    'not JSON',
    'null',
    '[]',
    '{}',
    '{"version":2,"id":"future","name":"Speaker"}',
    '{"version":0,"id":"old","name":"Speaker"}',
    '{"version":"1","id":"speaker","name":"Speaker"}',
    '{"version":1.0,"id":"speaker","name":"Speaker"}',
    '{"version":1,"id":7,"name":"Speaker"}',
    '{"version":1,"id":"speaker","name":null}',
    '{"version":1,"id":"","name":"Speaker"}',
    '{"version":1,"id":"speaker","name":" "}',
    '{"version":1,"id":" speaker","name":"Speaker"}',
    '{"version":1,"id":"speaker","name":"Speaker "}',
    '{"version":1,"id":"speaker\\u0000","name":"Speaker"}',
    '{"version":1,"id":"speaker","name":"Speaker\\u007f"}',
    jsonEncode({'version': 1, 'id': 'é' * 65, 'name': 'Speaker'}),
    jsonEncode({'version': 1, 'id': 'speaker', 'name': '😀' * 31}),
    jsonEncode({
      'version': 1,
      'id': 'speaker',
      'name': 'Speaker',
      'extra': 'é' * 2048,
    }),
  ]) {
    test(
      'unreadable record is rejected and survives refused save: ${raw.length} ${raw.substring(0, raw.length.clamp(0, 45))}',
      () async {
        await preferences.setString(
          SharedPreferencesSavedSpeakerStore.key,
          raw,
        );
        await expectLater(store.load(), throwsFormatException);
        await expectLater(
          store.save(SavedSpeaker('new', 'New')),
          throwsFormatException,
        );
        expect(
          await preferences.getString(SharedPreferencesSavedSpeakerStore.key),
          raw,
        );
      },
    );
  }

  test(
    'an exactly 4 KiB valid payload is accepted but one additional byte is refused',
    () async {
      const base = '{"version":1,"id":"speaker","name":"Speaker","extra":""}';
      final raw = base.replaceFirst(
        '"extra":""',
        '"extra":"${'x' * (4096 - base.length)}"',
      );
      await preferences.setString(SharedPreferencesSavedSpeakerStore.key, raw);
      expect((await store.load())?.id, 'speaker');
      await preferences.setString(
        SharedPreferencesSavedSpeakerStore.key,
        '$raw ',
      );
      await expectLater(store.load(), throwsFormatException);
    },
  );

  for (final speaker in <SavedSpeaker>[
    SavedSpeaker('', 'Speaker'),
    SavedSpeaker('id', ''),
    SavedSpeaker(' id', 'Speaker'),
    SavedSpeaker('id', 'Speaker '),
    SavedSpeaker('id\n', 'Speaker'),
    SavedSpeaker('id', 'A\tB'),
    SavedSpeaker('A\u0000B', 'Speaker'),
    SavedSpeaker('id', 'A\u007fB'),
    SavedSpeaker('é' * 65, 'Speaker'),
    SavedSpeaker('id', '😀' * 31),
  ]) {
    test(
      'invalid outgoing speaker never replaces a valid record: ${speaker.id.length}/${speaker.name.length}',
      () async {
        const previous = '{"version":1,"id":"old","name":"Old"}';
        await preferences.setString(
          SharedPreferencesSavedSpeakerStore.key,
          previous,
        );
        await expectLater(store.save(speaker), throwsFormatException);
        expect(
          await preferences.getString(SharedPreferencesSavedSpeakerStore.key),
          previous,
        );
      },
    );
  }

  test('UTF-8 field limits are inclusive', () async {
    await store.save(SavedSpeaker('é' * 64, '😀' * 30));
    final saved = await store.load();
    expect(saved?.id, 'é' * 64);
    expect(saved?.name, '😀' * 30);
  });

  test('overlapping writes and reads observe invocation order', () async {
    platform.pauseNextWrite = Completer<void>();
    final firstWrite = store.save(SavedSpeaker('first', 'First'));
    await platform.writeStarted.future;
    final between = store.load();
    final secondWrite = store.save(SavedSpeaker('second', 'Second'));
    final after = store.load();
    platform.pauseNextWrite!.complete();
    await firstWrite;
    expect((await between)?.id, 'first');
    await secondWrite;
    expect((await after)?.id, 'second');
  });

  test(
    'failed write is reported and does not poison later queued operations',
    () async {
      await store.save(SavedSpeaker('old', 'Old'));
      platform.failNextWrite = true;
      final failed = store.save(SavedSpeaker('failed', 'Failed'));
      final failure = expectLater(failed, throwsStateError);
      final afterFailure = store.load();
      final recovered = store.save(SavedSpeaker('recovered', 'Recovered'));
      await failure;
      expect((await afterFailure)?.id, 'old');
      await recovered;
      expect((await store.load())?.id, 'recovered');
    },
  );

  test(
    'save rechecks the current record even after an earlier successful load',
    () async {
      await store.save(SavedSpeaker('old', 'Old'));
      await store.load();
      const newer = '{"version":9,"id":"future","name":"Future"}';
      await preferences.setString(
        SharedPreferencesSavedSpeakerStore.key,
        newer,
      );
      await expectLater(
        store.save(SavedSpeaker('new', 'New')),
        throwsFormatException,
      );
      expect(
        await preferences.getString(SharedPreferencesSavedSpeakerStore.key),
        newer,
      );
    },
  );
}

final class _PreferencesPlatform extends InMemorySharedPreferencesAsync {
  _PreferencesPlatform() : super.empty();
  Completer<void>? pauseNextWrite;
  final writeStarted = Completer<void>();
  bool failNextWrite = false;

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    final pause = pauseNextWrite;
    if (pause != null) {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await pause.future;
      pauseNextWrite = null;
    }
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Simulated platform write failure');
    }
    return super.setString(key, value, options);
  }
}
