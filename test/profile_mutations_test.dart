import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/persistence/profile_store.dart';
import 'package:bdk_audio/features/presets/profile_mutations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final initial = ProfileData(
    profiles: [
      SoundProfile('one', 'Evening', EqGains(2, -1, 3)),
      SoundProfile('two', 'Desk', const EqGains.zero()),
    ],
    favorites: const ['one', 'warm'],
    theme: 'dark',
  );
  test(
    'rename preserves identity, gain values, other profiles and settings',
    () {
      final changed = ProfileMutations.rename(initial, 'one', 'Night');
      expect(changed.profiles.first.id, 'one');
      expect(changed.profiles.first.gains, EqGains(2, -1, 3));
      expect(changed.profiles.last, same(initial.profiles.last));
      expect(changed.favorites, initial.favorites);
      expect(changed.theme, 'dark');
      expect(initial.profiles.first.name, 'Evening');
    },
  );
  test('replacement changes only the chosen profile gains', () {
    final changed = ProfileMutations.replace(initial, 'one', EqGains(8, 0, -2));
    expect(changed.profiles.first.name, 'Evening');
    expect(changed.profiles.first.id, 'one');
    expect(changed.profiles.first.gains, EqGains(8, 0, -2));
    expect(changed.profiles.last, same(initial.profiles.last));
  });
  test(
    'deletion removes the chosen identity and its favorite reference only',
    () {
      final changed = ProfileMutations.delete(initial, 'one');
      expect(changed.profiles.single.id, 'two');
      expect(changed.favorites, ['warm']);
      expect(changed.theme, 'dark');
      expect(initial.profiles, hasLength(2));
    },
  );
  test(
    'invalid names and stale identities never silently mutate another profile',
    () {
      for (final name in ['', '  ', 'Desk', 'bad\nname', 'a' * 121]) {
        expect(
          () => ProfileMutations.rename(initial, 'one', name),
          throwsFormatException,
        );
      }
      expect(
        () => ProfileMutations.delete(initial, 'missing'),
        throwsFormatException,
      );
      expect(
        () =>
            ProfileMutations.replace(initial, 'missing', const EqGains.zero()),
        throwsFormatException,
      );
    },
  );
}
