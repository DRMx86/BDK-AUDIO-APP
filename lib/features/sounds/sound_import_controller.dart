import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'wav_audio.dart';

class AudioImportSource {
  const AudioImportSource({required this.path, required this.name});
  final String path, name;
}

class AudioImportInfo {
  const AudioImportInfo({
    required this.duration,
    required this.sampleRate,
    required this.channels,
  });
  final Duration duration;
  final int sampleRate, channels;
}

class SoundPreviewEvent {
  const SoundPreviewEvent(this.revision, {this.playing = false, this.error});
  final int revision;
  final bool playing;
  final String? error;
}

abstract interface class SoundImportIO {
  Stream<SoundPreviewEvent> get previewEvents;
  Future<AudioImportSource?> pick();
  void cancelPick();
  Future<AudioImportInfo> inspect(AudioImportSource source);
  Future<Int16List> decode(AudioImportSource source, SoundClipPlan plan);
  Future<void> play(Uint8List wave, {required int revision});
  Future<void> stop();
  Future<void> dispose();
}

class PreparedSound {
  PreparedSound({
    required this.name,
    required Uint8List wave,
    required this.plan,
    required this.sourceInfo,
  }) : wave = Uint8List.fromList(wave).asUnmodifiableView();
  final String name;
  final Uint8List wave;
  final SoundClipPlan plan;
  final AudioImportInfo sourceInfo;
}

enum SoundImportPhase {
  empty,
  picking,
  inspecting,
  choosingClip,
  preparing,
  ready,
  failed,
}

