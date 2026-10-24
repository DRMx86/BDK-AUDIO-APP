import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/domain/light_power_memory.dart';
import 'package:bdk_led_engine/bdk_led_engine.dart';
import 'package:flutter/material.dart';
import '../../widgets/surface_decoration.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'light_diffusion.dart';
import 'gpu_light_fields.dart';
export 'light_diffusion.dart' show FirmwareLightPainter;

// Additive LED light needs a dark optical surface in either app theme.
// A pale Material surface clips RGB channels and hides changing LED frames.
const _ledGlass = Color(0xff101010);
const _ledOnGlass = Color(0xfff6f8ff);
const _ledAccent = Color(0xff65d9f4);

/// A renderer is created once per screen and disposed by its owner.
/// Frames are 16 × 16 RGBA bytes; meter estimates enter through [render].
abstract interface class LightFrameRenderer {
  void configure(List<int> payload);
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  });
  void dispose();
}

abstract interface class LightFieldRenderer {
  NativeLightFields lightFields(Uint8List pixels, double haloSigma);
}

class _NativeFrames implements LightFrameRenderer, LightFieldRenderer {
  final _engine = NativeLedEngine();
  @override
  void configure(List<int> payload) => _engine.configure(payload);
  @override
  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) => _engine.render(
    demo: demo,
    audio: audio,
    beat: beat,
    audioActive: audioActive,
  );
  @override
  void dispose() => _engine.dispose();
  @override
  NativeLightFields lightFields(Uint8List pixels, double haloSigma) =>
      _engine.lightFields(pixels, haloSigma);
}

class LightScreen extends StatefulWidget {
  const LightScreen({
    super.key,
    required this.settings,
    required this.onChanged,
    this.meter,
    this.connected = false,
    this.rendererFactory,
    this.powerMemory,
    this.previewAudio,
    this.previewBeat = false,
    this.previewBeatAt,
    this.previewAudioActive = false,
  });
  final LedSettings settings;
  final ValueChanged<LedSettings> onChanged;
  final MeterLevels? meter;
  final bool connected;
  final LightFrameRenderer Function()? rendererFactory;
  final LightPowerMemory? powerMemory;
  final List<double>? previewAudio;
  final bool previewBeat, previewAudioActive;

  /// Stable onset identity, independent of subsequent level notifications.
  final DateTime? previewBeatAt;

  @override
  State<LightScreen> createState() => _LightScreenState();
}

enum _Page { home, gallery, ambient }

