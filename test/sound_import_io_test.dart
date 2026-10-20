import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:bdk_audio/features/sounds/sound_import_controller.dart';
import 'package:bdk_audio/features/sounds/sound_import_io.dart';
import 'package:bdk_audio/features/sounds/wav_audio.dart';
import 'package:flutter_test/flutter_test.dart';

class TestDecoder implements SoundFileDecoder {
  Completer<Int16List>? gate;
  @override
  Future<AudioImportInfo> inspect(String path) async => const AudioImportInfo(
    duration: Duration(seconds: 1),
    sampleRate: 22050,
    channels: 1,
  );
  @override
  Future<Int16List> decode(String path, SoundClipPlan plan) async =>
      gate == null ? Int16List(plan.frameCount!) : await gate!.future;
}

class TestPlayer implements LocalSoundPlayer {
  final stream = StreamController<SoundPreviewEvent>.broadcast(sync: true);
  String? played;
  Completer<void>? stopGate;
  @override
  Stream<SoundPreviewEvent> get events => stream.stream;
  @override
  Future<void> playFile(String path, {required int revision}) async {
    played = path;
    stream.add(SoundPreviewEvent(revision, playing: true));
  }

  @override
  Future<void> stop() async {
    await stopGate?.future;
  }

  @override
  Future<void> dispose() async {
    await stream.close();
  }
}

void main() {
  late Directory root;
  late TestDecoder decoder;
  late TestPlayer player;
  late SystemSoundImportIO io;
  late File original;
  late Uint8List bytes;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bdk_sound_io_test_');
    bytes = Pcm16Wave.encodeMono(Int16List(1600), 16000);
    original = await File(
      '${root.path}${Platform.pathSeparator}original.wav',
    ).writeAsBytes(bytes);
    decoder = TestDecoder();
    player = TestPlayer();
    io = SystemSoundImportIO(
      picker: () async => PickedSoundFile(
        name: '../Chime.wav',
        length: bytes.length,
        openStream: original.openRead,
      ),
      decoder: decoder,
      player: player,
      createTempDirectory: () => root.createTemp('work_'),
    );
  });
  tearDown(() async {
    await io.dispose();
    if (await original.exists()) await original.delete();
    await root.delete();
  });

  test(
    'imports a private copy and cleanup never deletes the selected original',
    () async {
      final source = (await io.pick())!;
      expect(source.path, isNot(original.path));
      expect(source.name, '../Chime.wav');
      expect(await File(source.path).readAsBytes(), orderedEquals(bytes));
      expect(File(source.path).parent.path, startsWith(root.path));
      await io.dispose();
      expect(await original.readAsBytes(), orderedEquals(bytes));
      expect(await File(source.path).exists(), isFalse);
    },
  );

  test(
    'unknown-length streams stop at the cap and remove the partial private copy',
    () async {
      await io.dispose();
      var chunksRead = 0;
      Stream<List<int>> chunks() async* {
        for (var i = 0; i < 100; i++) {
          chunksRead++;
          yield Uint8List(64);
        }
      }

      io = SystemSoundImportIO(
        picker: () async =>
            PickedSoundFile(name: 'big.wav', openStream: chunks),
        decoder: decoder,
        player: TestPlayer(),
        maximumInputBytes: 100,
        createTempDirectory: () => root.createTemp('work_'),
      );
      await expectLater(io.pick(), throwsA(isA<AudioImportException>()));
      expect(chunksRead, lessThan(100));
      await io.dispose();
      expect(await root.list().toList(), hasLength(1));
    },
  );

  test(
    'disposal waits for the decoder to release an owned input file',
    () async {
      final source = (await io.pick())!;
      decoder.gate = Completer<Int16List>();
      final decoding = io.decode(
        source,
        SoundClipPolicy.plan(total: const Duration(seconds: 1)),
      );
      await Future<void>.delayed(Duration.zero);
      final disposal = io.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(await File(source.path).exists(), isTrue);
      decoder.gate!.complete(Int16List(22050));
      await decoding;
      await disposal;
      expect(await File(source.path).exists(), isFalse);
    },
  );

  test(
    'an older copy finishing last cannot replace or delete the newer source',
    () async {
      await io.dispose();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var picks = 0;
      Stream<List<int>> slowCopy() async* {
        firstStarted.complete();
        await releaseFirst.future;
        yield bytes;
      }

      io = SystemSoundImportIO(
        picker: () async => PickedSoundFile(
          name: ++picks == 1 ? 'old.wav' : 'new.wav',
          openStream: picks == 1 ? slowCopy : original.openRead,
        ),
        decoder: decoder,
        player: TestPlayer(),
        createTempDirectory: () => root.createTemp('work_'),
      );
      final oldPick = io.pick();
      await firstStarted.future;
      final newest = (await io.pick())!;
      await io.inspect(newest);
      releaseFirst.complete();
      expect(await oldPick, isNull);
      expect(await File(newest.path).exists(), isTrue);
      expect(await io.inspect(newest), isA<AudioImportInfo>());
      expect(
        await io.decode(
          newest,
          SoundClipPolicy.plan(total: const Duration(seconds: 1)),
        ),
        hasLength(22050),
      );
    },
  );

  test(
    'cancelling a copy retains the adopted source for later clip edits',
    () async {
      await io.dispose();
      final started = Completer<void>(), release = Completer<void>();
      var picks = 0;
      Stream<List<int>> slowCopy() async* {
        started.complete();
        await release.future;
        yield bytes;
      }

      io = SystemSoundImportIO(
        picker: () async => PickedSoundFile(
          name: 'sound.wav',
          openStream: ++picks == 1 ? original.openRead : slowCopy,
        ),
        decoder: decoder,
        player: TestPlayer(),
        createTempDirectory: () => root.createTemp('work_'),
      );
      final adopted = (await io.pick())!;
      await io.inspect(adopted);
      final cancelled = io.pick();
      await started.future;
      io.cancelPick();
      release.complete();
      expect(await cancelled, isNull);
      expect(await File(adopted.path).exists(), isTrue);
      expect(
        await io.decode(
          adopted,
          SoundClipPolicy.plan(total: const Duration(seconds: 1)),
        ),
        hasLength(22050),
      );
    },
  );

  test(
    'preview cleanup follows player stop and preserves exact prepared bytes',
    () async {
      await io.play(bytes, revision: 7);
      final path = player.played!;
      expect(await File(path).readAsBytes(), orderedEquals(bytes));
      player.stopGate = Completer<void>();
      final stopping = io.stop();
      await Future<void>.delayed(Duration.zero);
      expect(await File(path).exists(), isTrue);
      player.stopGate!.complete();
      await stopping;
      expect(await File(path).exists(), isFalse);
    },
  );
}
