import 'package:flutter_test/flutter_test.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/persistence/profile_store.dart';

void main() {
  test(
    'named profiles survive serialization and unknown versions are rejected',
    () {
      final data = ProfileData(
        profiles: [SoundProfile('mine', 'Evening', EqGains(2, -1, 3))],
      );
      final loaded = ProfileData.decode(data.encode());
      expect(loaded.profiles.single.name, 'Evening');
      expect(loaded.profiles.single.gains, EqGains(2, -1, 3));
      expect(
        () => ProfileData.decode('{"version":9,"profiles":[]}'),
        throwsFormatException,
      );
    },
  );
  test(
    'Android percent presets truncate exactly like Kotlin and use actual EQ packets',
    () {
      expect(builtInProfiles.length, 12);
      expect(builtInProfiles[1].gains, EqGains(8, -1, -2));
      expect(builtInProfiles[6].gains, EqGains(0, 0, 0));
      final p = SoundProfile.fromLegacySlot(0, 'Legacy', 85, 45, 40);
      expect(p.gains, builtInProfiles[1].gains);
    },
  );
  test('malformed or out-of-range imported profile never becomes valid', () {
    expect(
      () => ProfileData.decode(
        '{"version":1,"profiles":[{"id":"x","name":"bad","levels":[40,0,0]}]}',
      ),
      throwsFormatException,
    );
  });
}