class _LightScreenState extends State<LightScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _names = [
    'Spectrum Bars',
    'Beat Pulse',
    'Ripple',
    'Fire',
    'Plasma',
    'Matrix Rain',
    'VU Meter',
    'Starfield',
    'Wave',
    'Fireworks',
    'Rainbow Wave',
    'Particle Burst',
    'Kaleidoscope',
    'Frequency Spiral',
    'Bass Reactor',
    'Meteor Shower',
    'Breathing',
    'DNA Helix',
    'Audio Scope',
    'Bouncing Balls',
    'Lava Lamp',
    'Ambient',
  ];
  static String _effectName(int effect) =>
      effect == LedSettings.offEffect ? 'Off' : _names[effect];
  bool _effectSelected(int effect) => effect == LedSettings.offEffect
      ? !widget.settings.lightsOn
      : widget.settings.lightsOn && widget.settings.effect == effect;
  final _scroll = ScrollController();
  late final Ticker _ticker;
  LightFrameRenderer? _renderer;
  ui.Image? _image;
  Uint8List? _pixels;
  bool _hasLight = false;
  Color? _uniformColor;
  ui.FragmentProgram? _diffusionProgram;
  ui.FragmentProgram? _gpuFieldProgram;
  ui.FragmentShader? _diffusionShader;
  final _galleryShaders = <int, ui.FragmentShader>{};
  LightFieldBuilder? get _fieldBuilder {
    final renderer = _renderer;
    return renderer is LightFieldRenderer
        ? (renderer as LightFieldRenderer).lightFields
        : null;
  }

  Future<void> _prepareDiffusion() async {
    try {
      final program = await LedDiffusion.load();
      final gpuFields = await GpuLightFieldRenderer.load();
      if (!mounted) return;
      setState(() {
        _diffusionProgram = program;
        _gpuFieldProgram = gpuFields;
        _diffusionShader = program.fragmentShader();
      });
    } catch (_) {
      // Optical fallback keeps the controls usable on unsupported backends.
    }
  }

  ui.FragmentShader? _galleryShader(int effect) => _diffusionProgram == null
      ? null
      : _galleryShaders.putIfAbsent(
          effect,
          () => _diffusionProgram!.fragmentShader(),
        );
  final _galleryImages =
      <
        int,
        ({
          ui.Image image,
          Uint8List pixels,
          double opacity,
          bool emitting,
          Color? uniformColor,
        })
      >{};
  bool _galleryGenerating = false, _galleryUnavailable = false;
  int _galleryGeneration = 0;
  Timer? _meterExpiry;
  _Page _page = _Page.home;
  Duration _lastFrame = Duration.zero;
  bool _decoding = false;
  bool _playing = true;
  bool _motionInitialized = false;
  bool _reducedMotion = false;
  bool _background = false;
  bool _colorPickerOpen = false;
  bool _meterFresh = false;
  bool _forceFrame = false;
  DateTime? _lastBeatAt;
  DateTime? _queuedBeatAt;
  static const _timingDiagnostics = bool.fromEnvironment(
    'BDK_LIGHT_TIMING_DIAGNOSTICS',
  );
  int _diagnosticFrames = 0, _diagnosticSettings = 0;
  Duration _diagnosticReport = Duration.zero;
  Future<File?>? _diagnosticFile;
  Future<void> _diagnosticWrites = Future<void>.value();
  int _generation = 0;
  final _localPowerMemory = LightPowerMemory();
  LightPowerMemory get _powerMemory => widget.powerMemory ?? _localPowerMemory;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareDiffusion());
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
    _powerMemory.remember(widget.settings);
    _updateMeterFreshness();
    _renderFrame(
      force: true,
    ); // The initial effect is never skipped, including effect zero.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (!_motionInitialized) {
      _playing = !reduced;
      _motionInitialized = true;
    } else if (reduced && !_reducedMotion) {
      _playing = false;
    }
    _reducedMotion = reduced;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant LightScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    var renderSettingsFrame = false;
    _powerMemory.remember(widget.settings);
    if (oldWidget.settings != widget.settings) {
      if (oldWidget.settings.color1 != widget.settings.color1 ||
          oldWidget.settings.color2 != widget.settings.color2 ||
          oldWidget.settings.gradient != widget.settings.gradient ||
          oldWidget.settings.speed != widget.settings.speed) {
        _galleryGeneration++;
        for (final image in _galleryImages.values) {
          image.image.dispose();
        }
        _galleryImages.clear();
        _galleryUnavailable = false;
        if (_page == _Page.gallery) _ensureGalleryImages();
      }
      // Parameter edits feed the existing clock, just like incoming meters.
      // Invalidating every decode and forcing a render here makes a fast drag
      // advance source animation at the input rate instead of 30 FPS.
      final keepClock =
          _ticker.isActive &&
          oldWidget.settings.effect == widget.settings.effect &&
          oldWidget.settings.lightsOn == widget.settings.lightsOn;
      if (!keepClock) _generation++;
      try {
        _renderer?.configure(widget.settings.toPayload());
        if (_timingDiagnostics) _diagnosticSettings++;
        renderSettingsFrame = !keepClock;
      } catch (_) {
        _previewError = 'Firmware preview unavailable on this device';
      }
      _syncAnimation();
    }
    if (oldWidget.meter != widget.meter ||
        oldWidget.connected != widget.connected) {
      _updateMeterFreshness();
    }
    if (oldWidget.previewAudio != widget.previewAudio ||
        oldWidget.previewBeat != widget.previewBeat ||
        oldWidget.previewBeatAt != widget.previewBeatAt ||
        oldWidget.previewAudioActive != widget.previewAudioActive ||
        oldWidget.connected != widget.connected ||
        oldWidget.meter != widget.meter) {
      // Input can arrive faster than the effect clock. Keep its latest values,
      // but advance source state only on a frame tick. New input also must not
      // invalidate an image decode indefinitely on a slower device.
      if (!widget.connected) {
        _lastBeatAt = null;
        _queuedBeatAt = null;
      } else if (widget.meter == null || _audioEstimate == null) {
        _queuedBeatAt = null;
      } else if (oldWidget.previewBeatAt != null &&
          widget.previewBeatAt == null &&
          !widget.previewBeat) {
        _queuedBeatAt = null;
      } else {
        final beatAt =
            widget.previewBeatAt ??
            (widget.previewBeat ? widget.meter?.receivedAt : null);
        if (beatAt != null && beatAt != _lastBeatAt) {
          _queuedBeatAt = beatAt;
        }
      }
      if (oldWidget.connected != widget.connected) {
        _generation++;
        _renderFrame(force: true);
      }
      _syncAnimation();
    }
    // A forced effect-change frame must see any simultaneous input invalidation.
    if (renderSettingsFrame) _renderFrame(force: true);
  }

  List<double>? get _audioEstimate {
    final audio = widget.previewAudio;
    if (!widget.connected ||
        audio == null ||
        audio.length != 7 ||
        audio.any((value) => !value.isFinite)) {
      return null;
    }
    if (widget.meter != null && !_meterFresh) return null;
    return audio;
  }

  bool get _spectrumIdle {
    final meter = widget.meter;
    return widget.connected &&
        widget.settings.effect == 0 &&
        widget.settings.lightsOn &&
        !widget.previewAudioActive &&
        _meterFresh &&
        meter != null &&
        meter.isFresh(DateTime.now()) &&
        meter.values.every((value) => value == 0);
  }

  String get _previewLabel => !widget.connected
      ? 'Preview · firmware demo'
      : _spectrumIdle
      ? 'Preview · idle animation'
      : _audioEstimate != null
      ? 'Audio-reactive preview · estimated'
      : 'Audio-reactive preview · waiting for audio levels';

  void _updateMeterFreshness() {
    _meterExpiry?.cancel();
    final now = DateTime.now();
    final meter = widget.meter;
    _meterFresh = widget.connected && meter != null && meter.isFresh(now);
    if (_meterFresh) {
      final remaining = meter!.receivedAt
          .add(const Duration(milliseconds: 500))
          .difference(now);
      _meterExpiry = Timer(remaining, () {
        if (mounted) setState(() => _meterFresh = false);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    if (_background) {
      _galleryGeneration++;
    } else if (_page == _Page.gallery) {
      _ensureGalleryImages();
    }
    if (!_background) _renderFrame();
    _syncAnimation();
  }

  void _syncAnimation() {
    final active =
        _playing &&
        !_background &&
        !_colorPickerOpen &&
        _page != _Page.gallery &&
        widget.settings.lightsOn &&
        _renderer != null &&
        _previewError == null;
    if (active && !_ticker.isActive) {
      _lastFrame = Duration.zero;
      if (_timingDiagnostics) {
        _diagnosticReport = Duration.zero;
        _diagnosticFrames = 0;
        _diagnosticSettings = 0;
      }
      _ticker.start();
    } else if (!active && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    if (_timingDiagnostics &&
        elapsed - _diagnosticReport >= const Duration(seconds: 1)) {
      debugPrint(
        'BDK_LIGHT_TIMING ms=${(elapsed - _diagnosticReport).inMilliseconds} '
        'frames=$_diagnosticFrames settings=$_diagnosticSettings '
        'effect=${widget.settings.effect} brightness=${widget.settings.brightness}',
      );
      final sample = <String, int>{
        'timestamp_us': DateTime.now().microsecondsSinceEpoch,
        'ms': (elapsed - _diagnosticReport).inMilliseconds,
        'frames': _diagnosticFrames,
        'settings': _diagnosticSettings,
        'effect': widget.settings.effect,
        'brightness': widget.settings.brightness,
      };
      _diagnosticWrites = _diagnosticWrites.then((_) => _writeTiming(sample));
      _diagnosticFrames = 0;
      _diagnosticSettings = 0;
      _diagnosticReport = elapsed;
    }
    if (elapsed - _lastFrame < const Duration(milliseconds: 33)) return;
    _lastFrame = elapsed;
    _renderFrame();
  }

  // Opt-in QA only: some phones suppress release logcat output. Keep the same
  // counters in this app's own external-files directory, with no permission or
  // logging-setting changes. The normal build eliminates this disabled branch.
  Future<void> _writeTiming(Map<String, int> sample) async {
    try {
      final file = await (_diagnosticFile ??= () async {
        if (!Platform.isAndroid) return null;
        final directory = await getExternalStorageDirectory();
        if (directory == null) return null;
        return File(
          '${directory.path}/bdk-light-timing-'
          '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}.jsonl',
        );
      }());
      await file?.writeAsString(
        '${jsonEncode(sample)}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // Diagnostic output never changes preview behavior or readiness.
    }
  }

  void _renderFrame({bool force = false}) {
    if (force) _forceFrame = true;
    if (_decoding ||
        _background ||
        _page == _Page.gallery ||
        _colorPickerOpen ||
        _previewError != null) {
      return;
    }
    if (!_playing && !_forceFrame && _image != null) return;
    final generation = _generation;
    try {
      if (_renderer == null) {
        _renderer = (widget.rendererFactory ?? _NativeFrames.new)();
        _renderer!.configure(widget.settings.toPayload());
      }
      final audio = _audioEstimate;
      final idle = _spectrumIdle;
      final receivedAt =
          _queuedBeatAt ??
          widget.previewBeatAt ??
          (widget.previewBeat ? widget.meter?.receivedAt : null);
      final beatAge = receivedAt == null
          ? null
          : DateTime.now().difference(receivedAt);
      final beat =
          !idle &&
          audio != null &&
          widget.meter != null &&
          receivedAt != null &&
          beatAge != null &&
          !beatAge.isNegative &&
          beatAge.inMilliseconds < 500 &&
          receivedAt != _lastBeatAt;
      if (beat) _lastBeatAt = receivedAt;
      _queuedBeatAt = null;
      // Existing meter-derived inputs are an estimate, not physical LED frames.
      // The effects themselves are still the unchanged portable source classes.
      final pixels = _renderer!.render(
        demo: !widget.connected || idle,
        audio: widget.connected && !idle
            ? audio ?? const [0.0, 0.0, 0.0, -60.0, -60.0, -60.0, 0.0]
            : null,
        beat: beat,
        audioActive: !idle && audio != null && widget.previewAudioActive,
      );
      if (_timingDiagnostics) _diagnosticFrames++;
      if (pixels.length != 1024) throw StateError('Expected 16 × 16 RGBA');
      var emitting = false;
      for (var index = 0; index < pixels.length; index += 4) {
        if (pixels[index] != 0 ||
            pixels[index + 1] != 0 ||
            pixels[index + 2] != 0) {
          emitting = true;
          break;
        }
      }
      final uniform = uniformLightColor(pixels);
      _decoding = true;
      ui.decodeImageFromPixels(pixels, 16, 16, ui.PixelFormat.rgba8888, (
        image,
      ) {
        if (!mounted) {
          image.dispose();
          return;
        }
        _decoding = false;
        if (generation != _generation) {
          image.dispose();
          _renderFrame();
          return;
        }
        final previous = _image;
        _forceFrame = false;
        setState(() {
          _image = image;
          _pixels = pixels;
          _hasLight = emitting;
          _uniformColor = uniform;
        });
        previous?.dispose();
      }, rowBytes: 64);
    } catch (_) {
      _decoding = false;
      _previewError = 'Firmware preview unavailable on this device';
      _ticker.stop();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _generation++;
    _galleryGeneration++;
    _diffusionShader?.dispose();
    for (final shader in _galleryShaders.values) {
      shader.dispose();
    }
    _galleryShaders.clear();
    WidgetsBinding.instance.removeObserver(this);
    _meterExpiry?.cancel();
    _ticker.dispose();
    _scroll.dispose();
    _image?.dispose();
    for (final image in _galleryImages.values) {
      image.image.dispose();
    }
    _galleryImages.clear();
    _renderer?.dispose();
    super.dispose();
  }

  void _go(_Page page) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _page = page);
    if (page == _Page.gallery) {
      _ensureGalleryImages();
    } else {
      _galleryGeneration++;
    }
    _syncAnimation();
  }

  bool _galleryCurrent(int generation) =>
      mounted &&
      !_background &&
      _page == _Page.gallery &&
      generation == _galleryGeneration;

  void _ensureGalleryImages() {
    if (_galleryGenerating ||
        _galleryImages.length == 22 ||
        _galleryUnavailable ||
        _background) {
      return;
    }
    _galleryGenerating = true;
    unawaited(_generateGalleryImages(++_galleryGeneration));
  }

  Future<void> _generateGalleryImages(int generation) async {
    LightFrameRenderer? renderer;
    final settings = widget.settings;
    try {
      renderer = (widget.rendererFactory ?? _NativeFrames.new)();
      if (identical(renderer, _renderer)) {
        throw StateError('Renderer factory must return a fresh instance');
      }
      for (var effect = 0; effect < 22; effect++) {
        if (!_galleryCurrent(generation)) return;
        if (_galleryImages.containsKey(effect)) continue;
        renderer.configure(
          settings.copyWith(effect: effect, brightness: 85).toPayload(),
        );
        Uint8List? representative;
        var bestEnergy = -1;
        // Select an energetic real frame, including Beat Pulse's actual flash.
        // This is a bounded native demo sampling pass, not an effect simulation.
        for (var sample = 0; sample < 72; sample++) {
          final pixels = renderer.render(demo: true);
          if (pixels.length != 1024) {
            throw StateError('Expected square RGBA frame');
          }
          var energy = 0;
          for (var i = 0; i < pixels.length; i += 4) {
            energy += pixels[i] + pixels[i + 1] + pixels[i + 2];
          }
          if (energy > bestEnergy) {
            bestEnergy = energy;
            representative = Uint8List.fromList(pixels);
          }
        }
        final decoded = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          representative!,
          16,
          16,
          ui.PixelFormat.rgba8888,
          decoded.complete,
          rowBytes: 64,
        );
        final image = await decoded.future;
        if (!_galleryCurrent(generation)) {
          image.dispose();
          return;
        }
        // Sparse patterns otherwise disappear under the gallery's subdued
        // treatment. Give low-energy representatives bounded extra exposure;
        // dense patterns keep their existing contrast behind the labels.
        final opacity = (.2 * 16384 / math.max(1, bestEnergy)).clamp(.2, .6);
        setState(
          () => _galleryImages[effect] = (
            image: image,
            pixels: representative!,
            opacity: opacity,
            emitting: bestEnergy > 0,
            uniformColor: uniformLightColor(representative),
          ),
        );
        await SchedulerBinding.instance.endOfFrame;
      }
    } catch (_) {
      if (_galleryCurrent(generation)) _galleryUnavailable = true;
    } finally {
      if (renderer != null && !identical(renderer, _renderer)) {
        renderer.dispose();
      }
      _galleryGenerating = false;
      if (mounted &&
          _page == _Page.gallery &&
          !_background &&
          !_galleryUnavailable &&
          _galleryImages.length < 22) {
        _ensureGalleryImages();
      }
    }
  }

  void _select(int effect) {
    if (effect != LedSettings.offEffect &&
        !MediaQuery.disableAnimationsOf(context)) {
      setState(() => _playing = true);
    }
    widget.onChanged(
      effect == LedSettings.offEffect
          ? _powerMemory.restore(widget.settings).copyWith(brightness: 0)
          : widget.settings.copyWith(effect: effect),
    );
    _go(effect == 21 ? _Page.ambient : _Page.home);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _page == _Page.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_Page.home);
      },
      child: SingleChildScrollView(
        key: ValueKey(_page),
        controller: _scroll,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: switch (_page) {
                _Page.home => _home(context),
                _Page.gallery => _gallery(context),
                _Page.ambient => _ambient(context),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(
    BuildContext context,
    String title, {
    bool back = false,
    bool playback = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (back)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _go(_Page.home),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Light'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (playback)
              Tooltip(
                message: _playing ? 'Pause preview' : 'Play preview',
                excludeFromSemantics: true,
                child: MergeSemantics(
                  child: Semantics(
                    key: const ValueKey('preview-playback'),
                    label: _playing ? 'Pause preview' : 'Play preview',
                    toggled: _playing,
                    child: TextButton.icon(
                      onPressed: _previewError != null
                          ? null
                          : () {
                              setState(() {
                                _playing = !_playing;
                                _generation++;
                              });
                              _renderFrame();
                              _syncAnimation();
                            },
                      icon: Icon(
                        _playing ? Icons.pause : Icons.play_arrow,
                        size: 20,
                      ),
                      label: const ExcludeSemantics(child: Text('Preview')),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _preview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _previewLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            key: const ValueKey('led-artwork'),
            height: 300,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: _ledGlass),
                if (_image != null)
                  FirmwareLightView(
                    key: ValueKey('optics-${widget.settings.effect}'),
                    paintKey: const ValueKey('led-core'),
                    image: _image,
                    pixels: _pixels,
                    fieldBuilder: _fieldBuilder,
                    gpuProgram: _gpuFieldProgram,
                    opacity: 1,
                    shader: _diffusionShader,
                    titleShade: true,
                    hasEmission: _hasLight,
                    uniformColor: _uniformColor,
                    willChange: _playing,
                  ),
                Positioned(
                  left: 20,
                  right: 20,
                  top: 18,
                  child: Text(
                    _effectName(widget.settings.effect),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 12),
                      ],
                    ),
                  ),
                ),
                if (_previewError != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _previewError!,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: _ledOnGlass),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _brightness(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Lights on',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Semantics(
              label: 'Lights on',
              child: Switch(
                key: const ValueKey('lights-power'),
                value: widget.settings.lightsOn,
                onChanged: (value) {
                  widget.onChanged(
                    value
                        ? _powerMemory.restore(widget.settings)
                        : widget.settings.copyWith(brightness: 0),
                  );
                },
              ),
            ),
          ],
        ),
        _PercentageSlider(
          label: 'Brightness',
          controlKey: const ValueKey('brightness'),
          value: widget.settings.isOff ? 0 : widget.settings.brightness,
          onChanged: (value) => widget.onChanged(
            (value > 0 && widget.settings.isOff
                    ? _powerMemory.restore(widget.settings)
                    : widget.settings)
                .copyWith(brightness: value),
          ),
        ),
      ],
    ),
  );

  Widget _home(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(context, 'Light'),
      _preview(context),
      const SizedBox(height: 18),
      _brightness(context),
      const SizedBox(height: 16),
      _ActionRow(
        title: 'Choose an effect',
        subtitle: _effectName(widget.settings.effect),
        icon: Icons.grid_view,
        onTap: () => _go(_Page.gallery),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final effect in [0, 1, 21])
            ChoiceChip(
              key: ValueKey('quick-$effect'),
              label: Text(
                effect == 0
                    ? 'Spectrum'
                    : effect == 1
                    ? 'Beat pulse'
                    : 'Ambient',
              ),
              selected: widget.settings.effect == effect,
              onSelected: (_) => _select(effect),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
      if (widget.settings.effect == 21) ...[
        const SizedBox(height: 12),
        _ActionRow(
          title: 'Customize Ambient',
          subtitle: 'Colors, blend, and movement',
          icon: Icons.palette_outlined,
          onTap: () => _go(_Page.ambient),
        ),
      ],
      const SizedBox(height: 16),
      _meters(context),
    ],
  );

  Widget _gallery(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(context, 'Choose an effect', back: true, playback: false),
      Text(
        'Choose a light pattern. Ambient opens its color controls.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
          final columns = largeText || constraints.maxWidth < 260
              ? 1
              : constraints.maxWidth > 580
              ? 3
              : 2;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final effect in [
                for (var effect = 0; effect < _names.length; effect++) effect,
                LedSettings.offEffect,
              ])
                SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 14) / columns,
                  child: OutlinedButton(
                    key: ValueKey('effect-$effect'),
                    onPressed: () => _select(effect),
                    clipBehavior: Clip.antiAlias,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: _ledGlass,
                      side: BorderSide(
                        color: _effectSelected(effect)
                            ? _ledAccent
                            : Colors.transparent,
                        width: _effectSelected(effect) ? 2 : 0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(21),
                      ),
                    ),
                    child: Semantics(
                      selected: _effectSelected(effect),
                      child: SizedBox(
                        height: largeText ? 202 : 174,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (effect != LedSettings.offEffect)
                              FirmwareLightView(
                                key: ValueKey('gallery-optics-$effect'),
                                paintKey: ValueKey('effect-preview-$effect'),
                                image: _galleryImages[effect]?.image,
                                pixels: _galleryImages[effect]?.pixels,
                                fieldBuilder: _fieldBuilder,
                                gpuProgram: _gpuFieldProgram,
                                shader: _galleryShader(effect),
                                hasEmission:
                                    _galleryImages[effect]?.emitting ?? false,
                                uniformColor:
                                    _galleryImages[effect]?.uniformColor,
                                opacity: _galleryImages[effect]?.opacity ?? .2,
                              ),
                            Positioned(
                              top: 22,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: SizedBox(
                                  width: 78,
                                  height: 78,
                                  child: CustomPaint(
                                    painter: _EffectSymbolPainter(
                                      effect: effect,
                                      color: _effectSelected(effect)
                                          ? _ledAccent
                                          : _ledOnGlass,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 16,
                              child: Text(
                                _effectName(effect),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: _ledOnGlass,
                                    ),
                              ),
                            ),
                            if (_effectSelected(effect))
                              Positioned(
                                right: 12,
                                top: 12,
                                child: Icon(
                                  Icons.check,
                                  size: 20,
                                  color: _ledAccent,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _ambient(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(context, 'Ambient colors', back: true),
      _preview(context),
      const SizedBox(height: 18),
      _brightness(context),
      const SizedBox(height: 16),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ColorRow(
              controlKey: const ValueKey('primary-color'),
              label: 'Primary color',
              color: widget.settings.color1,
              onTap: () => _pickColor(true),
            ),
            const SizedBox(height: 10),
            _ColorRow(
              controlKey: const ValueKey('secondary-color'),
              label: 'Secondary color',
              color: widget.settings.color2,
              onTap: () => _pickColor(false),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int>(
              key: ValueKey('gradient-${widget.settings.gradient}'),
              initialValue: widget.settings.gradient,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Color blend',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var i = 0; i < 5; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      const [
                        'Solid',
                        'Horizontal',
                        'Vertical',
                        'Radial',
                        'Diagonal',
                      ][i],
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  widget.onChanged(widget.settings.copyWith(gradient: value));
                }
              },
            ),
            const SizedBox(height: 24),
            _PercentageSlider(
              label: 'Movement speed',
              controlKey: const ValueKey('speed'),
              value: widget.settings.speed,
              onChanged: (value) =>
                  widget.onChanged(widget.settings.copyWith(speed: value)),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _pickColor(bool primary) async {
    _colorPickerOpen = true;
    _syncAnimation();
    final color = await showDialog<int>(
      context: context,
      builder: (context) => _ColorDialog(
        initial: primary ? widget.settings.color1 : widget.settings.color2,
      ),
    );
    if (!mounted) return;
    _colorPickerOpen = false;
    _syncAnimation();
    if (color == null) return;
    widget.onChanged(
      primary
          ? widget.settings.copyWith(color1: color)
          : widget.settings.copyWith(color2: color),
    );
  }

  Widget _meters(BuildContext context) {
    final values = widget.meter?.values;
    return ExpansionTile(
      title: const Text('Audio activity'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _meterFresh
              ? 'Received from speaker'
              : widget.connected
              ? 'Waiting for fresh audio levels'
              : 'Connect your speaker to see audio levels',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Text('Level · 0–100%', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 16,
          children: [
            for (var i = 0; i < 3; i++)
              SizedBox(
                width: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${const [30, 60, 100][i]} Hz'),
                    const SizedBox(height: 4),
                    Text(
                      _meterFresh && values != null ? '${values[i]}%' : '—',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    ExcludeSemantics(
                      child: LinearProgressIndicator(
                        value: _meterFresh && values != null
                            ? values[i].clamp(0, 100) / 100
                            : 0,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: bdkSurfaceDecoration(
      context,
      radius: 22,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
    ),
    child: child,
  );
}

class _PercentageSlider extends StatefulWidget {
  const _PercentageSlider({
    required this.label,
    required this.controlKey,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final Key controlKey;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  State<_PercentageSlider> createState() => _PercentageSliderState();
}

class _PercentageSliderState extends State<_PercentageSlider> {
  bool _dragging = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
          Text(
            '${widget.value}%',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      MergeSemantics(
        child: Semantics(
          label: widget.label,
          child: Slider(
            key: widget.controlKey,
            value: widget.value.toDouble(),
            min: 0,
            max: 100,
            // Keep one-percent keyboard/accessible steps while idle, and
            // follow a held pointer without discrete-value thumb easing.
            divisions: _dragging ? null : 100,
            semanticFormatterCallback: (value) => '${value.round()} percent',
            onChangeStart: (_) => setState(() => _dragging = true),
            onChangeEnd: (_) => setState(() => _dragging = false),
            onChanged: (value) => widget.onChanged(value.round()),
          ),
        ),
      ),
    ],
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Panel(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.controlKey,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final Key controlKey;
  final String label;
  final int color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: controlKey,
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 64),
      padding: const EdgeInsets.all(14),
    ),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Color(0xff000000 | color),
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              Text(
                '#${color.toRadixString(16).padLeft(6, '0').toUpperCase()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial});
  final int initial;
  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late int _color = widget.initial;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose a color'),
    scrollable: true,
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in [
                0x65D9F4,
                0xBCABFF,
                0x85E2C3,
                0xFFB176,
                0xFF5E84,
                0x4584FF,
                0xFFFFFF,
                0xFFCF54,
              ])
                Semantics(
                  label: 'Color ${color.toRadixString(16).toUpperCase()}',
                  selected: _color == color,
                  child: InkWell(
                    key: ValueKey(
                      'color-${color.toRadixString(16).toUpperCase()}',
                    ),
                    onTap: () => setState(() => _color = color),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Color(0xff000000 | color),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _color == color
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: _color == color ? 3 : 1,
                        ),
                      ),
                      child: _color == color
                          ? const Icon(Icons.check, color: Colors.black)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          for (var channel = 0; channel < 3; channel++) ...[
            Text(const ['Red', 'Green', 'Blue'][channel]),
            MergeSemantics(
              child: Semantics(
                label: const ['Red', 'Green', 'Blue'][channel],
                child: Slider(
                  value: ((_color >> (16 - channel * 8)) & 255).toDouble(),
                  max: 255,
                  divisions: 255,
                  semanticFormatterCallback: (value) => '${value.round()}',
                  onChanged: (value) => setState(() {
                    final shift = 16 - channel * 8;
                    _color =
                        (_color & ~(255 << shift)) | (value.round() << shift);
                  }),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _color),
        child: const Text('Use color'),
      ),
    ],
  );
}

/// Static semantic illustrations for choosing an effect, not simulated LED frames.
class _EffectSymbolPainter extends CustomPainter {
  const _EffectSymbolPainter({required this.effect, required this.color});
  final int effect;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 80);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), ink);
    void circle(double x, double y, double radius, {bool solid = false}) =>
        canvas.drawCircle(Offset(x, y), radius, solid ? fill : ink);
    void wave(double y) => canvas.drawPath(
      Path()
        ..moveTo(9, y)
        ..cubicTo(18, y - 30, 30, y - 30, 40, y)
        ..cubicTo(50, y + 30, 62, y + 30, 71, y),
      ink,
    );
    switch (effect) {
      case LedSettings.offEffect:
        canvas.drawArc(
          const Rect.fromLTWH(16, 16, 48, 48),
          -math.pi / 3,
          5 * math.pi / 3,
          false,
          ink,
        );
        line(40, 9, 40, 36);
      case 0:
        ink.strokeWidth = 6;
        for (var i = 0; i < 5; i++) {
          line(
            14 + i * 13,
            58,
            14 + i * 13,
            const [38.0, 22.0, 31.0, 16.0, 43.0][i],
          );
        }
      case 1:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(20, 20, 40, 40),
            const Radius.circular(8),
          ),
          Paint()..color = color.withValues(alpha: .18),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(20, 20, 40, 40),
            const Radius.circular(8),
          ),
          ink,
        );
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(
            40 + 29 * math.cos(a),
            40 + 29 * math.sin(a),
            40 + 36 * math.cos(a),
            40 + 36 * math.sin(a),
          );
        }
      case 2:
        for (final r in [7.0, 18.0, 29.0]) {
          circle(40, 40, r);
        }
      case 3:
        canvas.drawPath(
          Path()
            ..moveTo(42, 8)
            ..cubicTo(46, 26, 64, 31, 61, 50)
            ..cubicTo(58, 75, 18, 77, 18, 49)
            ..cubicTo(18, 36, 28, 29, 34, 19)
            ..cubicTo(33, 33, 38, 38, 42, 41)
            ..cubicTo(48, 31, 46, 18, 42, 8)
            ..close(),
          ink,
        );
      case 4:
        wave(30);
        wave(42);
        wave(54);
      case 5:
        ink.strokeWidth = 5;
        for (var x = 0; x < 3; x++) {
          for (var y = 0; y < 4; y++) {
            final top = 13 + x % 2 * 7 + y * 13;
            line(20 + x * 20, top.toDouble(), 20 + x * 20, top + 6.0);
          }
        }
      case 6:
        ink.strokeWidth = 5;
        for (var y = 0; y < 5; y++) {
          line(23, 61 - y * 9, 33, 61 - y * 9);
        }
        for (var y = 0; y < 4; y++) {
          line(47, 61 - y * 9, 57, 61 - y * 9);
        }
      case 7:
        for (final star in [
          const Offset(26, 26),
          const Offset(56, 48),
          const Offset(23, 63),
        ]) {
          final r = star.dy > 60 ? 5.0 : 12.0;
          canvas.drawPath(
            Path()
              ..moveTo(star.dx, star.dy - r)
              ..lineTo(star.dx + r * .3, star.dy - r * .3)
              ..lineTo(star.dx + r, star.dy)
              ..lineTo(star.dx + r * .3, star.dy + r * .3)
              ..lineTo(star.dx, star.dy + r)
              ..lineTo(star.dx - r * .3, star.dy + r * .3)
              ..lineTo(star.dx - r, star.dy)
              ..lineTo(star.dx - r * .3, star.dy - r * .3)
              ..close(),
            ink,
          );
        }
      case 8:
        wave(35);
        wave(47);
      case 9:
        circle(40, 40, 5, solid: true);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(
            40 + 16 * math.cos(a),
            40 + 16 * math.sin(a),
            40 + 32 * math.cos(a),
            40 + 32 * math.sin(a),
          );
        }
      case 10:
        ink.strokeWidth = 5;
        for (final r in [28.0, 18.0, 8.0]) {
          canvas.drawArc(
            Rect.fromCircle(center: const Offset(40, 58), radius: r),
            math.pi,
            math.pi,
            false,
            ink,
          );
        }
      case 11:
        circle(40, 40, 5, solid: true);
        for (var i = 0; i < 5; i++) {
          final a = i * math.pi * 2 / 5;
          circle(
            40 + 27 * math.cos(a),
            40 + 27 * math.sin(a),
            i.isEven ? 4 : 5,
          );
        }
      case 12:
        final p = Path();
        for (var i = 0; i < 6; i++) {
          final a = -math.pi / 2 + i * math.pi / 3;
          final point = Offset(40 + 29 * math.cos(a), 40 + 29 * math.sin(a));
          if (i == 0) {
            p.moveTo(point.dx, point.dy);
          } else {
            p.lineTo(point.dx, point.dy);
          }
          line(40, 40, point.dx, point.dy);
        }
        p.close();
        canvas.drawPath(p, ink);
        circle(40, 40, 10);
      case 13:
        final p = Path();
        for (var i = 0; i <= 60; i++) {
          final a = i * .15,
              r = 3 + i * .45,
              x = 40 + r * math.cos(a),
              y = 40 + r * math.sin(a);
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        canvas.drawPath(p, ink);
      case 14:
        circle(40, 40, 10, solid: true);
        circle(40, 40, 22);
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(40, 40), radius: 32),
          -.5,
          .99,
          false,
          ink,
        );
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(40, 40), radius: 32),
          math.pi - .5,
          .99,
          false,
          ink,
        );
      case 15:
        line(16, 58, 44, 30);
        line(25, 67, 58, 34);
        line(27, 23, 35, 15);
        circle(47, 27, 5, solid: true);
        circle(61, 31, 4, solid: true);
      case 16:
        circle(40, 40, 15);
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(40, 40), radius: 30),
          -.8,
          1.6,
          false,
          ink,
        );
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(40, 40), radius: 30),
          math.pi - .8,
          1.6,
          false,
          ink,
        );
      case 17:
        canvas.drawPath(
          Path()
            ..moveTo(25, 10)
            ..cubicTo(65, 26, 15, 54, 55, 70),
          ink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(55, 10)
            ..cubicTo(15, 26, 65, 54, 25, 70),
          ink,
        );
        for (var i = 0; i < 5; i++) {
          final y = 17 + i * 12.0;
          line(i.isEven ? 31 : 27, y, i.isEven ? 49 : 53, y);
        }
      case 18:
        canvas.drawPath(
          Path()
            ..moveTo(8, 41)
            ..lineTo(21, 41)
            ..lineTo(28, 22)
            ..lineTo(38, 61)
            ..lineTo(48, 18)
            ..lineTo(56, 41)
            ..lineTo(72, 41),
          ink,
        );
      case 19:
        circle(20, 51, 7, solid: true);
        circle(40, 28, 9);
        circle(63, 44, 6, solid: true);
        line(10, 68, 70, 68);
      case 20:
        canvas.drawPath(
          Path()
            ..moveTo(18, 63)
            ..cubicTo(7, 47, 37, 45, 30, 29)
            ..cubicTo(24, 12, 50, 2, 56, 20)
            ..cubicTo(62, 39, 35, 39, 46, 55)
            ..cubicTo(58, 73, 28, 79, 18, 63)
            ..close(),
          ink,
        );
        canvas.drawOval(
          const Rect.fromLTWH(16, 9, 12, 16),
          Paint()..color = color.withValues(alpha: .4),
        );
      case 21:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(14, 20, 52, 40),
            const Radius.circular(20),
          ),
          ink,
        );
        circle(29, 40, 9, solid: true);
        canvas.drawCircle(
          const Offset(51, 40),
          9,
          Paint()..color = color.withValues(alpha: .3),
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EffectSymbolPainter oldDelegate) =>
      oldDelegate.effect != effect || oldDelegate.color != color;
}
