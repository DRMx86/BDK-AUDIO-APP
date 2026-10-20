import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:bdk_audio_decoder/bdk_audio_decoder.dart';
import 'package:file_picker/file_picker.dart';
import 'sound_import_controller.dart';
import 'wav_audio.dart';

class PickedSoundFile {
  const PickedSoundFile({
    required this.name,
    required this.openStream,
    this.length,
  });
  final String name;
  final int? length;
  final Stream<List<int>> Function() openStream;
}

abstract interface class SoundFileDecoder {
  Future<AudioImportInfo> inspect(String path);
  Future<Int16List> decode(String path, SoundClipPlan plan);
}

abstract interface class LocalSoundPlayer {
  Stream<SoundPreviewEvent> get events;
  Future<void> playFile(String path, {required int revision});
  Future<void> stop();
  Future<void> dispose();
}

class SystemSoundImportIO implements SoundImportIO {
  SystemSoundImportIO({
    Future<PickedSoundFile?> Function()? picker,
    SoundFileDecoder? decoder,
    LocalSoundPlayer? player,
    Future<Directory> Function()? createTempDirectory,
    this.maximumInputBytes = 64 * 1024 * 1024,
  }) : _picker = picker ?? _nativePick,
       _decoder = decoder ?? NativeSoundFileDecoder(),
       _player = player ?? AudioplayersSoundPlayer(),
       _createDirectory =
           createTempDirectory ??
           (() => Directory.systemTemp.createTemp('bdk_sound_import_')) {
    if (maximumInputBytes < 1 || maximumInputBytes > 64 * 1024 * 1024) {
      throw ArgumentError('Invalid import file cap.');
    }
  }
  final Future<PickedSoundFile?> Function() _picker;
  final SoundFileDecoder _decoder;
  final LocalSoundPlayer _player;
  final Future<Directory> Function() _createDirectory;
  final int maximumInputBytes;
  final _sources = <String>{}, _previews = <String>{};
  final _activePaths = <String, int>{};
  Future<Directory>? _directoryFuture;
  Future<void>? _disposal;
  Future<void> _previewTail = Future<void>.value();
  Completer<void>? _idle;
  String? _currentSource;
  int _active = 0, _counter = 0, _previewTicket = 0, _pickTicket = 0;
  bool _closed = false;
  @override
  Stream<SoundPreviewEvent> get previewEvents => _player.events;

  static Future<PickedSoundFile?> _nativePick() async {
    final file = await FilePicker.pickFile(
      // Windows' generic filter omits FLAC. Android's custom extension-to-MIME
      // mapping hides valid M4A files, so keep its native audio/* selection.
      // Every selection still passes bounded native format validation.
      type: Platform.isAndroid ? FileType.audio : FileType.custom,
      allowedExtensions: Platform.isAndroid
          ? null
          : Platform.isLinux
          ? const ['wav', 'mp3', 'flac']
          : const ['wav', 'mp3', 'flac', 'm4a', 'aac', 'ogg'],
      dialogTitle: 'Choose a speaker sound',
    );
    if (file == null) return null;
    return PickedSoundFile(
      name: file.name,
      length: file.lengthSync() ?? await file.length(),
      openStream: file.readAsByteStream,
    );
  }

  void _begin() {
    if (_closed) {
      throw const AudioImportException('This sound editor is closed.');
    }
    if (_active++ == 0) _idle = Completer<void>();
  }

  void _end() {
    if (--_active == 0) _idle?.complete();
  }

  Future<Directory> _directory() => _directoryFuture ??= _createDirectory();
  Future<void> _remove(String path) async {
    try {
      if (await File(path).exists()) await File(path).delete();
    } on FileSystemException {
      return;
    }
    _sources.remove(path);
    _previews.remove(path);
  }

  Future<void> _cleanSources() async {
    for (final path in _sources.toList()) {
      if (path != _currentSource && !_activePaths.containsKey(path)) {
        await _remove(path);
      }
    }
  }

