import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedSpeaker {
  const SavedSpeaker(this.id, this.name);
  final String id;
  final String name;
}

abstract interface class SavedSpeakerStore {
  Future<SavedSpeaker?> load();
  Future<void> save(SavedSpeaker speaker);
}

class SharedPreferencesSavedSpeakerStore implements SavedSpeakerStore {
  SharedPreferencesSavedSpeakerStore(this._preferences);
  static const key = 'last_speaker_v1';
  static const _maxPayloadBytes = 4096;
  final SharedPreferencesAsync _preferences;
  Future<void> _tail = Future<void>.value();

  @override
  Future<SavedSpeaker?> load() => _enqueue(() async {
    final raw = await _preferences.getString(key);
    return raw == null ? null : _decode(raw);
  });

  @override
  Future<void> save(SavedSpeaker speaker) => _enqueue(() async {
    _validate(speaker);
    // Never replace an unreadable or newer record with startup fallback data.
    final previous = await _preferences.getString(key);
    if (previous != null) _decode(previous);
    await _preferences.setString(
      key,
      jsonEncode({'version': 1, 'id': speaker.id, 'name': speaker.name}),
    );
  });

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    // A refused operation must not prevent later reads or valid writes.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static SavedSpeaker _decode(String raw) {
    if (raw.length > _maxPayloadBytes ||
        utf8.encode(raw).length > _maxPayloadBytes) {
      throw const FormatException('Saved speaker record is too large.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] is! int ||
        decoded['version'] != 1 ||
        decoded['id'] is! String ||
        decoded['name'] is! String) {
      throw const FormatException(
        'Invalid or unsupported saved speaker record.',
      );
    }
    final speaker = SavedSpeaker(
      decoded['id'] as String,
      decoded['name'] as String,
    );
    _validate(speaker);
    return speaker;
  }

  static void _validate(SavedSpeaker speaker) {
    _validateField(speaker.id, 128);
    _validateField(speaker.name, 120);
  }

  static void _validateField(String value, int maxBytes) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f) ||
        utf8.encode(value).length > maxBytes) {
      throw const FormatException('Invalid saved speaker identifier or name.');
    }
  }
}
