import 'package:bdk_audio/persistence/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'saving cannot overwrite a newer or unreadable existing profile store',
    () async {
      var raw = '{"version":9,"profiles":[]}';
      var writes = 0;
      final store = ProfileStore.fromCallbacks(
        read: () async => raw,
        write: (value) async {
          writes++;
          raw = value;
        },
      );
      await expectLater(store.load(), throwsFormatException);
      await expectLater(store.save(const ProfileData()), throwsFormatException);
      expect(writes, 0);
      expect(raw, contains('"version":9'));
      raw = const ProfileData().encode();
      await store.save(const ProfileData(theme: 'dark'));
      expect(ProfileData.decode(raw).theme, 'dark');
    },
  );
}
