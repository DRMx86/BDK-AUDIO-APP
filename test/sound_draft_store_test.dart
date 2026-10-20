import 'dart:io';
import 'dart:typed_data';
import 'package:bdk_audio/features/sounds/sound_draft_store.dart';
import 'package:bdk_audio/features/sounds/sound_import_controller.dart';
import 'package:bdk_audio/features/sounds/wav_audio.dart';
import 'package:flutter_test/flutter_test.dart';

PreparedSound draft(String name) {
  final plan = SoundClipPolicy.plan(total: const Duration(seconds: 1));
  final pcm = Int16List(plan.frameCount!)..[7] = -12345;
  return PreparedSound(
    name: name,
    wave: Pcm16Wave.encodeMono(pcm, plan.outputRate!),
    plan: plan,
    sourceInfo: const AudioImportInfo(
      duration: Duration(seconds: 1),
      sampleRate: 48000,
      channels: 2,
    ),
  );
}

void main() {
  late Directory root;
  late File file;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bdk_sound_store_test_');
    file = File('${root.path}${Platform.pathSeparator}drafts.json');
  });
  tearDown(() async {
    for (final entry in await root.list().toList()) {
      if (entry is File) await entry.delete();
    }
    await root.delete();
  });

  test(
    'four local drafts survive a fresh store without being marked uploaded',
    () async {
      final store = FileSoundDraftStore(file);
      await Future.wait([
        for (var i = 0; i < 4; i++) store.save(i, draft('Sound$i.wav')),
      ]);
      final loaded = await FileSoundDraftStore(file).load();
      expect(loaded.length, 4);
      expect(loaded[2]!.name, 'Sound2.wav');
      expect(Pcm16Wave.decode(loaded[2]!.wave).samples[7], -12345);
      expect(loaded[2]!.sourceInfo.channels, 2);
      expect(() => loaded[0] = draft('bad'), throwsUnsupportedError);
    },
  );

  test(
    'unknown storage versions preserve the original bytes and refuse overwrite',
    () async {
      const original = '{"version":99,"privateData":"retain"}';
      await file.writeAsString(original);
      final store = FileSoundDraftStore(file);
      await expectLater(store.load(), throwsFormatException);
      await expectLater(store.save(0, draft('new')), throwsFormatException);
      expect(await file.readAsString(), original);
    },
  );

  test('an invalid sound cannot become a stored compatible draft', () async {
    final valid = draft('good');
    final invalid = PreparedSound(
      name: 'bad',
      wave: Uint8List(3),
      plan: valid.plan,
      sourceInfo: valid.sourceInfo,
    );
    await expectLater(
      FileSoundDraftStore(file).save(0, invalid),
      throwsFormatException,
    );
    expect(await file.exists(), isFalse);
  });

  test(
    'a failed atomic replacement retains prior drafts and removes the temporary write',
    () async {
      await FileSoundDraftStore(file).save(0, draft('old'));
      final original = await file.readAsBytes();
      final failing = FileSoundDraftStore(
        file,
        commitFile: (_, _) async =>
            throw const FileSystemException('Simulated disk commit failure'),
      );
      await expectLater(
        failing.save(1, draft('new')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsBytes(), orderedEquals(original));
      expect((await failing.load()).keys, [0]);
      expect(await root.list().toList(), hasLength(1));
    },
  );
}
