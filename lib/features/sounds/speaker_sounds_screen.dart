import 'dart:async';
import 'dart:math' as math;
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/features/transfers/sound_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'sound_import_controller.dart';
import 'wav_audio.dart';

const _slotNames = ['Startup', 'Pairing', 'Connected', 'Volume limit'];
const _slotDescriptions = [
  'Plays when the speaker turns on.',
  'Plays when the speaker enters pairing mode.',
  'Plays when Bluetooth audio connects.',
  'Plays when the maximum volume is reached.',
];

/// Content-only list; the host supplies its Scaffold and heading. Controllers
/// belong to this widget State, including while an individual editor is open.
class SpeakerSoundsScreen extends StatefulWidget {
  const SpeakerSoundsScreen({
    super.key,
    required this.session,
    required this.speaker,
    required this.allowChanges,
    required this.importIOFactory,
    this.initialSounds = const {},
    this.onPrepared,
  });
  final SpeakerSession? session;
  final SpeakerState speaker;
  final bool allowChanges;
  final SoundImportIO Function() importIOFactory;
  final Map<int, PreparedSound> initialSounds;
  final Future<void> Function(int, PreparedSound)? onPrepared;
  @override
  State<SpeakerSoundsScreen> createState() => _SpeakerSoundsScreenState();
}

