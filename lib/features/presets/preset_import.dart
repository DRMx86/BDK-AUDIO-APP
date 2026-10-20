import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';
import '../../persistence/profile_store.dart';

class PresetMerge {
  const PresetMerge(this.data, this.addedCount, this.skippedCount);
  final ProfileData data;
  final int addedCount, skippedCount;
}

abstract final class PresetImport {
  static const maximumBytes = 256 * 1024;
  static const maximumProfiles = 128;
  static final _legacyKey = RegExp(
    r'^custom_(?:preset_)?[123]_(name|bass|mid|treble)$',
  );

  static List<SoundProfile> parse(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumBytes) {
      throw const FormatException(
        'Choose a preset file no larger than 256 KiB.',
      );
    }
    try {
      final text = utf8
          .decode(bytes)
          .replaceFirst(RegExp(r'^\uFEFF'), '')
          .trim();
      final values = text.startsWith('<') ? _xml(text) : _json(text);
      final unique = <String, SoundProfile>{};
      for (final p in values) {
        final name = p.name.trim();
        if (name.isEmpty ||
            name.length > 120 ||
            name.contains(RegExp(r'[\x00-\x1f]'))) {
          throw const FormatException(
            'Preset names must contain 1–120 characters.',
          );
        }
        final id = _identity(name, p.gains.values);
        unique.putIfAbsent(
          id,
          () => SoundProfile(id, name, p.gains, description: 'Imported preset'),
        );
      }
      if (unique.length > maximumProfiles) {
        throw const FormatException('Import up to 128 presets at a time.');
      }
      return List.unmodifiable(unique.values);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('This preset file could not be read.');
    }
  }

  static String _identity(String name, List<int> levels) =>
      'import-${sha256.convert(utf8.encode(jsonEncode([name, ...levels]))).toString().substring(0, 24)}';

  static List<SoundProfile> _xml(String text) {
    // SharedPreferences needs no DTD, external entities or arbitrary nesting.
    // Validate the event stream before constructing a bounded DOM.
    var depth = 0, nodes = 0;
    for (final event in parseEvents(
      text,
      validateDocument: true,
      validateNesting: true,
    )) {
      if (++nodes > 20000 || event is XmlDoctypeEvent) {
        throw const FormatException('Unsupported Android preset document.');
      }
      if (event is XmlStartElementEvent && !event.isSelfClosing) {
        if (++depth > 4) {
          throw const FormatException('Preset document is too deeply nested.');
        }
      } else if (event is XmlEndElementEvent) {
        depth--;
      }
    }
    final root = XmlDocument.parse(text).rootElement;
    if (root.name.qualified != 'map') {
      throw const FormatException(
        'Choose the original Android preferences file.',
      );
    }
    final map = <String, Object>{};
    for (final element in root.childElements) {
      final key = element.getAttribute('name');
      if (key == null || !_legacyKey.hasMatch(key)) continue;
      if (map.containsKey(key) || element.childElements.isNotEmpty) {
        throw const FormatException(
          'Duplicate or invalid Android preset entry.',
        );
      }
      if (key.endsWith('_name') && element.name.qualified == 'string') {
        map[key] = element.innerText;
      } else if (!key.endsWith('_name') && element.name.qualified == 'int') {
        final value = int.tryParse(element.getAttribute('value') ?? '');
        if (value == null) {
          throw const FormatException('Invalid Android equalizer value.');
        }
        map[key] = value;
      } else {
        throw const FormatException('Invalid Android preset value type.');
      }
    }
    return _legacy(map);
  }

  static List<SoundProfile> _json(String text) {
    final data = jsonDecode(text);
    if (data is! Map<String, dynamic> ||
        data['version'] is! int ||
        data['version'] != 1) {
      throw const FormatException('Unsupported preset file version.');
    }
    if (data['format'] == 'bdk-android-prefs') {
      final values = data['preferences'];
      if (values is! Map<String, dynamic>) {
        throw const FormatException('Invalid Android preset backup.');
      }
      return _legacy(values);
    }
    final raw = data['profiles'];
    if (raw is! List || raw.length > maximumProfiles) {
      throw const FormatException('Import up to 128 presets at a time.');
    }
    return ProfileData.decode(text).profiles;
  }

  static List<SoundProfile> _legacy(Map<String, dynamic> map) {
    final result = <SoundProfile>[];
    for (final prefix in ['custom_preset_', 'custom_']) {
      for (var slot = 1; slot <= 3; slot++) {
        final key = '$prefix$slot';
        final saved = prefix == 'custom_preset_'
            ? map.containsKey('${key}_name')
            : map.containsKey('${key}_bass');
        // Validate every relevant entry, including incomplete saved slots.
        for (final band in ['bass', 'mid', 'treble']) {
          final value = map['${key}_$band'];
          if (value != null && (value is! int || value < 0 || value > 100)) {
            throw const FormatException(
              'Android equalizer values must be 0–100.',
            );
          }
        }
        final rawName = map['${key}_name'];
        if (rawName != null && rawName is! String) {
          throw const FormatException('Invalid preset name.');
        }
        if (!saved) continue;
        final name = rawName == null || (rawName as String).trim().isEmpty
            ? 'Custom $slot'
            : rawName;
        result.add(
          SoundProfile.fromLegacySlot(
            slot,
            name,
            map['${key}_bass'] as int? ?? 50,
            map['${key}_mid'] as int? ?? 50,
            map['${key}_treble'] as int? ?? 50,
          ),
        );
      }
    }
    return result;
  }

  static PresetMerge merge(
    ProfileData current,
    Iterable<SoundProfile> incoming,
  ) {
    final values = [...current.profiles],
        names = values.map((p) => p.name).toSet();
    final ids = values.map((p) => p.id).toSet();
    final fingerprints = values
        .map((p) => _identity(p.name.trim(), p.gains.values))
        .toSet();
    var added = 0, skipped = 0;
    for (final p in incoming) {
      if (ids.contains(p.id) ||
          fingerprints.contains(_identity(p.name.trim(), p.gains.values))) {
        skipped++;
        continue;
      }
      if (values.length >= maximumProfiles) {
        throw const FormatException(
          'Your library holds up to 128 presets. No presets were imported.',
        );
      }
      var name = p.name, suffix = 2;
      while (names.contains(name)) {
        final ending = ' (${suffix++})';
        final runes = p.name.runes.toList();
        var length = p.name.length;
        while (length + ending.length > 120) {
          length -= runes.removeLast() > 0xffff ? 2 : 1;
        }
        name = '${String.fromCharCodes(runes)}$ending';
      }
      values.add(SoundProfile(p.id, name, p.gains, description: p.description));
      ids.add(p.id);
      names.add(name);
      fingerprints.add(_identity(p.name.trim(), p.gains.values));
      added++;
    }
    return PresetMerge(
      ProfileData(
        profiles: List.unmodifiable(values),
        favorites: current.favorites,
        theme: current.theme,
      ),
      added,
      skipped,
    );
  }
}
