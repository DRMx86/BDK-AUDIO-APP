import 'dart:async';
import 'dart:typed_data';
import 'package:bdk_audio/features/sounds/sound_import_controller.dart';
import 'package:bdk_audio/features/sounds/wav_audio.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSoundIO implements SoundImportIO {
  AudioImportSource? picked = const AudioImportSource(
    path: 'test.wav',
    name: 'Chime.wav',
  );
  AudioImportInfo metadata = const AudioImportInfo(
    duration: Duration(seconds: 2),
    sampleRate: 48000,
    channels: 2,
  );
  final events = StreamController<SoundPreviewEvent>.broadcast(sync: true);
  final decoded = <SoundClipPlan>[];
  final played = <int>[];
  Completer<Int16List>? decodeGate;
  bool shortDecode = false;
  bool completesDuringPlay = false;
  int disposed = 0, stopped = 0;
  @override
  Stream<SoundPreviewEvent> get previewEvents => events.stream;
  @override
  Future<AudioImportSource?> pick() async => picked;
  @override
  void cancelPick() {}
  @override
  Future<AudioImportInfo> inspect(AudioImportSource source) async => metadata;
  @override
  Future<Int16List> decode(AudioImportSource source, SoundClipPlan plan) async {
    decoded.add(plan);
    return decodeGate == null
        ? Int16List(plan.frameCount! - (shortDecode ? 1 : 0))
        : await decodeGate!.future;
  }

  @override
  Future<void> play(Uint8List wave, {required int revision}) async {
    played.add(revision);
    events.add(SoundPreviewEvent(revision, playing: true));
    if (completesDuringPlay) events.add(SoundPreviewEvent(revision));
  }

  @override
  Future<void> stop() async {
    stopped++;
  }

  @override
  Future<void> dispose() async {
    disposed++;
  }
}

void main() {
  late FakeSoundIO io;
  late SoundImportController controller;
  var disposed = false;
  setUp(() {
    io = FakeSoundIO();
    controller = SoundImportController(io);
    disposed = false;
  });
  tearDown(() async {
    if (!disposed) controller.dispose();
    await io.events.close();
  });

  test(
    'short audio prepares a bounded canonical preview from actual decoded samples',
    () async {
      await controller.pickFile();
      expect(controller.phase, SoundImportPhase.ready);
      final prepared = controller.prepared!;
      expect(prepared.name, 'Chime.wav');
      expect(prepared.plan.outputRate, 22050);
      expect(io.decoded.single.frameCount, 44100);
      final wav = Pcm16Wave.decode(prepared.wave);
      expect(wav.frames, 44100);
      expect(wav.channels, 1);
      expect(wav.sampleRate, 22050);
      expect(() => prepared.wave[0] = 0, throwsUnsupportedError);
    },
  );

  test(
    'long import waits for explicit clip selection without decoding or truncating',
    () async {
      io.metadata = const AudioImportInfo(
        duration: Duration(minutes: 1),
        sampleRate: 44100,
        channels: 1,
      );
      await controller.pickFile();
      expect(controller.phase, SoundImportPhase.choosingClip);
      expect(controller.plan!.requiresTrim, isTrue);
      expect(controller.prepared, isNull);
      expect(io.decoded, isEmpty);
      controller.selectClip(
        const Duration(seconds: 10),
        const Duration(seconds: 15),
      );
      await controller.prepare();
      expect(controller.prepared!.plan.isExcerpt, isTrue);
      expect(controller.prepared!.plan.outputRate, 16000);
      expect(controller.prepared!.wave.length, 160044);
    },
  );

  test(
    'cancelling the file picker preserves the existing prepared clip',
    () async {
      await controller.pickFile();
      final old = controller.prepared;
      io.picked = null;
      await controller.pickFile();
      expect(controller.prepared, same(old));
      expect(controller.phase, SoundImportPhase.ready);
    },
  );

  test(
    'a decode completed after selecting another clip cannot resurrect the old draft',
    () async {
      io.decodeGate = Completer<Int16List>();
      final oldPick = controller.pickFile();
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.phase, SoundImportPhase.preparing);
      controller.selectClip(Duration.zero, const Duration(seconds: 1));
      io.decodeGate!.complete(Int16List(44100));
      await oldPick;
      expect(controller.prepared, isNull);
      expect(controller.phase, SoundImportPhase.choosingClip);
      io.decodeGate = null;
      await controller.prepare();
      expect(controller.prepared!.plan.frameCount, 22050);
    },
  );

  test(
    'short decoded output is an error rather than a padded successful sound',
    () async {
      io.shortDecode = true;
      await controller.pickFile();
      expect(controller.phase, SoundImportPhase.failed);
      expect(controller.prepared, isNull);
      expect(controller.message, isNotEmpty);
    },
  );

  test(
    'late work after disposal cannot notify or publish a prepared file',
    () async {
      io.decodeGate = Completer<Int16List>();
      var notices = 0;
      controller.addListener(() => notices++);
      final pending = controller.pickFile();
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.dispose();
      disposed = true;
      final before = notices;
      io.decodeGate!.complete(Int16List(44100));
      await pending;
      expect(notices, before);
      expect(io.disposed, 1);
    },
  );

  test(
    'preview completion belongs to the current revision and pause stops local playback',
    () async {
      await controller.pickFile();
      await controller.togglePreview();
      expect(controller.playing, isTrue);
      final first = io.played.last;
      await controller.stopPreview();
      expect(controller.playing, isFalse);
      await controller.togglePreview();
      io.events.add(SoundPreviewEvent(first));
      expect(controller.playing, isTrue);
      io.events.add(SoundPreviewEvent(io.played.last));
      expect(controller.playing, isFalse);
    },
  );

  test(
    'stopping playback while decoding does not cancel the audio preparation',
    () async {
      io.decodeGate = Completer<Int16List>();
      final pending = controller.pickFile();
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.stopPreview();
      io.decodeGate!.complete(Int16List(44100));
      await pending;
      expect(controller.phase, SoundImportPhase.ready);
      expect(controller.prepared, isNotNull);
    },
  );

  test(
    'a tiny preview that completes before play returns never stays marked playing',
    () async {
      await controller.pickFile();
      io.completesDuringPlay = true;
      await controller.togglePreview();
      expect(controller.playing, isFalse);
    },
  );

  test(
    'a stored prepared clip previews without pretending the original source is available',
    () async {
      await controller.pickFile();
      final stored = controller.prepared!;
      final otherIO = FakeSoundIO();
      final restored = SoundImportController(otherIO, initial: stored);
      expect(restored.phase, SoundImportPhase.ready);
      expect(restored.source, isNull);
      expect(restored.prepared, same(stored));
      await restored.togglePreview();
      expect(restored.playing, isTrue);
      restored.selectClip(Duration.zero, const Duration(seconds: 1));
      expect(restored.prepared, same(stored));
      restored.dispose();
      await otherIO.events.close();
    },
  );
}