  Future<void> _cleanPreviews() async {
    for (final path in _previews.toList()) {
      await _remove(path);
    }
  }

  @override
  Future<AudioImportSource?> pick() async {
    if (_closed) return null;
    final ticket = ++_pickTicket;
    final picked = await _picker();
    if (_closed || ticket != _pickTicket || picked == null) return null;
    if (picked.length != null &&
        (picked.length! <= 0 || picked.length! > maximumInputBytes)) {
      throw const AudioImportException(
        'Choose a nonempty audio file no larger than 64 MiB.',
      );
    }
    _begin();
    File? copy;
    IOSink? sink;
    var retained = false;
    try {
      final directory = await _directory();
      if (_closed || ticket != _pickTicket) return null;
      copy = File(
        '${directory.path}${Platform.pathSeparator}source_${++_counter}.audio',
      );
      sink = copy.openWrite();
      var count = 0;
      await for (final chunk in picked.openStream()) {
        if (_closed || ticket != _pickTicket) return null;
        if (chunk.length > maximumInputBytes - count) {
          throw const AudioImportException(
            'Choose an audio file no larger than 64 MiB.',
          );
        }
        count += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (count == 0) {
        throw const AudioImportException('This file contains no audio data.');
      }
      if (_closed || ticket != _pickTicket) return null;
      _sources.add(copy.path);
      retained = true;
      return AudioImportSource(path: copy.path, name: picked.name);
    } on FileSystemException {
      throw const AudioImportException(
        'This file could not be copied. Choose an available audio file and try again.',
      );
    } finally {
      await sink?.close();
      if (!retained && copy != null) await _remove(copy.path);
      _end();
    }
  }

  @override
  void cancelPick() => ++_pickTicket;

  Future<T> _withSource<T>(
    AudioImportSource source,
    Future<T> Function() action,
  ) async {
    if (!_sources.contains(source.path)) {
      throw const AudioImportException(
        'Choose the source file again to prepare this sound.',
      );
    }
    _begin();
    // Only a source the controller actually adopted may replace the current
    // input. A cancelled picker result must never delete the active source.
    _currentSource = source.path;
    _activePaths.update(source.path, (n) => n + 1, ifAbsent: () => 1);
    try {
      return await action();
    } finally {
      final remaining = _activePaths[source.path]! - 1;
      if (remaining == 0) {
        _activePaths.remove(source.path);
      } else {
        _activePaths[source.path] = remaining;
      }
      await _cleanSources();
      _end();
    }
  }

  @override
  Future<AudioImportInfo> inspect(AudioImportSource source) =>
      _withSource(source, () => _decoder.inspect(source.path));
  @override
  Future<Int16List> decode(AudioImportSource source, SoundClipPlan plan) =>
      _withSource(source, () => _decoder.decode(source.path, plan));

  Future<void> _queuePreview(Future<void> Function() action) {
    final result = _previewTail.then((_) => action());
    _previewTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  @override
  Future<void> play(Uint8List wave, {required int revision}) async {
    final copy = Uint8List.fromList(wave);
    final parsed = Pcm16Wave.decode(
      copy,
      maximumBytes: SoundClipPolicy.maximumBytes,
    );
    if (parsed.channels != 1 ||
        !SoundClipPolicy.rates.contains(parsed.sampleRate)) {
      throw const AudioImportException('Prepare a compatible preview first.');
    }
    _begin();
    final ticket = ++_previewTicket;
    try {
      await _queuePreview(() async {
        if (_closed || ticket != _previewTicket) return;
        await _player.stop();
        await _cleanPreviews();
        if (_closed || ticket != _previewTicket) return;
        final directory = await _directory();
        final file = File(
          '${directory.path}${Platform.pathSeparator}preview_${++_counter}.wav',
        );
        _previews.add(file.path);
        await file.writeAsBytes(copy, flush: true);
        if (_closed || ticket != _previewTicket) {
          await _cleanPreviews();
          return;
        }
        await _player.playFile(file.path, revision: revision);
      });
    } finally {
      _end();
    }
  }

  @override
  Future<void> stop() async {
    if (_closed) return;
    ++_previewTicket;
    _begin();
    try {
      await _queuePreview(() async {
        await _player.stop();
        await _cleanPreviews();
      });
    } finally {
      _end();
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    ++_previewTicket;
    if (_active > 0) await _idle!.future;
    try {
      await _player.dispose();
    } finally {
      for (final path in {..._sources, ..._previews}) {
        await _remove(path);
      }
      if (_directoryFuture != null) {
        try {
          await (await _directoryFuture!).delete();
        } on FileSystemException {
          /* Never recursively delete unknown files. */
        }
      }
    }
  }
}

class NativeSoundFileDecoder implements SoundFileDecoder {
  NativeSoundFileDecoder({this._decoder});
  NativeAudioDecoder? _decoder;
  NativeAudioDecoder get _native => _decoder ??= NativeAudioDecoder();
  @override
  Future<AudioImportInfo> inspect(String path) async {
    try {
      final result = await _native.probeAsync(path);
      return AudioImportInfo(
        duration: result.duration,
        sampleRate: result.sampleRate,
        channels: result.channels,
      );
    } on AudioDecoderException catch (error) {
      throw AudioImportException(error.message);
    }
  }

  @override
  Future<Int16List> decode(String path, SoundClipPlan plan) async {
    try {
      return await _native.decodeSegmentAsync(
        path,
        outputRate: plan.outputRate!,
        startFrame: plan.startFrame!,
        frameCount: plan.frameCount!,
      );
    } on AudioDecoderException catch (error) {
      throw AudioImportException(error.message);
    }
  }
}

class AudioplayersSoundPlayer implements LocalSoundPlayer {
  final _events = StreamController<SoundPreviewEvent>.broadcast(sync: true);
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposal;
  AudioPlayer? _player;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  int _generation = 0;
  bool _closed = false;
  @override
  Stream<SoundPreviewEvent> get events => _events.stream;
  Future<void> _queue(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _closePlayer() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop().timeout(const Duration(seconds: 15));
    } finally {
      await player.dispose().timeout(const Duration(seconds: 15));
    }
  }

  @override
  Future<void> playFile(String path, {required int revision}) {
    if (_closed) {
      return Future.error(
        const AudioImportException('This preview is closed.'),
      );
    }
    final generation = ++_generation;
    return _queue(() async {
      await _closePlayer();
      if (_closed || generation != _generation) return;
      final player = _player = AudioPlayer();
      bool current() =>
          !_closed && generation == _generation && identical(player, _player);
      void failed(Object error) {
        if (current()) {
          _events.add(
            SoundPreviewEvent(
              revision,
              error: 'The preview could not play. Try again.',
            ),
          );
        }
      }

      _subscriptions.add(
        player.onPlayerStateChanged.listen((state) {
          if (current()) {
            _events.add(
              SoundPreviewEvent(
                revision,
                playing: state == PlayerState.playing,
              ),
            );
          }
        }, onError: failed),
      );
      _subscriptions.add(
        player.onPlayerComplete.listen((_) {
          if (current()) _events.add(SoundPreviewEvent(revision));
        }, onError: failed),
      );
      _subscriptions.add(player.eventStream.listen((_) {}, onError: failed));
      await player
          .setReleaseMode(ReleaseMode.stop)
          .timeout(const Duration(seconds: 15));
      if (!current()) return;
      await player
          .play(
            DeviceFileSource(path),
            ctx: AudioContextConfig(
              focus: AudioContextConfigFocus.duckOthers,
            ).build(),
          )
          .timeout(const Duration(seconds: 15));
      if (!current()) await _closePlayer();
    });
  }

  @override
  Future<void> stop() {
    if (_closed) return Future.value();
    ++_generation;
    return _queue(_closePlayer);
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    ++_generation;
    try {
      await _queue(_closePlayer);
    } finally {
      await _events.close();
    }
  }
}
