import 'dart:async';
import 'package:flutter/material.dart';
import 'connection/speaker_session.dart';
import 'connection/speaker_setup_controller.dart';
import 'platform/audio_connection_adapter.dart';
import 'features/pairing/speaker_pairing_screen.dart';
import 'domain/speaker_state.dart';
import 'features/light/light_screen.dart';
import 'features/light/meter_preview.dart';
import 'features/sound/widgets/tone_controls.dart';
import 'features/sound/widgets/preset_shape.dart';
import 'features/sound/widgets/sound_options_panel.dart';
import 'persistence/profile_store.dart';
import 'theme.dart';
import 'features/codec/audio_quality_screen.dart';
import 'features/codec/codec_adapter.dart';
import 'features/codec/codec_controller.dart';
import 'features/codec/audio_config_summary_controller.dart';
import 'features/codec/audio_config_summary.dart';
import 'features/sounds/sound_draft_store.dart';
import 'features/sounds/sound_import_controller.dart';
import 'features/sounds/sound_import_io.dart';
import 'features/sounds/speaker_sounds_screen.dart';
import 'features/imports/bounded_file_picker.dart';
import 'features/presets/preset_import.dart';
import 'features/presets/preset_import_screen.dart';
import 'features/presets/preset_name_dialog.dart';
import 'features/presets/profile_mutations.dart';
import 'features/updates/firmware_update_screen.dart';
import 'features/updates/ota_transfer_controller.dart';
import 'features/app_info/app_info_screen.dart';
import 'domain/light_power_memory.dart';
import 'widgets/surface_decoration.dart';
import 'widgets/connected_controls_reveal.dart';

class BdkApp extends StatefulWidget {
  const BdkApp({
    super.key,
    this.session,
    this.store,
    this.initialProfiles = const ProfileData(),
    this.setup,
    this.initialDemoMode = false,
    this.previewOnly = false,
    this.codecAdapterFactory,
    this.soundDraftStore,
    this.initialSounds = const {},
    this.soundImportIOFactory,
    this.soundDraftWarning,
    this.presetFilePicker,
    this.profileWarning,
    this.updateFilePicker,
  });
  final SpeakerSession? session;
  final ProfileStore? store;
  final ProfileData initialProfiles;
  final SpeakerSetupController? setup;
  final bool initialDemoMode;
  final bool previewOnly;
  final CodecAdapter Function()? codecAdapterFactory;
  final SoundDraftStore? soundDraftStore;
  final Map<int, PreparedSound> initialSounds;
  final SoundImportIO Function()? soundImportIOFactory;
  final String? soundDraftWarning;
  final BoundedFilePicker? presetFilePicker;
  final String? profileWarning;
  final BoundedFilePicker? updateFilePicker;
  @override
  State<BdkApp> createState() => _BdkAppState();
}