class SoundImportController extends ChangeNotifier {
  SoundImportController(this.io, {PreparedSound? initial}) {
    if (initial != null) {
      _prepared = initial;
      _info = initial.sourceInfo;
      _plan = initial.plan;
      _phase = SoundImportPhase.ready;
    }
    _preview = io.previewEvents.listen((event) {
      if (!_currentPreview(event.revision)) return;
      _playing = event.playing;
      _message = event.error;
      _notify();
    });
  }
  final SoundImportIO io;
  late final StreamSubscription<SoundPreviewEvent> _preview;
  Future<void> _workTail = Future<void>.value();
  SoundImportPhase _phase = SoundImportPhase.empty;
  AudioImportSource? _source;
  AudioImportInfo? _info;
  SoundClipPlan? _plan;
  PreparedSound? _prepared;
  String? _message;
  bool _playing = false, _disposed = false, _previewStarting = false;
  int _generation = 0, _previewRevision = 0;
  SoundImportPhase get phase => _phase;
  AudioImportSource? get source => _source;
  AudioImportInfo? get info => _info;
  SoundClipPlan? get plan => _plan;
  PreparedSound? get prepared => _prepared;
  String? get message => _message;
  bool get playing => _playing;
  bool get previewStarting => _previewStarting;
  bool get busy => const [
    SoundImportPhase.picking,
    SoundImportPhase.inspecting,
    SoundImportPhase.preparing,
  ].contains(_phase);
  bool _current(int revision) => !_disposed && revision == _generation;
  bool _currentPreview(int revision) =>
      !_disposed && revision == _previewRevision && _prepared != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _work<T>(int revision, Future<T> Function() action) {
    final result = _workTail.then<T>((_) {
      if (!_current(revision)) throw const _StaleImport();
      return action();
    });
    _workTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  String _error(Object error) => error is AudioImportException
      ? error.message
      : 'This audio could not be prepared. Choose another file and try again.';

  Future<void> pickFile() async {
    if (_disposed ||
        _phase == SoundImportPhase.picking ||
        _phase == SoundImportPhase.inspecting) {
      return;
    }
    final revision = ++_generation;
    ++_previewRevision;
    _previewStarting = false;
    final priorPhase = _prepared == null
        ? (_plan == null
              ? SoundImportPhase.empty
              : SoundImportPhase.choosingClip)
        : SoundImportPhase.ready;
    _playing = false;
    _phase = SoundImportPhase.picking;
    _message = null;
    _notify();
    try {
      await io.stop();
      if (!_current(revision)) return;
      final picked = await io.pick();
      if (!_current(revision)) return;
      if (picked == null) {
        _phase = priorPhase;
        _notify();
        return;
      }
      _source = picked;
      _info = null;
      _plan = null;
      _prepared = null;
      _phase = SoundImportPhase.inspecting;
      _notify();
      final metadata = await _work(revision, () => io.inspect(picked));
      if (!_current(revision)) return;
      if (metadata.duration <= Duration.zero ||
          metadata.sampleRate <= 0 ||
          metadata.channels <= 0) {
        throw const AudioImportException('This file has no usable audio.');
      }
      _info = metadata;
      _plan = SoundClipPolicy.plan(total: metadata.duration);
      _phase = SoundImportPhase.choosingClip;
      _notify();
      if (!_plan!.requiresTrim) await prepare();
    } catch (error) {
      if (_current(revision)) {
        _phase = SoundImportPhase.failed;
        _prepared = null;
        _message = _error(error);
        _notify();
      }
    }
  }

  void selectClip(Duration start, Duration end) {
    if (_disposed || _info == null || _source == null) return;
    final plan = SoundClipPolicy.plan(
      total: _info!.duration,
      start: start,
      end: end,
    );
    ++_generation;
    ++_previewRevision;
    _previewStarting = false;
    _playing = false;
    _prepared = null;
    _plan = plan;
    _phase = SoundImportPhase.choosingClip;
    _message = null;
    unawaited(io.stop().catchError((Object _) {}));
    _notify();
  }

  Future<void> prepare() async {
    final source = _source, info = _info, plan = _plan;
    if (_disposed ||
        source == null ||
        info == null ||
        plan == null ||
        _phase == SoundImportPhase.preparing) {
      return;
    }
    if (plan.requiresTrim) {
      _message = 'Choose a clip of 12.8 seconds or less before preparing.';
      _notify();
      return;
    }
    final revision = ++_generation;
    ++_previewRevision;
    _previewStarting = false;
    _prepared = null;
    _playing = false;
    _phase = SoundImportPhase.preparing;
    _message = null;
    _notify();
    try {
      await io.stop();
      if (!_current(revision)) return;
      final samples = await _work(revision, () => io.decode(source, plan));
      if (!_current(revision)) return;
      if (samples.length != plan.frameCount) {
        throw const AudioImportException(
          'The selected clip could not be read completely. Choose a shorter clip.',
        );
      }
      final wave = Pcm16Wave.encodeMono(samples, plan.outputRate!);
      _prepared = PreparedSound(
        name: source.name,
        wave: wave,
        plan: plan,
        sourceInfo: info,
      );
      _phase = SoundImportPhase.ready;
      _notify();
    } catch (error) {
      if (_current(revision)) {
        _phase = SoundImportPhase.failed;
        _message = _error(error);
        _notify();
      }
    }
  }

  Future<void> togglePreview() async {
    if (_disposed || _prepared == null || _previewStarting) return;
    if (_playing) return stopPreview();
    final revision = ++_previewRevision, sound = _prepared!;
    _previewStarting = true;
    _message = null;
    _notify();
    try {
      await io.play(sound.wave, revision: revision);
    } catch (error) {
      if (_currentPreview(revision)) {
        _playing = false;
        _message = 'The preview could not play on this device. Try again.';
        _notify();
      }
    } finally {
      if (_currentPreview(revision)) {
        _previewStarting = false;
        _notify();
      }
    }
  }

  Future<void> stopPreview() async {
    if (_disposed) return;
    final revision = ++_previewRevision;
    _previewStarting = false;
    _playing = false;
    _notify();
    try {
      await io.stop();
    } catch (_) {
      if (_currentPreview(revision)) {
        _message =
            'The preview could not stop cleanly. Close this page and try again.';
        _notify();
      }
    }
  }

  void cancel() {
    if (_disposed) return;
    io.cancelPick();
    ++_generation;
    ++_previewRevision;
    _previewStarting = false;
    _playing = false;
    _prepared = null;
    _phase = _plan == null
        ? SoundImportPhase.empty
        : SoundImportPhase.choosingClip;
    _message = null;
    unawaited(io.stop().catchError((Object _) {}));
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    ++_previewRevision;
    unawaited(_preview.cancel());
    unawaited(io.dispose().catchError((Object _) {}));
    super.dispose();
  }
}

class AudioImportException implements Exception {
  const AudioImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _StaleImport implements Exception {
  const _StaleImport();
}
