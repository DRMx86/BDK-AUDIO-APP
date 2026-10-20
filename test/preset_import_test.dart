import 'dart:convert';
import 'dart:typed_data';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/persistence/profile_store.dart';
import 'package:bdk_audio/features/presets/preset_import.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List input(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test(
    'collision renaming keeps a valid long Unicode name inside storage bounds',
    () {
      final name = 'A${'🎧' * 59}B';
      expect(name.length, 120);
      final old = ProfileData(
        profiles: [SoundProfile('keep', name, const EqGains.zero())],
      );
      final incoming = PresetImport.parse(
        input(
          jsonEncode({
            'version': 1,
            'profiles': [
              {
                'id': 'old',
                'name': name,
                'levels': [1, 2, 3],
              },
            ],
          }),
        ),
      );
      final result = PresetImport.merge(old, incoming);
      expect(result.data.profiles.last.name.length, lessThanOrEqualTo(120));
      expect(result.data.profiles.last.name.endsWith(' (2)'), isTrue);
      expect(
        String.fromCharCodes(result.data.profiles.last.name.runes),
        result.data.profiles.last.name,
      );
      expect(ProfileData.decode(result.data.encode()).profiles, hasLength(2));
    },
  );
  test(
    'imports all three original Android slots using Kotlin integer scaling',
    () {
      final values = PresetImport.parse(
        input('''<?xml version="1.0"?>
<map>
  <string name="custom_preset_1_name">Night &amp; day</string>
  <int name="custom_preset_1_bass" value="85"/>
  <int name="custom_preset_1_mid" value="45"/>
  <int name="custom_preset_1_treble" value="40"/>
  <string name="custom_preset_2_name">Voice</string>
  <int name="custom_preset_2_mid" value="70"/>
  <string name="custom_preset_3_name">Third</string>
  <int name="custom_preset_3_treble" value="100"/>
  <string name="current_codec">irrelevant</string>
</map>'''),
      );
      expect(values.map((v) => v.name), ['Night & day', 'Voice', 'Third']);
      expect(values.map((v) => v.gains), [
        EqGains(8, -1, -2),
        EqGains(0, 4, 0),
        EqGains(0, 0, 12),
      ]);
      expect(values.every((v) => v.id.startsWith('import-')), isTrue);
    },
  );

  test('preserves both Android schemas and skips exact duplicate presets', () {
    final values = PresetImport.parse(
      input('''<map>
<int name="custom_1_bass" value="100"/>
<string name="custom_1_name">Deep</string>
<string name="custom_preset_1_name">Deep</string>
<int name="custom_preset_1_bass" value="100"/>
<int name="custom_3_bass" value="25"/>
</map>'''),
    );
    expect(values, hasLength(2));
    expect(values.last.name, 'Custom 3');
    expect(values.last.gains, EqGains(-6, 0, 0));
  });

  test('reads curated Android JSON and reimport preserves existing data', () {
    final imported = PresetImport.parse(
      input(
        jsonEncode({
          'format': 'bdk-android-prefs',
          'version': 1,
          'preferences': {'custom_1_bass': 75, 'custom_1_name': 'My sound'},
        }),
      ),
    );
    final old = ProfileData(
      profiles: [SoundProfile('mine', 'Keep', EqGains(1, 2, 3))],
      favorites: const ['mine', 'warm'],
      theme: 'light',
    );
    final merged = PresetImport.merge(old, imported);
    expect(merged.addedCount, 1);
    expect(merged.data.profiles.first, same(old.profiles.first));
    expect(merged.data.favorites, old.favorites);
    expect(merged.data.theme, 'light');
    final again = PresetImport.merge(merged.data, imported);
    expect(again.addedCount, 0);
    expect(again.skippedCount, 1);
    expect(again.data.profiles, hasLength(2));
  });

  test(
    'changed source becomes another preset without overwriting a local edit',
    () {
      final old = ProfileData(
        profiles: [SoundProfile('local', 'Evening', EqGains(0, 0, 0))],
      );
      final incoming = PresetImport.parse(
        input('''{"version":1,"profiles":[
{"id":"balanced","name":"Evening","levels":[4,-2,0]}]}'''),
      );
      final merged = PresetImport.merge(old, incoming);
      expect(merged.data.profiles.first.gains, const EqGains.zero());
      expect(merged.data.profiles.last.name, 'Evening (2)');
      expect(merged.data.profiles.last.id, isNot('balanced'));
      expect(PresetImport.merge(merged.data, incoming).addedCount, 0);
    },
  );

  test(
    'malformed relevant entries and external entities never become presets',
    () {
      for (final value in [
        '<map><int name="custom_1_bass" value="101"/></map>',
        '<map><string name="custom_1_bass">50</string></map>',
        '<map><int name="custom_1_bass" value="50"/><int name="custom_1_bass" value="60"/></map>',
        '<!DOCTYPE map [<!ENTITY x SYSTEM "file:///private">]><map/>',
        '<other><int name="custom_1_bass" value="50"/></other>',
        '{"version":9,"profiles":[]}',
        '<map><int name="custom_1_bass" value="50"/></broken>',
      ]) {
        expect(
          () => PresetImport.parse(input(value)),
          throwsFormatException,
          reason: value,
        );
      }
      expect(
        () => PresetImport.parse(Uint8List(PresetImport.maximumBytes + 1)),
        throwsFormatException,
      );
      expect(
        () => PresetImport.parse(input('<map>' * 20 + '</map>' * 20)),
        throwsFormatException,
      );
      expect(
        PresetImport.parse(
          input('<map><boolean name="other" value="true"/></map>'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'import does not silently drop presets when the local library is full',
    () {
      final old = ProfileData(
        profiles: List.generate(
          PresetImport.maximumProfiles,
          (i) => SoundProfile('p$i', 'Preset $i', const EqGains.zero()),
        ),
      );
      final incoming = PresetImport.parse(
        input('''<map><int name="custom_1_bass" value="99"/></map>'''),
      );
      expect(() => PresetImport.merge(old, incoming), throwsFormatException);
    },
  );
}