class _SpeakerSoundsScreenState extends State<SpeakerSoundsScreen>
    with WidgetsBindingObserver {
  final _imports = <int, SoundImportController>{};
  final _lastPrepared = <int, PreparedSound>{};
  final _saveErrors = <int, String>{};
  final _confirmedUploads = <int, PreparedSound>{};
  final _uploadedSlots = <int>{};
  SoundTransferController? _transfer;
  late final ValueNotifier<_SoundsAccess> _access;
  late bool _receiptConnected;
  String? _receiptDeviceId;
  int _connectionEpoch = 0;
  bool _closing = false, _refreshQueued = false, _editorOpen = false;
  SpeakerState get _speaker => widget.session?.state.value ?? widget.speaker;
  _SoundsAccess get _currentAccess => _SoundsAccess(
    _speaker,
    widget.allowChanges && _transfer != null,
    _transfer?.state.value ?? const SoundTransferState(),
    Map.unmodifiable(_saveErrors),
    Map.unmodifiable(_confirmedUploads),
    Set.unmodifiable(_uploadedSlots),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _receiptConnected = _speaker.connected;
    _receiptDeviceId = _speaker.deviceId;
    _attachTransfer();
    _access = ValueNotifier(_currentAccess);
  }

  void _attachTransfer() {
    final session = widget.session;
    if (session == null) return;
    _transfer = SoundTransferController(
      session: session,
      allowChanges: widget.allowChanges,
    );
    _transfer!.state.addListener(_refresh);
    session.state.addListener(_refresh);
  }

  void _refresh() {
    if (_closing || !mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_refreshQueued) {
        _refreshQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _refreshQueued = false;
          _refresh();
        });
      }
      return;
    }
    final current = _speaker;
    if (current.connected != _receiptConnected ||
        current.deviceId != _receiptDeviceId) {
      _receiptConnected = current.connected;
      _receiptDeviceId = current.deviceId;
      _connectionEpoch++;
      _confirmedUploads.clear();
      _uploadedSlots.clear();
    }
    _access.value = _currentAccess;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant SpeakerSoundsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.allowChanges != widget.allowChanges) {
      oldWidget.session?.state.removeListener(_refresh);
      _transfer?.state.removeListener(_refresh);
      _transfer?.dispose();
      _transfer = null;
      _attachTransfer();
    }
    if (oldWidget.speaker.connected && !widget.speaker.connected) {
      _stopPreviews();
      unawaited(_transfer?.onAudioDisconnected() ?? Future<void>.value());
    }
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopPreviews();
  }

  void _stopPreviews() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      scheduleMicrotask(_stopPreviews);
      return;
    }
    for (final controller in _imports.values) {
      unawaited(controller.stopPreview());
    }
  }

  SoundImportController _import(int slot) => _imports.putIfAbsent(slot, () {
    final initial = widget.initialSounds[slot];
    if (initial != null) _lastPrepared[slot] = initial;
    final controller = SoundImportController(
      widget.importIOFactory(),
      initial: initial,
    );
    controller.addListener(() {
      if (_closing) return;
      final sound = controller.prepared;
      if (sound != null && !identical(_lastPrepared[slot], sound)) {
        _lastPrepared[slot] = sound;
        _saveErrors.remove(slot);
        _confirmedUploads.remove(slot);
        unawaited(_persist(slot, sound));
      }
      _refresh();
    });
    return controller;
  });
  Future<void> _persist(int slot, PreparedSound sound) async {
    try {
      await widget.onPrepared?.call(slot, sound);
    } catch (_) {
      if (!_closing && identical(_imports[slot]?.prepared, sound)) {
        _saveErrors[slot] =
            'The clip is ready, but saving this local draft failed.';
        _refresh();
      }
    }
  }

  Future<void> _open(int slot) async {
    if (_editorOpen || _closing) return;
    _editorOpen = true;
    _stopPreviews();
    final controller = _import(slot);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _SoundEditor(
            slot: slot,
            controller: controller,
            access: _access,
            onUpload: (sound) async {
              if (!_currentAccess.canChange || _transfer == null) return;
              final epoch = _connectionEpoch;
              final result = await _transfer!.upload(
                soundType: slot,
                wav: sound.wave,
              );
              if (!_closing &&
                  epoch == _connectionEpoch &&
                  _speaker.connected &&
                  result == SoundTransferResult.completed) {
                _confirmedUploads[slot] = sound;
                _uploadedSlots.add(slot);
                _refresh();
              }
            },
            onDelete: () async {
              if (!_currentAccess.canChange || _transfer == null) return;
              final result = await _transfer!.delete(slot);
              if (result == SoundTransferResult.completed) {
                _confirmedUploads.remove(slot);
                _uploadedSlots.remove(slot);
              }
              _refresh();
            },
            onCancelTransfer: () => _transfer?.cancel() ?? Future<void>.value(),
          ),
        ),
      );
    } finally {
      _editorOpen = false;
      if (!_closing) await controller.stopPreview();
    }
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.session?.state.removeListener(_refresh);
    _transfer?.state.removeListener(_refresh);
    _transfer?.dispose();
    _stopPreviews();
    for (final controller in _imports.values) {
      controller.dispose();
    }
    _access.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = _access.value, colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        if (!access.canChange)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              widget.allowChanges
                  ? 'Import and preview here. Connect a speaker to upload sounds.'
                  : 'Local preview only. Speaker changes are unavailable.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Play sounds',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    access.speaker.connected
                        ? (access.muted ? 'Muted on speaker' : 'Sounds enabled')
                        : 'Speaker status unavailable',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 48,
              child: Semantics(
                label: 'Play speaker notification sounds',
                child: Switch(
                  key: const ValueKey('speaker-sounds-switch'),
                  value: !access.muted,
                  onChanged: access.canChange && !access.transfer.busy
                      ? (value) => unawaited(_transfer!.setMuted(!value))
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (access.transfer.operation == SoundTransferOperation.mute) ...[
          const SizedBox(height: 12),
          if (access.transfer.busy) const _BusyLine('Updating speaker sounds…'),
          if (access.transfer.message != null)
            Text(
              access.transfer.message!,
              style: TextStyle(color: colors.error),
            ),
        ],
        const SizedBox(height: 24),
        const Divider(height: 1),
        for (var slot = 0; slot < 4; slot++) ...[
          _SoundSlotRow(
            slot: slot,
            speaker: access.speaker,
            presenceUnconfirmed: access.presenceUnconfirmed(slot),
            prepared: _imports.containsKey(slot)
                ? _imports[slot]!.prepared
                : widget.initialSounds[slot],
            onTap: () => unawaited(_open(slot)),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _SoundsAccess {
  const _SoundsAccess(
    this.speaker,
    this.allowChanges,
    this.transfer,
    this.saveErrors,
    this.confirmedUploads,
    this.uploadedSlots,
  );
  final SpeakerState speaker;
  final bool allowChanges;
  final SoundTransferState transfer;
  final Map<int, String> saveErrors;
  final Map<int, PreparedSound> confirmedUploads;
  final Set<int> uploadedSlots;
  bool get canChange => allowChanges && speaker.connected;
  bool get muted => speaker.soundFlags & 0x80 != 0;
  bool custom(int slot) =>
      speaker.connected && speaker.soundFlags & (1 << slot) != 0;
  bool presenceUnconfirmed(int slot) =>
      speaker.connected && uploadedSlots.contains(slot) && !custom(slot);
  bool requiresReplacementPrompt(int slot) =>
      custom(slot) || uploadedSlots.contains(slot);
  String presence(int slot) => !speaker.connected
      ? 'Speaker status unavailable'
      : custom(slot)
      ? 'On speaker · Custom sound'
      : presenceUnconfirmed(slot)
      ? 'On speaker · Sound presence unconfirmed'
      : 'On speaker · No custom sound';
}

class _SoundSlotRow extends StatelessWidget {
  const _SoundSlotRow({
    required this.slot,
    required this.speaker,
    required this.presenceUnconfirmed,
    required this.prepared,
    required this.onTap,
  });
  final int slot;
  final SpeakerState speaker;
  final bool presenceUnconfirmed;
  final PreparedSound? prepared;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final presence = !speaker.connected
        ? 'Speaker status unavailable'
        : speaker.soundFlags & (1 << slot) != 0
        ? 'On speaker · Custom sound'
        : presenceUnconfirmed
        ? 'On speaker · Sound presence unconfirmed'
        : 'On speaker · No custom sound';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 88),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _slotNames[slot],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      presence,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    if (prepared != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Local draft · ${prepared!.name}',
                        style: TextStyle(color: colors.primary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoundEditor extends StatefulWidget {
  const _SoundEditor({
    required this.slot,
    required this.controller,
    required this.access,
    required this.onUpload,
    required this.onDelete,
    required this.onCancelTransfer,
  });
  final int slot;
  final SoundImportController controller;
  final ValueListenable<_SoundsAccess> access;
  final Future<void> Function(PreparedSound) onUpload;
  final Future<void> Function() onDelete, onCancelTransfer;
  @override
  State<_SoundEditor> createState() => _SoundEditorState();
}

class _SoundEditorState extends State<_SoundEditor> {
  bool _editingClip = false, _confirming = false, _remotePending = false;
  SoundImportController get controller => widget.controller;
  _SoundsAccess get access => widget.access.value;
  bool get transferring =>
      access.transfer.busy && access.transfer.soundType == widget.slot;
  @override
  void dispose() {
    final cancelling = transferring;
    // The owner defers UI notifications while route unmount locks the tree.
    unawaited(controller.stopPreview());
    if (cancelling) unawaited(widget.onCancelTransfer());
    super.dispose();
  }

  Future<bool> _confirm({required bool replacing}) async {
    _confirming = true;
    await controller.stopPreview();
    if (!mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          replacing
              ? 'Replace ${_slotNames[widget.slot].toLowerCase()} sound?'
              : 'Remove custom sound?',
        ),
        content: Text(
          replacing
              ? 'An interrupted replacement may lose the current custom sound. Keep the speaker nearby until upload finishes.'
              : 'This removes the custom sound from the speaker. Your local draft stays on this device.',
        ),
        actions: [
          TextButton(
            style: _actionStyle,
            onPressed: () => Navigator.pop(context, false),
            child: Text(replacing ? 'Keep current' : 'Keep custom'),
          ),
          FilledButton(
            style: _actionStyle,
            onPressed: () => Navigator.pop(context, true),
            child: Text(replacing ? 'Replace sound' : 'Remove sound'),
          ),
        ],
      ),
    );
    _confirming = false;
    return approved == true;
  }

  Future<void> _upload() async {
    final sound = controller.prepared;
    if (_remotePending ||
        _confirming ||
        sound == null ||
        !access.canChange ||
        access.transfer.busy) {
      return;
    }
    setState(() => _remotePending = true);
    try {
      await controller.stopPreview();
      if (!mounted || !access.canChange || access.transfer.busy) return;
      if (access.requiresReplacementPrompt(widget.slot) &&
          !await _confirm(replacing: true)) {
        return;
      }
      if (!mounted ||
          !access.canChange ||
          access.transfer.busy ||
          !identical(controller.prepared, sound)) {
        return;
      }
      await widget.onUpload(sound);
    } finally {
      if (mounted) setState(() => _remotePending = false);
    }
  }

  Future<void> _delete() async {
    if (_remotePending ||
        _confirming ||
        !access.canChange ||
        access.transfer.busy ||
        !access.custom(widget.slot)) {
      return;
    }
    setState(() => _remotePending = true);
    try {
      if (!await _confirm(replacing: false) ||
          !mounted ||
          !access.canChange ||
          access.transfer.busy) {
        return;
      }
      await widget.onDelete();
    } finally {
      if (mounted) setState(() => _remotePending = false);
    }
  }

  Future<void> _prepare() async {
    await controller.prepare();
    if (mounted && controller.prepared != null) {
      setState(() => _editingClip = false);
    }
  }

  Future<void> _setExactTimes() async {
    final source = controller.source, plan = controller.plan;
    if (source == null || plan == null) return;
    final values = await showDialog<RangeValues>(
      context: context,
      builder: (_) => _ClipTimesDialog(plan: plan),
    );
    if (!mounted || values == null || !identical(controller.source, source)) {
      return;
    }
    controller.selectClip(
      Duration(microseconds: (values.start * 1000000).round()),
      Duration(microseconds: (values.end * 1000000).round()),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, widget.access]),
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme, sound = controller.prepared;
      final plan = controller.plan;
      final transfer = access.transfer;
      final ownTransfer = transfer.soundType == widget.slot;
      final remote =
          access.canChange &&
          !transfer.busy &&
          !controller.busy &&
          !_remotePending;
      final clipEditing =
          controller.source != null &&
          (_editingClip || sound == null) &&
          !controller.busy;
      return Scaffold(
        appBar: AppBar(title: Text(_slotNames[widget.slot])),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _slotDescriptions[widget.slot],
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      access.presence(widget.slot),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 28),
                    if (transferring) ...[
                      _BusyLine(
                        transfer.phase == SoundTransferPhase.cancelling
                            ? 'Cancelling…'
                            : transfer.uploadCompleted
                            ? 'Checking speaker sound presence…'
                            : transfer.phase == SoundTransferPhase.finishing
                            ? 'Waiting for speaker confirmation…'
                            : transfer.operation ==
                                  SoundTransferOperation.delete
                            ? 'Removing custom sound…'
                            : 'Uploading sound…',
                      ),
                      if (transfer.totalBytes > 0) ...[
                        const SizedBox(height: 20),
                        LinearProgressIndicator(
                          value: transfer.progress,
                          minHeight: 4,
                          semanticsLabel: 'Acknowledged sound bytes',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_size(transfer.acknowledgedBytes)} of ${_size(transfer.totalBytes)} acknowledged',
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        transfer.uploadCompleted
                            ? 'Upload is confirmed. You can stop this separate status check.'
                            : 'Cancel disconnects speaker controls. Leaving this page cancels too.',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: _actionStyle,
                        onPressed:
                            transfer.phase == SoundTransferPhase.cancelling
                            ? null
                            : () => unawaited(widget.onCancelTransfer()),
                        child: Text(
                          transfer.uploadCompleted
                              ? 'Stop status check'
                              : transfer.operation ==
                                    SoundTransferOperation.upload
                              ? 'Cancel upload'
                              : 'Cancel operation',
                        ),
                      ),
                    ] else ...[
                      if (controller.busy) ...[
                        _BusyLine(switch (controller.phase) {
                          SoundImportPhase.picking => 'Choose an audio file…',
                          SoundImportPhase.inspecting => 'Reading audio…',
                          _ => 'Preparing your clip…',
                        }),
                        const SizedBox(height: 12),
                        TextButton(
                          style: _actionStyle,
                          onPressed: controller.cancel,
                          child: const Text('Cancel preparation'),
                        ),
                      ] else ...[
                        if (sound != null) ...[
                          Text(
                            'Local draft',
                            style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            sound.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_time(sound.plan.duration)} · Mono PCM16 · ${_rate(sound.plan.outputRate!)} · ${_size(sound.wave.length)}',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          if (sound.plan.isExcerpt) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Excerpt · ${_time(sound.plan.start)}–${_time(sound.plan.end)} of ${_time(sound.sourceInfo.duration)}',
                            ),
                          ],
                          if (sound.plan.lowerRate) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Reduced sample rate to fit the 200 KiB limit.',
                            ),
                          ],
                          if (controller.source == null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Pick the original file again to edit its clip.',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            style: _actionStyle,
                            onPressed: controller.previewStarting
                                ? null
                                : () => unawaited(controller.togglePreview()),
                            icon: Icon(
                              controller.playing
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(
                              controller.previewStarting
                                  ? 'Starting preview…'
                                  : controller.playing
                                  ? 'Stop preview'
                                  : 'Preview locally',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Uses this device’s audio output. Preview does not upload the clip.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          if (controller.source != null && !clipEditing)
                            TextButton(
                              style: _actionStyle,
                              onPressed: () =>
                                  setState(() => _editingClip = true),
                              child: const Text('Adjust clip'),
                            ),
                          const SizedBox(height: 16),
                        ] else if (!clipEditing) ...[
                          Text(
                            'Choose your sound',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Import audio, preview your clip, then upload it to this slot.',
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (clipEditing && plan != null) ...[
                          Text(
                            plan.requiresTrim
                                ? 'Choose a short clip'
                                : 'Selected clip',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Choose up to 12.8 seconds. Short notification sounds work best.',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${_time(plan.start)}–${_time(plan.end)} · ${_time(plan.duration)} selected',
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 56),
                            child: RangeSlider(
                              values: RangeValues(
                                plan.start.inMicroseconds / 1000000,
                                plan.end.inMicroseconds / 1000000,
                              ),
                              max: plan.total.inMicroseconds / 1000000,
                              semanticFormatterCallback: (value) =>
                                  '${value.toStringAsFixed(1)} seconds',
                              labels: RangeLabels(
                                _time(plan.start),
                                _time(plan.end),
                              ),
                              onChanged: (values) {
                                if (values.end - values.start < 0.001) return;
                                controller.selectClip(
                                  Duration(
                                    microseconds: (values.start * 1000000)
                                        .round(),
                                  ),
                                  Duration(
                                    microseconds: (values.end * 1000000)
                                        .round(),
                                  ),
                                );
                              },
                            ),
                          ),
                          TextButton(
                            style: _actionStyle,
                            onPressed: () => unawaited(_setExactTimes()),
                            child: const Text('Set exact times'),
                          ),
                          OutlinedButton(
                            style: _actionStyle,
                            onPressed: () => controller.selectClip(
                              Duration.zero,
                              Duration(
                                microseconds: math.min(
                                  plan.total.inMicroseconds,
                                  3000000,
                                ),
                              ),
                            ),
                            child: const Text('Use first 3 seconds'),
                          ),
                          if (!plan.requiresTrim) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Target · ${_rate(plan.outputRate!)} · ${_size(plan.outputBytes!)} · Mono PCM16',
                            ),
                          ],
                          const SizedBox(height: 12),
                          FilledButton(
                            style: _actionStyle,
                            onPressed: plan.requiresTrim
                                ? null
                                : () => unawaited(_prepare()),
                            child: const Text('Prepare clip'),
                          ),
                          const SizedBox(height: 16),
                        ],
                        OutlinedButton.icon(
                          style: _actionStyle,
                          onPressed: () => unawaited(controller.pickFile()),
                          icon: const Icon(Icons.audio_file_outlined),
                          label: Text(
                            controller.source != null || sound != null
                                ? 'Choose another file'
                                : 'Choose audio',
                          ),
                        ),
                      ],
                      if (controller.message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          controller.message!,
                          style: TextStyle(color: colors.error),
                        ),
                      ],
                      if (access.saveErrors[widget.slot] != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          access.saveErrors[widget.slot]!,
                          style: TextStyle(color: colors.error),
                        ),
                      ],
                      const SizedBox(height: 28),
                      const Divider(),
                      const SizedBox(height: 16),
                      if (!access.canChange) ...[
                        Text(
                          access.allowChanges
                              ? 'Connect the speaker to upload your local draft.'
                              : 'Local preview only. Speaker changes are unavailable.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        style: _actionStyle,
                        onPressed: sound != null && remote
                            ? () => unawaited(_upload())
                            : null,
                        child: const Text('Upload to speaker'),
                      ),
                      if (access.custom(widget.slot)) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          style: _actionStyle,
                          onPressed: remote ? () => unawaited(_delete()) : null,
                          child: const Text('Remove custom sound'),
                        ),
                      ],
                      if (ownTransfer &&
                          transfer.phase == SoundTransferPhase.completed &&
                          (transfer.operation !=
                                  SoundTransferOperation.upload ||
                              identical(
                                access.confirmedUploads[widget.slot],
                                sound,
                              ))) ...[
                        const SizedBox(height: 12),
                        Text(
                          transfer.operation == SoundTransferOperation.upload
                              ? 'Upload confirmed by speaker'
                              : 'Custom sound removed from speaker',
                          style: TextStyle(color: colors.primary),
                        ),
                      ],
                      if (ownTransfer && transfer.message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          transfer.message!,
                          style: TextStyle(color: colors.error),
                        ),
                        if (transfer.previousSoundMayBeLost) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'The previous custom sound may already be removed. Reconnect before trying again.',
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ClipTimesDialog extends StatefulWidget {
  const _ClipTimesDialog({required this.plan});
  final SoundClipPlan plan;
  @override
  State<_ClipTimesDialog> createState() => _ClipTimesDialogState();
}

class _ClipTimesDialogState extends State<_ClipTimesDialog> {
  late final TextEditingController _start, _length;
  String? _error;
  @override
  void initState() {
    super.initState();
    _start = TextEditingController(
      text: (widget.plan.start.inMicroseconds / 1000000).toString(),
    );
    _length = TextEditingController(
      text:
          (widget.plan.requiresTrim
                  ? math.min(3.0, widget.plan.duration.inMicroseconds / 1000000)
                  : widget.plan.duration.inMicroseconds / 1000000)
              .toString(),
    );
  }

  @override
  void dispose() {
    _start.dispose();
    _length.dispose();
    super.dispose();
  }

  void _apply() {
    final start = double.tryParse(_start.text.trim().replaceAll(',', '.'));
    final length = double.tryParse(_length.text.trim().replaceAll(',', '.'));
    final total = widget.plan.total.inMicroseconds / 1000000;
    if (start == null ||
        length == null ||
        !start.isFinite ||
        !length.isFinite ||
        start < 0 ||
        length <= 0 ||
        start > total ||
        length > SoundClipPolicy.maximumDuration.inMicroseconds / 1000000 ||
        start + length > total ||
        (length * 1000000).round() < 1) {
      setState(() => _error = 'Choose up to 12.797 seconds within this audio.');
      return;
    }
    Navigator.pop(context, RangeValues(start, start + length));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose clip'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('clip-start-seconds'),
            controller: _start,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Start (seconds)'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('clip-length-seconds'),
            controller: _length,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Length (seconds)'),
            onSubmitted: (_) => _apply(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        style: _actionStyle,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: _actionStyle,
        onPressed: _apply,
        child: const Text('Apply clip'),
      ),
    ],
  );
}

final _actionStyle = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
);

class _BusyLine extends StatelessWidget {
  const _BusyLine(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 20,
        height: 20,
        child: MediaQuery.disableAnimationsOf(context)
            ? const Icon(Icons.more_horiz, size: 20)
            : const CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

String _time(Duration value) =>
    '${(value.inMicroseconds / 1000000).toStringAsFixed(1)} s';
String _size(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KiB';
String _rate(int rate) =>
    '${(rate / 1000).toStringAsFixed(rate % 1000 == 0
        ? 0
        : rate % 100 == 0
        ? 1
        : 2)} kHz';
