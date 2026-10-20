import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/speaker_state.dart';

class SoundProfile {
  const SoundProfile(
    this.id,
    this.name,
    this.gains, {
    this.description = 'Your saved sound',
  });
  final String id, name, description;
  final EqGains gains;
  factory SoundProfile.fromLegacySlot(
    int slot,
    String name,
    int bass,
    int mid,
    int treble,
  ) {
    int level(int v) => ((v - 50) * 12 ~/ 50).clamp(-12, 12);
    return SoundProfile(
      'legacy-$slot',
      name,
      EqGains(level(bass), level(mid), level(treble)),
    );
  }
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'levels': gains.values,
  };
}

// MainActivity.applyEqPreset uses Kotlin integer division (towards zero).
final List<SoundProfile> builtInProfiles = [
  for (final p in <(String, String, int, int, int, String)>[
    ('balanced', 'Balanced', 50, 50, 50, 'Natural and even'),
    ('deep-bass', 'Deep Bass', 85, 45, 40, 'Weight and warmth'),
    ('vocals', 'Clear Vocals', 40, 70, 55, 'Voices up front'),
    ('bright', 'Bright & Clear', 45, 55, 80, 'Air and detail'),
    ('punchy', 'Punchy', 75, 40, 70, 'Energy and impact'),
    ('warm', 'Warm', 65, 55, 35, 'Soft and relaxed'),
    ('studio', 'Studio', 50, 52, 50, 'Subtle balance'),
    ('club', 'Club', 80, 45, 65, 'Feel the rhythm'),
    ('cinema', 'Cinema', 70, 60, 55, 'A fuller soundtrack'),
    ('podcast', 'Podcast', 35, 80, 50, 'Clear conversation'),
    ('gaming', 'Gaming', 75, 55, 70, 'Presence and detail'),
    ('late-night', 'Late Night', 55, 55, 40, 'Easy listening'),
  ])
    SoundProfile(
      p.$1,
      p.$2,
      SoundProfile.fromLegacySlot(0, p.$2, p.$3, p.$4, p.$5).gains,
      description: p.$6,
    ),
];

class ProfileData {
  const ProfileData({
    this.profiles = const [],
    this.favorites = const ['balanced', 'deep-bass', 'vocals', 'warm'],
    this.theme = 'system',
  });
  final List<SoundProfile> profiles;
  final List<String> favorites;
  final String theme;
  String encode() => jsonEncode({
    'version': 1,
    'profiles': profiles.map((p) => p.toJson()).toList(),
    'favorites': favorites,
    'theme': theme,
  });
  factory ProfileData.decode(String raw) {
    try {
      if (raw.length > 256 * 1024) {
        throw const FormatException('Preset storage is too large.');
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['version'] != 1) {
        throw const FormatException('Unsupported profile version');
      }
      final profiles = <SoundProfile>[];
      final items = map['profiles'] as List;
      if (items.length > 128) throw const FormatException('Too many presets.');
      final ids = <String>{};
      for (final item in items) {
        final p = item as Map<String, dynamic>, v = p['levels'] as List;
        if (v.length != 3 ||
            p['id'] is! String ||
            (p['id'] as String).isEmpty ||
            (p['id'] as String).length > 96 ||
            !ids.add(p['id'] as String) ||
            p['name'] is! String ||
            (p['name'] as String).trim().isEmpty ||
            (p['name'] as String).length > 120) {
          throw const FormatException('Invalid profile');
        }
        profiles.add(
          SoundProfile(
            p['id'],
            p['name'],
            EqGains(v[0] as int, v[1] as int, v[2] as int),
          ),
        );
      }
      return ProfileData(
        profiles: List.unmodifiable(profiles),
        favorites: List<String>.unmodifiable(
          map['favorites'] ?? ['balanced', 'deep-bass', 'vocals', 'warm'],
        ),
        theme: map['theme'] ?? 'system',
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid profile file');
    }
  }
}

class ProfileStore {
  ProfileStore(SharedPreferencesAsync preferences)
    : _read = (() => preferences.getString(key)),
      _write = ((raw) => preferences.setString(key, raw));
  factory ProfileStore.fromCallbacks({
    required Future<String?> Function() read,
    required Future<void> Function(String) write,
  }) => ProfileStore._callbacks(read, write);
  ProfileStore._callbacks(this._read, this._write);
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  Future<void> _tail = Future<void>.value();
  static const key = 'bdk.profiles.v1';
  Future<ProfileData> load() async {
    final raw = await _read();
    return raw == null ? const ProfileData() : ProfileData.decode(raw);
  }

  Future<void> save(ProfileData data) {
    final encoded = data.encode();
    final result = _tail.then((_) async {
      // An unreadable/newer file must survive startup fallback and later saves.
      final previous = await _read();
      if (previous != null) ProfileData.decode(previous);
      ProfileData.decode(encoded);
      await _write(encoded);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
