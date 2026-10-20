import '../../domain/speaker_state.dart';
import '../../persistence/profile_store.dart';

abstract final class ProfileMutations {
  static String name(String raw, Iterable<String> taken) {
    final value = raw.trim();
    if (value.isEmpty) throw const FormatException('Enter a preset name.');
    if (value.length > 120 || RegExp(r'[\x00-\x1f]').hasMatch(value)) {
      throw const FormatException(
        'Use a shorter preset name without line breaks.',
      );
    }
    if (taken.contains(value)) {
      throw const FormatException('Choose a different preset name.');
    }
    return value;
  }

  static SoundProfile _find(ProfileData data, String id) =>
      data.profiles.where((p) => p.id == id).firstOrNull ??
      (throw const FormatException('This preset is no longer available.'));
  static ProfileData _with(
    ProfileData data,
    List<SoundProfile> profiles, {
    List<String>? favorites,
  }) => ProfileData(
    profiles: List.unmodifiable(profiles),
    favorites: favorites ?? data.favorites,
    theme: data.theme,
  );
  static ProfileData rename(ProfileData data, String id, String raw) {
    final previous = _find(data, id);
    final value = name(
      raw,
      data.profiles.where((p) => p.id != id).map((p) => p.name),
    );
    return _with(data, [
      for (final p in data.profiles)
        if (p.id == id)
          SoundProfile(
            id,
            value,
            previous.gains,
            description: previous.description,
          )
        else
          p,
    ]);
  }

  static ProfileData replace(ProfileData data, String id, EqGains gains) {
    final previous = _find(data, id);
    return _with(data, [
      for (final p in data.profiles)
        if (p.id == id)
          SoundProfile(
            id,
            previous.name,
            gains,
            description: previous.description,
          )
        else
          p,
    ]);
  }

  static ProfileData delete(ProfileData data, String id) {
    _find(data, id);
    return _with(
      data,
      data.profiles.where((p) => p.id != id).toList(),
      favorites: List.unmodifiable(
        data.favorites.where((value) => value != id),
      ),
    );
  }
}
