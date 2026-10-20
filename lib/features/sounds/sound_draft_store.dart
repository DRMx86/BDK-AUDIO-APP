import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'sound_import_controller.dart';
import 'wav_audio.dart';

abstract interface class SoundDraftStore {
  Future<Map<int, PreparedSound>> load();
  Future<void> save(int type, PreparedSound sound);
}

class FileSoundDraftStore implements SoundDraftStore {
  FileSoundDraftStore(
    this.file, {
    Future<void> Function(File, File)? commitFile,
  }) : _commitFile = commitFile ?? _rename;
  final File file;
  final Future<void> Function(File, File) _commitFile;
  Future<void> _tail = Future<void>.value();
  Map<int, PreparedSound>? _cache;
  static var _scratch = 0;
  static const _maximumStoreBytes = 1200 * 1024;
  static Future<void> _rename(File temporary, File destination) async {
    await temporary.rename(destination.path);
  }

  Future<T> _queue<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _read() async {
    if (_cache != null) return;
    if (!await file.exists()) {
      _cache = {};
      return;
    }
    if (await file.length() > _maximumStoreBytes) {
      throw const FormatException(
        'Saved sound previews exceed the storage bound.',
      );
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, _maximumStoreBytes + 1)) {
      if (chunk.length > _maximumStoreBytes - buffer.length) {
        throw const FormatException(
          'Saved sound previews exceed the storage bound.',
        );
      }
      buffer.add(chunk);
    }
    final text = utf8.decode(buffer.takeBytes());
    _cache = await _decodeDraftsOffThread(text);
  }

  @override
  Future<Map<int, PreparedSound>> load() => _queue(() async {
    await _read();
    return Map<int, PreparedSound>.unmodifiable(_cache!);
  });
  @override
  Future<void> save(int type, PreparedSound sound) => _queue(() async {
    RangeError.checkValueInInterval(type, 0, 3);
    _validate(sound);
    await _read();
    final next = {..._cache!, type: sound};
    final text = await _encodeDraftsOffThread(next);
    if (utf8.encode(text).length > _maximumStoreBytes) {
      throw const FormatException(
        'Saved sound previews exceed the storage bound.',
      );
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp-$pid-${++_scratch}');
    try {
      await temporary.writeAsString(text, flush: true);
      await _commitFile(temporary, file);
      _cache = next;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  });

  static void _validate(PreparedSound sound) {
    final wave = Pcm16Wave.decode(
      sound.wave,
      maximumBytes: SoundClipPolicy.maximumBytes,
    );
    if (sound.name.trim().isEmpty ||
        sound.name.length > 1024 ||
        sound.plan.requiresTrim ||
        wave.channels != 1 ||
        wave.sampleRate != sound.plan.outputRate ||
        wave.frames != sound.plan.frameCount ||
        sound.wave.length != 44 + wave.frames * 2 ||
        sound.plan.total != sound.sourceInfo.duration ||
        sound.sourceInfo.sampleRate < 1 ||
        sound.sourceInfo.sampleRate > 384000 ||
        sound.sourceInfo.channels < 1 ||
        sound.sourceInfo.channels > 64 ||
        sound.sourceInfo.duration <= Duration.zero ||
        sound.sourceInfo.duration > const Duration(days: 7)) {
      throw const FormatException('Invalid saved sound preview.');
    }
  }

  static String _encode(Map<int, PreparedSound> data) => jsonEncode({
    'version': 1,
    'sounds': [
      for (final entry in data.entries)
        {
          'slot': entry.key,
          'name': entry.value.name,
          'wave': base64Encode(entry.value.wave),
          'selection': {
            'totalUs': entry.value.plan.total.inMicroseconds,
            'startUs': entry.value.plan.start.inMicroseconds,
            'endUs': entry.value.plan.end.inMicroseconds,
            'rate': entry.value.plan.outputRate,
          },
          'source': {
            'durationUs': entry.value.sourceInfo.duration.inMicroseconds,
            'rate': entry.value.sourceInfo.sampleRate,
            'channels': entry.value.sourceInfo.channels,
          },
        },
    ],
  });
  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved sound metadata.');
    }
    return value;
  }

  static int _int(Map<String, dynamic> data, String key) {
    if (data[key] is! int) {
      throw const FormatException('Invalid saved sound dimension.');
    }
    return data[key] as int;
  }

  static Map<int, PreparedSound> _decode(String text) {
    final data = _map(jsonDecode(text));
    if (data['version'] != 1 ||
        data['sounds'] is! List ||
        (data['sounds'] as List).length > 4) {
      throw const FormatException('Unsupported saved sound version.');
    }
    final result = <int, PreparedSound>{};
    for (final raw in data['sounds'] as List) {
      final item = _map(raw),
          selection = _map(_map(raw)['selection']),
          source = _map(_map(raw)['source']);
      final type = _int(item, 'slot');
      if (type < 0 ||
          type > 3 ||
          result.containsKey(type) ||
          item['name'] is! String ||
          item['wave'] is! String ||
          (item['wave'] as String).length >
              (SoundClipPolicy.maximumBytes + 2) ~/ 3 * 4) {
        throw const FormatException('Invalid saved sound slot.');
      }
      SoundClipPlan plan;
      try {
        plan = SoundClipPolicy.plan(
          total: Duration(microseconds: _int(selection, 'totalUs')),
          start: Duration(microseconds: _int(selection, 'startUs')),
          end: Duration(microseconds: _int(selection, 'endUs')),
        );
      } on ArgumentError {
        throw const FormatException('Invalid saved sound selection.');
      }
      if (plan.outputRate != _int(selection, 'rate')) {
        throw const FormatException('Invalid saved sound rate.');
      }
      final sound = PreparedSound(
        name: item['name'] as String,
        wave: base64Decode(item['wave'] as String),
        plan: plan,
        sourceInfo: AudioImportInfo(
          duration: Duration(microseconds: _int(source, 'durationUs')),
          sampleRate: _int(source, 'rate'),
          channels: _int(source, 'channels'),
        ),
      );
      _validate(sound);
      result[type] = sound;
    }
    return result;
  }
}

// Keep isolate closures outside instance callbacks so they cannot capture the
// store's non-sendable pending I/O futures through a parent closure context.
Future<String> _encodeDraftsOffThread(Map<int, PreparedSound> data) =>
    Isolate.run(() => FileSoundDraftStore._encode(data));
Future<Map<int, PreparedSound>> _decodeDraftsOffThread(String text) =>
    Isolate.run(() => FileSoundDraftStore._decode(text));