class _BdkAppState extends State<BdkApp> with WidgetsBindingObserver {
  late ProfileData profiles;
  late final Map<int, PreparedSound> _soundDrafts;
  bool _localSoundRouteOpen = false, _soundWarningShown = false;
  int _localDetailDepth = 0;
  Future<void> _profileTail = Future<void>.value();
  OtaTransferController? _otaTransfer;
  bool? _otaAllowChanges;
  late SpeakerState speaker;
  late EqGains eq;
  late LedSettings led;
  LightPowerMemory _lightPowerMemory = LightPowerMemory();
  String? _lightPowerDeviceId;
  late int flags;
  int destination = 0;
  String? selected = 'balanced';
  ThemeMode mode = ThemeMode.system;
  final _details = ValueNotifier(0);
  final _navigator = GlobalKey<NavigatorState>();
  final _pending = <String>{};
  final _revisions = <String, int>{};
  late bool _showSetup, _demoMode;
  bool _foreground = true;
  final _meterPreview = MeterPreviewProcessor();
  PreviewAudioSample _previewSample = PreviewAudioSample.silent;
  late final AudioConfigSummaryController _audioSummary;
  bool _audioQualityOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    profiles = widget.initialProfiles;
    _soundDrafts = Map<int, PreparedSound>.of(widget.initialSounds);
    mode = switch (profiles.theme) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    speaker = widget.session?.state.value ?? const SpeakerState();
    eq = speaker.eq;
    led = speaker.led;
    _lightPowerMemory.remember(led);
    _lightPowerDeviceId = speaker.deviceId;
    flags = speaker.controlFlags;
    _previewSample = _meterPreview.update(speaker.meter, now: DateTime.now());
    _demoMode = widget.initialDemoMode;
    _showSetup = !_demoMode && !speaker.connected;
    _audioSummary = AudioConfigSummaryController(
      adapter: (widget.codecAdapterFactory ?? SystemCodecAdapter.new)(),
    );
    selected = _matchingProfile(eq);
    widget.session?.state.addListener(_updateSpeaker);
    widget.setup?.addListener(_updateSetup);
    _syncSetupActivity();
  }

  void _syncSetupActivity() {
    widget.setup?.setActive(
      _foreground && (_showSetup || (!_demoMode && speaker.connected)),
    );
    _syncAudioSummary();
  }

  void _syncAudioSummary() {
    final setup = widget.setup;
    final id = setup == null
        ? speaker.deviceId
        : setup.audioReady
        ? setup.selectedAudioId
        : null;
    final matched =
        speaker.connected &&
        id != null &&
        id.toLowerCase() == speaker.deviceId?.toLowerCase();
    _audioSummary.configure(
      deviceId: matched ? id : null,
      active:
          matched &&
          !_showSetup &&
          !_demoMode &&
          _foreground &&
          !_audioQualityOpen,
    );
  }

  void _updateSetup() {
    if (mounted) {
      setState(() {
        if (!_demoMode &&
            !_switchingSpeaker &&
            speaker.connected &&
            widget.setup?.connecting == false) {
          _showSetup = false;
        }
      });
      _details.value++;
      _syncAudioSummary();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _syncSetupActivity();
      if (_showSetup || (!_demoMode && speaker.connected)) {
        unawaited(widget.setup?.refresh());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _syncSetupActivity();
    }
  }

  void _updateSpeaker() {
    if (!mounted) return;
    final next = widget.session!.state.value;
    final lostControls = speaker.connected && !next.connected && !_demoMode;
    if (next.deviceId != speaker.deviceId || !next.connected) {
      _meterPreview.reset();
    }
    if (next.connected && next.deviceId != _lightPowerDeviceId) {
      _lightPowerMemory = LightPowerMemory();
      _lightPowerDeviceId = next.deviceId;
    }
    _previewSample = _meterPreview.update(next.meter, now: DateTime.now());
    setState(() {
      if (next.eq != speaker.eq && !_pending.contains('eq')) {
        eq = next.eq;
        selected = _matchingProfile(eq);
      }
      if (next.led != speaker.led && !_pending.contains('led')) led = next.led;
      // Connecting states contain default LED values, not fresh speaker data.
      if (next.connected) _lightPowerMemory.remember(led);
      if (next.controlFlags != speaker.controlFlags &&
          !_pending.contains('flags')) {
        flags = next.controlFlags;
      }
      speaker = next;
      if (next.connected && !_demoMode && widget.setup?.connecting != true) {
        _showSetup = false;
      } else if (!_demoMode) {
        _showSetup = true;
      }
    });
    _syncSetupActivity();
    _details.value++;
    if (lostControls && !_localSoundRouteOpen && _localDetailDepth == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !speaker.connected &&
            !_demoMode &&
            !_localSoundRouteOpen &&
            _localDetailDepth == 0) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
  }

  @override
  void dispose() {
    _audioSummary.dispose();
    _otaTransfer?.dispose();
    widget.session?.state.removeListener(_updateSpeaker);
    WidgetsBinding.instance.removeObserver(this);
    widget.setup?.removeListener(_updateSetup);
    widget.setup?.setActive(false);
    _details.dispose();
    super.dispose();
  }

  Future<void> _action(
    BuildContext context,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  void _setEq(BuildContext context, EqGains value) {
    final revision = _beginDraft('eq');
    setState(() => eq = value);
    if (speaker.connected && !widget.previewOnly && !_demoMode) {
      unawaited(
        _sendDraft(context, 'eq', revision, () => widget.session!.setEq(value)),
      );
    }
  }

  void _setLed(BuildContext context, LedSettings value) {
    final revision = _beginDraft('led');
    _lightPowerMemory.remember(value);
    setState(() => led = value);
    if (speaker.connected && !widget.previewOnly && !_demoMode) {
      unawaited(
        _sendDraft(
          context,
          'led',
          revision,
          () => widget.session!.setLed(value),
        ),
      );
    }
  }

  void _setFlags(BuildContext context, int value) {
    final revision = _beginDraft('flags');
    setState(() => flags = value);
    if (speaker.connected && !widget.previewOnly && !_demoMode) {
      unawaited(
        _sendDraft(
          context,
          'flags',
          revision,
          () => widget.session!.setControl(value),
        ),
      );
    }
  }

  String? _matchingProfile(EqGains value) {
    final all = [...builtInProfiles, ...profiles.profiles];
    if (all.any((p) => p.id == selected && p.gains == value)) return selected;
    return all.where((p) => p.gains == value).firstOrNull?.id;
  }

  int _beginDraft(String key) {
    final revision = (_revisions[key] ?? 0) + 1;
    _revisions[key] = revision;
    if (speaker.connected && !widget.previewOnly && !_demoMode) {
      _pending.add(key);
    } else {
      _pending.remove(key);
    }
    return revision;
  }

  Future<void> _sendDraft(
    BuildContext context,
    String key,
    int revision,
    Future<void> Function() send,
  ) async {
    try {
      await send();
    } catch (error) {
      if (mounted && context.mounted && _revisions[key] == revision) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted && _revisions[key] == revision) {
        _pending.remove(key);
        final accepted = widget.session!.state.value;
        setState(() {
          switch (key) {
            case 'eq':
              eq = accepted.eq;
              selected = _matchingProfile(eq);
            case 'led':
              led = accepted.led;
              _lightPowerMemory.remember(led);
            case 'flags':
              flags = accepted.controlFlags;
          }
        });
        _details.value++;
      }
    }
  }

  String get profileName => selected == null
      ? 'Custom sound'
      : [
              ...builtInProfiles,
              ...profiles.profiles,
            ].where((p) => p.id == selected).firstOrNull?.name ??
            'Custom sound';
  Future<void> _commitProfiles(ProfileData Function(ProfileData) mutation) {
    final result = _profileTail.then((_) async {
      if (!mounted) throw StateError('This screen is closed.');
      final next = mutation(profiles);
      await widget.store?.save(next);
      if (!mounted) return;
      setState(() {
        profiles = next;
        selected = _matchingProfile(eq);
        mode =
            ThemeMode.values.where((v) => v.name == next.theme).firstOrNull ??
            ThemeMode.system;
      });
      _details.value++;
    });
    _profileTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _save(BuildContext context) async {
    var initial = 'My sound', suffix = 2;
    final names = profiles.profiles.map((p) => p.name).toSet();
    while (names.contains(initial)) {
      initial = 'My sound ${suffix++}';
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => PresetNameDialog(
        title: 'Save your sound',
        initialName: initial,
        existingNames: names,
      ),
    );
    if (name == null || !mounted) return;
    final p = SoundProfile(
      'custom-${DateTime.now().microsecondsSinceEpoch}',
      name,
      eq,
    );
    if (context.mounted) {
      await _action(context, () async {
        await _commitProfiles((current) {
          ProfileMutations.name(name, current.profiles.map((p) => p.name));
          return ProfileData(
            profiles: [...current.profiles, p],
            favorites: current.favorites,
            theme: current.theme,
          );
        });
        if (mounted && eq == p.gains) setState(() => selected = p.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: 'BDK Audio',
    debugShowCheckedModeBanner: false,
    theme: bdkTheme(Brightness.light),
    darkTheme: bdkTheme(Brightness.dark),
    themeMode: mode,
    home: Builder(
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          if (!_soundWarningShown && widget.soundDraftWarning != null) {
            _soundWarningShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(widget.soundDraftWarning!)),
                );
              }
            });
          }
          if (_showSetup) {
            return Scaffold(body: SafeArea(child: _pairing(context)));
          }
          final wide = constraints.maxWidth >= 760;
          final pages = [
            _sound(context),
            LightScreen(
              settings: led,
              powerMemory: _lightPowerMemory,
              onChanged: (v) => _setLed(context, v),
              meter: speaker.meter,
              connected: speaker.connected && !_demoMode,
              previewAudio: _previewSample.values,
              previewBeat: _previewSample.beat,
              previewAudioActive: _previewSample.audioActive,
            ),
            _speaker(context),
          ];
          return _connectedReveal(
            context,
            Scaffold(
              appBar: AppBar(
                title: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'BDK',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        'AUDIO',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  if (constraints.maxWidth < 480 && _demoMode)
                    Semantics(
                      label: 'Demo mode. Pair speaker',
                      button: true,
                      child: Tooltip(
                        message: 'Pair speaker',
                        child: TextButton.icon(
                          onPressed: _openSetup,
                          icon: const Icon(Icons.bluetooth, size: 16),
                          label: const Text('Pair'),
                        ),
                      ),
                    )
                  else if (constraints.maxWidth < 360)
                    IconButton(
                      onPressed: () => speaker.connected
                          ? setState(() => destination = 2)
                          : _openSetup(),
                      tooltip: speaker.connected
                          ? speaker.name
                          : 'Not connected',
                      icon: Icon(
                        speaker.connected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: TextButton.icon(
                        onPressed: () => speaker.connected && !_demoMode
                            ? setState(() => destination = 2)
                            : _openSetup(),
                        icon: Icon(
                          speaker.connected && !_demoMode
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth,
                          size: 16,
                        ),
                        label: Text(
                          _demoMode
                              ? 'Demo · Pair speaker'
                              : speaker.connected
                              ? speaker.name
                              : 'Not connected',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  const SizedBox(width: 10),
                ],
              ),
              body: Column(
                children: [
                  if (speaker.connected && !_demoMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AudioConfigSummary(
                        controller: _audioSummary,
                        onTap: () => unawaited(_audioQuality(context)),
                      ),
                    ),
                  Expanded(
                    child: Row(
                      children: [
                        if (wide)
                          NavigationRail(
                            selectedIndex: destination,
                            onDestinationSelected: (v) =>
                                setState(() => destination = v),
                            labelType: NavigationRailLabelType.all,
                            destinations: const [
                              NavigationRailDestination(
                                icon: Icon(Icons.graphic_eq),
                                label: Text('Sound'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.light_mode_outlined),
                                label: Text('Light'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.speaker_outlined),
                                label: Text('Speaker'),
                              ),
                            ],
                          ),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 850),
                              child: pages[destination],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: destination,
                      onDestinationSelected: (v) =>
                          setState(() => destination = v),
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.graphic_eq),
                          label: 'Sound',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.light_mode_outlined),
                          label: 'Light',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.speaker_outlined),
                          label: 'Speaker',
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    ),
  );
  Widget _heading(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Text(title, style: Theme.of(context).textTheme.headlineLarge),
  );
  Widget _scroll(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
    children: children,
  );
  Widget _row(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback tap,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Card(
      child: ListTile(
        minVerticalPadding: 17,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: tap,
      ),
    ),
  );
  Future<void> _detail(
    BuildContext context,
    String title,
    Widget Function(BuildContext) body,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListenableBuilder(
              listenable: _details,
              builder: (context, _) => body(context),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _sound(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final favorite = builtInProfiles
        .where((p) => profiles.favorites.contains(p.id))
        .take(4)
        .toList();
    return _scroll([
      _heading(context, 'Sound'),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.primary.withValues(alpha: .35)),
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: .13),
              scheme.surfaceContainer,
            ],
          ),
          boxShadow: bdkSurfaceDecoration(context, emphasis: true).boxShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOUR SOUND',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 9),
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  profileName,
                  style: Theme.of(context).textTheme.headlineMedium,
                );
                final shape = SizedBox(
                  width: 110,
                  child: PresetShape(
                    key: const ValueKey('current-preset-shape'),
                    levels: eq.values,
                    large: true,
                  ),
                );
                if (constraints.maxWidth < 230 ||
                    MediaQuery.textScalerOf(context).scale(16) > 22) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), shape],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    shape,
                  ],
                );
              },
            ),
            const SizedBox(height: 7),
            Text(
              widget.previewOnly
                  ? 'Preview changes on this device'
                  : speaker.connected
                  ? '${speaker.name} · ${eq.values.map((v) => v > 0 ? '+$v' : '$v').join(' / ')} levels'
                  : 'Connect your speaker to apply these settings',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          const Text(
            'Choose preset',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          TextButton(
            onPressed: () => _detail(
              context,
              'All presets',
              (ctx) => _presets(ctx, builtInProfiles),
            ),
            child: const Text('All presets'),
          ),
        ],
      ),
      _presetGrid(context, favorite),
      _row(
        context,
        'Equalizer',
        'Shape bass, mid and treble',
        Icons.tune,
        () => _detail(context, 'Equalizer', _equalizer),
      ),
      _row(
        context,
        'Sound options',
        'Bass boost and speaker outputs',
        Icons.settings_input_component,
        () => _detail(context, 'Sound options', _options),
      ),
      _row(
        context,
        'Saved presets',
        '${profiles.profiles.length} personal profiles',
        Icons.bookmark_border,
        () => _localDetail(context, 'Saved presets', (ctx) => _saved(ctx)),
      ),
      if (speaker.message != null)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Text(
            speaker.message!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ]);
  }

  Widget _connectedReveal(BuildContext context, Widget child) {
    return ConnectedControlsReveal(
      animate: speaker.connected && !_demoMode,
      child: child,
    );
  }

  Widget _presetGrid(
    BuildContext context,
    List<SoundProfile> values, {
    bool manage = false,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final cols =
          constraints.maxWidth < (manage ? 620 : 300) ||
              MediaQuery.textScalerOf(context).scale(14) > 22
          ? 1
          : 2;
      final width = (constraints.maxWidth - (cols - 1) * 10) / cols;
      final scheme = Theme.of(context).colorScheme;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final p in values)
            SizedBox(
              width: width,
              child: Semantics(
                selected: selected == p.id,
                button: true,
                child: Material(
                  color: selected == p.id
                      ? scheme.primary.withValues(alpha: .12)
                      : scheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: selected == p.id
                          ? scheme.primary
                          : scheme.outlineVariant,
                      width: selected == p.id ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      setState(() => selected = p.id);
                      _setEq(context, p.gains);
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 112),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (selected == p.id)
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: scheme.primary,
                                  ),
                                if (manage)
                                  PopupMenuButton<_ProfileAction>(
                                    tooltip: 'Manage preset ${p.name}',
                                    icon: const Icon(Icons.more_horiz),
                                    onSelected: (action) => unawaited(
                                      _action(
                                        context,
                                        () => _managePreset(context, p, action),
                                      ),
                                    ),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: _ProfileAction.rename,
                                        child: Text('Rename'),
                                      ),
                                      PopupMenuItem(
                                        value: _ProfileAction.replace,
                                        child: Text('Use current sound'),
                                      ),
                                      PopupMenuItem(
                                        value: _ProfileAction.delete,
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              p.description,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            PresetShape(levels: p.gains.values),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget _presets(BuildContext context, List<SoundProfile> values) => _scroll([
    const Text('Choose the sound that suits your listening.'),
    const SizedBox(height: 20),
    _presetGrid(context, values),
  ]);
  Widget _equalizer(BuildContext context) => StatefulBuilder(
    builder: (context, refresh) => _scroll([
      Text(
        speaker.connected
            ? 'Adjust your speaker sound.'
            : 'Preview your sound. Connect a speaker to apply it.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 20),
      ToneControls(
        levels: eq.values,
        onChanged: (v) {
          selected = null;
          _setEq(context, EqGains(v[0], v[1], v[2]));
          refresh(() {});
        },
      ),
      const SizedBox(height: 22),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 10,
        children: [
          OutlinedButton(
            onPressed: () {
              selected = 'balanced';
              _setEq(context, const EqGains.zero());
              refresh(() {});
            },
            child: const Text('Reset'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await _save(context);
              if (context.mounted) refresh(() {});
            },
            icon: const Icon(Icons.bookmark_add_outlined, size: 19),
            label: const Text('Save preset'),
          ),
        ],
      ),
    ]),
  );
  Widget _options(BuildContext context) => StatefulBuilder(
    builder: (context, refresh) => _scroll([
      SoundOptionsPanel(
        controlFlags: flags,
        onChanged: (v) {
          _setFlags(context, v);
          refresh(() {});
        },
      ),
    ]),
  );
  Widget _saved(BuildContext context) => _scroll([
    if (widget.profileWarning != null) ...[
      Text(widget.profileWarning!),
      const SizedBox(height: 20),
    ],
    if (profiles.profiles.isEmpty) ...[
      const Text('Save your favorite settings from the equalizer.'),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => _detail(context, 'Equalizer', _equalizer),
        child: const Text('Create a preset'),
      ),
    ] else
      _presetGrid(context, profiles.profiles, manage: true),
    const SizedBox(height: 24),
    OutlinedButton.icon(
      onPressed: () => _importPresets(context),
      icon: const Icon(Icons.file_open_outlined),
      label: const Text('Import presets'),
    ),
  ]);

  Future<void> _localDetail(
    BuildContext context,
    String title,
    Widget Function(BuildContext) body,
  ) async {
    _localDetailDepth++;
    try {
      await _detail(context, title, body);
    } finally {
      _localDetailDepth--;
    }
  }

  Future<void> _importPresets(BuildContext context) => _localDetail(
    context,
    'Import presets',
    (_) => PresetImportScreen(
      picker: widget.presetFilePicker ?? BoundedFilePicker(),
      onImport: (incoming) async {
        PresetMerge? merged;
        await _commitProfiles((current) {
          merged = PresetImport.merge(current, incoming);
          return merged!.data;
        });
        return merged!;
      },
    ),
  );
  Future<void> _managePreset(
    BuildContext context,
    SoundProfile profile,
    _ProfileAction action,
  ) async {
    if (action == _ProfileAction.rename) {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => PresetNameDialog(
          title: 'Rename preset',
          initialName: profile.name,
          existingNames: profiles.profiles
              .where((p) => p.id != profile.id)
              .map((p) => p.name)
              .toSet(),
        ),
      );
      if (name != null && mounted) {
        await _commitProfiles(
          (current) => ProfileMutations.rename(current, profile.id, name),
        );
      }
      return;
    }
    final replacing = action == _ProfileAction.replace;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(replacing ? 'Replace preset?' : 'Delete preset?'),
        content: Text(
          replacing
              ? 'Save the current sound as “${profile.name}”?'
              : 'Remove “${profile.name}” from your library? Playback keeps its current sound.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(replacing ? 'Replace preset' : 'Delete preset'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      // The queued write may run after another preset has been selected.
      final confirmedGains = eq;
      await _commitProfiles(
        (current) => replacing
            ? ProfileMutations.replace(current, profile.id, confirmedGains)
            : ProfileMutations.delete(current, profile.id),
      );
    }
  }

  Widget _speaker(BuildContext context) => _scroll([
    _heading(context, 'Speaker'),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Icon(
              Icons.speaker_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    speaker.connected ? speaker.name : 'Your BDK speaker',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    speaker.connected
                        ? 'Connected · ${speaker.firmware.isEmpty ? 'Version unavailable' : speaker.firmware}'
                        : 'Not connected',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 18),
    FilledButton.icon(
      onPressed: _openSetup,
      icon: const Icon(Icons.bluetooth_searching),
      label: Text(speaker.connected ? 'Choose a speaker' : 'Connect speaker'),
    ),
    if (widget.setup?.rememberWarning != null)
      Padding(
        padding: const EdgeInsets.only(top: 15),
        child: Text(widget.setup!.rememberWarning!),
      ),
    if (speaker.message != null)
      Padding(
        padding: const EdgeInsets.only(top: 15),
        child: Text(speaker.message!),
      ),
    _row(
      context,
      'Audio quality',
      'Bluetooth audio connection',
      Icons.high_quality_outlined,
      () => unawaited(_audioQuality(context)),
    ),
    _row(
      context,
      'Appearance',
      'Light, dark or follow your device',
      Icons.contrast,
      () => _detail(context, 'Appearance', _appearance),
    ),
    _row(
      context,
      'Speaker sounds',
      'Startup, pairing and connection sounds',
      Icons.notifications_active_outlined,
      () => unawaited(_speakerSounds(context)),
    ),
    _row(
      context,
      'Firmware update',
      'Local update file',
      Icons.system_update_alt_outlined,
      () => unawaited(_firmwareUpdate(context)),
    ),
    _row(
      context,
      'App info',
      'About BDK Audio',
      Icons.info_outline,
      () => _detail(context, 'App info', (_) => const AppInfoScreen()),
    ),
    if (speaker.connected && !widget.previewOnly)
      _row(
        context,
        'Speaker name',
        speaker.name,
        Icons.edit_outlined,
        () => _rename(context),
      ),
    if (speaker.connected)
      Padding(
        padding: const EdgeInsets.only(top: 18),
        child: OutlinedButton(
          onPressed: () => _action(
            context,
            widget.setup?.disconnectControls ?? widget.session!.disconnect,
          ),
          child: const Text('Disconnect'),
        ),
      ),
  ]);
  bool _switchingSpeaker = false;
  Future<void> _speakerSounds(BuildContext context) async {
    if (_localSoundRouteOpen) return;
    _localSoundRouteOpen = true;
    final allowChanges = !widget.previewOnly && !_demoMode;
    try {
      await _detail(
        context,
        'Speaker sounds',
        (_) => SpeakerSoundsScreen(
          session: widget.session,
          speaker: speaker,
          allowChanges: allowChanges,
          importIOFactory:
              widget.soundImportIOFactory ?? SystemSoundImportIO.new,
          initialSounds: Map<int, PreparedSound>.unmodifiable(_soundDrafts),
          onPrepared: (type, sound) async {
            _soundDrafts[type] = sound;
            await widget.soundDraftStore?.save(type, sound);
          },
        ),
      );
    } finally {
      _localSoundRouteOpen = false;
    }
  }

  Future<void> _audioQuality(BuildContext context) async {
    if (_audioQualityOpen) return;
    final allowChanges = !widget.previewOnly && !_demoMode;
    final deviceId = speaker.deviceId ?? widget.setup?.selectedAudioId;
    final factory = widget.codecAdapterFactory ?? () => SystemCodecAdapter();
    _audioQualityOpen = true;
    _syncAudioSummary();
    try {
      await _detail(
        context,
        'Audio quality',
        (_) => _OwnedAudioQuality(
          adapterFactory: factory,
          deviceId: deviceId,
          allowChanges: allowChanges,
        ),
      );
    } finally {
      _audioQualityOpen = false;
      if (mounted) _syncAudioSummary();
    }
  }

  Future<void> _firmwareUpdate(BuildContext context) {
    final allowChanges = !widget.previewOnly && !_demoMode;
    if (_otaAllowChanges != allowChanges) {
      _otaTransfer?.dispose();
      _otaTransfer = null;
    }
    _otaAllowChanges = allowChanges;
    final session = widget.session;
    if (session != null) {
      _otaTransfer ??= OtaTransferController(
        session: session,
        allowChanges: allowChanges,
      );
    }
    return _localDetail(
      context,
      'Firmware update',
      (_) => FirmwareUpdateScreen(
        picker: widget.updateFilePicker ?? BoundedFilePicker(),
        speaker: speaker,
        allowChanges: allowChanges,
        controller: _otaTransfer,
        onReconnect: () {
          _navigator.currentState?.popUntil((route) => route.isFirst);
          _openSetup();
        },
      ),
    );
  }

  void _openSetup() {
    setState(() {
      _switchingSpeaker = speaker.connected;
      _showSetup = true;
      _demoMode = false;
    });
    _syncSetupActivity();
    widget.setup?.beginDiscovery();
  }

  void _exploreDemo() {
    setState(() {
      _showSetup = false;
      _demoMode = true;
      destination = 0;
    });
    _syncSetupActivity();
    unawaited(() async {
      await widget.setup?.cancel();
      if (widget.session?.state.value.connected == true) {
        await widget.session!.disconnect();
      }
    }());
  }

  Widget _pairing(BuildContext context) {
    final setup = widget.setup;
    final audio =
        setup?.audio ?? const AudioConnectionSnapshot(canVerifyIdentity: false);
    final devices = setup?.controlDevices ?? const [];
    return SpeakerPairingScreen(
      stage: _switchingSpeaker
          ? PairingStage.audio
          : setup?.connecting == true
          ? PairingStage.connecting
          : setup?.audioReady == true
          ? PairingStage.controls
          : PairingStage.audio,
      audioDevices: audio.devices
          .map((d) => PairingAudioDevice(id: d.id, name: d.name))
          .toList(),
      selectedAudioId: setup?.selectedAudioId,
      controlDevices: devices,
      busy:
          setup?.connecting == true ||
          setup?.loading == true ||
          setup?.preparingControls == true ||
          setup?.searching == true,
      searching: setup?.searching ?? false,
      checkingAudio: setup?.checkingAudio ?? false,
      continuousDiscovery: setup?.autoDiscoverEnabled ?? false,
      audioSearchCompleted: setup?.audioSearchCompleted ?? false,
      onRetryAudio: () => setup?.beginDiscovery(),
      permissionRequired: audio.permissionRequired,
      audioVerificationAvailable: audio.canVerifyIdentity,
      searchCompleted: setup?.searchCompleted ?? false,
      message: setup?.message ?? setup?.rememberWarning,
      onOpenBluetoothSettings: () => unawaited(
        setup?.openBluetoothSettings() ??
            _action(
              context,
              const SystemAudioConnectionAdapter().openBluetoothSettings,
            ),
      ),
      onRequestPermission: () => unawaited(setup?.requestPermission()),
      onSelectAudioDevice: (id) => unawaited(
        _action(context, () async {
          if (speaker.connected &&
              speaker.deviceId?.toLowerCase() == id.toLowerCase()) {
            setState(() => _showSetup = false);
            _syncSetupActivity();
            return;
          }
          setup?.selectAudioDevice(id);
          if (speaker.connected) await widget.session!.disconnect();
          if (mounted) setState(() => _switchingSpeaker = false);
        }),
      ),
      onConfirmAudioConnection: () {
        setup?.confirmManagedAudio();
        setState(() => _switchingSpeaker = false);
      },
      onSearchControls: () => unawaited(
        _action(context, () async {
          if (speaker.connected) await widget.session!.disconnect();
          await setup?.searchControls();
        }),
      ),
      onConnectControls: (id) => unawaited(setup?.connectControls(id)),
      onCancel: () {
        unawaited(setup?.cancel());
        if (speaker.connected) {
          setState(() => _showSetup = false);
          _syncSetupActivity();
        }
      },
      onExploreDemo: _exploreDemo,
    );
  }

  Widget _appearance(BuildContext context) => StatefulBuilder(
    builder: (context, refresh) => _scroll([
      RadioGroup<ThemeMode>(
        groupValue: mode,
        onChanged: (value) {
          if (value == null) return;
          unawaited(
            _action(context, () async {
              await _commitProfiles(
                (current) => ProfileData(
                  profiles: current.profiles,
                  favorites: current.favorites,
                  theme: value.name,
                ),
              );
              if (context.mounted) refresh(() {});
            }),
          );
        },
        child: Column(
          children: [
            for (final choice in ThemeMode.values)
              RadioListTile<ThemeMode>(
                title: Text(switch (choice) {
                  ThemeMode.system => 'Follow device',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
                value: choice,
              ),
          ],
        ),
      ),
    ]),
  );
  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: speaker.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Speaker name'),
        content: TextField(controller: controller, maxLength: 31),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (name != null && context.mounted) {
      await _action(context, () => widget.session!.rename(name));
    }
  }
}

enum _ProfileAction { rename, replace, delete }

// The controller must outlive its observing screen through the reverse route
// animation. Create/dispose it with route content, not Navigator.push's future.
class _OwnedAudioQuality extends StatefulWidget {
  const _OwnedAudioQuality({
    required this.adapterFactory,
    required this.deviceId,
    required this.allowChanges,
  });
  final CodecAdapter Function() adapterFactory;
  final String? deviceId;
  final bool allowChanges;
  @override
  State<_OwnedAudioQuality> createState() => _OwnedAudioQualityState();
}

class _OwnedAudioQualityState extends State<_OwnedAudioQuality> {
  late final CodecController _controller;
  @override
  void initState() {
    super.initState();
    _controller = CodecController(
      adapter: widget.adapterFactory(),
      deviceId: widget.deviceId,
      allowChanges: widget.allowChanges,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AudioQualityScreen(
    controller: _controller,
    allowChanges: widget.allowChanges,
  );
}
