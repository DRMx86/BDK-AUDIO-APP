import 'dart:async';
import 'package:flutter/material.dart';
import 'codec_controller.dart';
import 'codec_models.dart';

/// Content-only detail screen. The route owner disposes [controller].
/// Set allowChanges:false as an additional UI guard in Demo/preview builds.
class AudioQualityScreen extends StatefulWidget {
  const AudioQualityScreen({
    super.key,
    required this.controller,
    this.allowChanges = true,
    this.autoLoad = true,
  });
  final CodecController controller;
  final bool allowChanges, autoLoad;
  @override
  State<AudioQualityScreen> createState() => _AudioQualityScreenState();
}

class _AudioQualityScreenState extends State<AudioQualityScreen>
    with WidgetsBindingObserver {
  Timer? _observationExpiry;
  CodecController get controller => widget.controller;
  bool get _changes => widget.allowChanges && controller.allowChanges;
  bool get _editing => _changes && controller.canEdit;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_updated);
    _scheduleObservationExpiry();
    _initialRead();
  }

  void _initialRead() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.autoLoad &&
          controller.snapshot == null &&
          !controller.busy) {
        unawaited(controller.refresh());
      }
    });
  }

  void _updated() {
    _scheduleObservationExpiry();
    if (mounted) setState(() {});
  }

  void _scheduleObservationExpiry() {
    _observationExpiry?.cancel();
    final remaining = controller.observationValidityRemaining;
    if (remaining != null) {
      _observationExpiry = Timer(remaining, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant AudioQualityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_updated);
      controller.addListener(_updated);
      _scheduleObservationExpiry();
      _initialRead();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.autoLoad &&
        !controller.busy) {
      unawaited(controller.refresh());
    }
  }

  @override
  void dispose() {
    _observationExpiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_updated);
    super.dispose();
  }

  Future<void> _action(Future<Object?> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'This choice is no longer available. Refresh audio quality.',
            ),
          ),
        );
      }
    }
  }

  void _select(VoidCallback action) {
    try {
      action();
    } catch (_) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'This preference is no longer available. Refresh audio quality.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final hasCurrent =
        snapshot?.access == CodecAccess.ready && snapshot?.active != null;
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_changes) ...[
                  _notice('Preview only · changes are disabled.'),
                  const SizedBox(height: 16),
                ],
                _current(context, snapshot, hasCurrent),
                if (controller.busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(minHeight: 3),
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(switch (controller.phase) {
                      CodecOperationPhase.submitting =>
                        'Requesting audio preference…',
                      CodecOperationPhase.verifying =>
                        'Checking the current connection…',
                      _ => 'Checking Bluetooth audio…',
                    }, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
                if (hasCurrent &&
                    snapshot!.canApply &&
                    controller.preference != null) ...[
                  const SizedBox(height: 24),
                  _preferences(context, snapshot),
                ] else if (!hasCurrent || snapshot?.canApply == false) ...[
                  const SizedBox(height: 20),
                  _access(context, snapshot),
                ],
                if (!controller.busy && controller.message != null) ...[
                  const SizedBox(height: 18),
                  Semantics(
                    liveRegion: true,
                    child: _notice(controller.message!),
                  ),
                  if (controller.requiresRefresh)
                    TextButton.icon(
                      onPressed: () => _action(controller.refresh),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh current connection'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                _details(context, snapshot),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _current(
    BuildContext context,
    CodecSnapshot? snapshot,
    bool available,
  ) {
    final colors = Theme.of(context).colorScheme;
    final active = snapshot?.active;
    String? name;
    for (final device in snapshot?.devices ?? const <CodecAudioDevice>[]) {
      if (device.id.toLowerCase() ==
          snapshot?.selectedDeviceId?.toLowerCase()) {
        name = device.name;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  'Current connection',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: colors.primary),
                ),
                TextButton.icon(
                  key: const ValueKey('codec-refresh'),
                  onPressed: controller.busy
                      ? null
                      : () => _action(controller.refresh),
                  icon: const Icon(Icons.refresh, size: 19),
                  label: const Text('Refresh'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ],
            ),
            if (available) ...[
              Text(
                active!.codecName,
                key: const ValueKey('current-codec'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  Text(
                    CodecConfiguration.sampleRateLabel(active.sampleRateMask),
                  ),
                  Text(CodecConfiguration.bitDepthLabel(active.bitsMask)),
                  Text(CodecConfiguration.channelLabel(active.channelMask)),
                ],
              ),
              const SizedBox(height: 10),
              if (active.codecType == 4) ...[
                Text(
                  active.ldacQuality == null
                      ? active.cs1 == 0
                            ? 'LDAC quality: Device default'
                            : 'LDAC quality is managed by your device.'
                      : 'LDAC quality: ${active.ldacQuality!.label}',
                ),
              ],
              if (active.lhdcV5Quality != null)
                Text(
                  active.lhdcV5Quality == LhdcV5Quality.adaptive
                      ? 'LHDC V5 quality: Adaptive'
                      : active.lhdcV5NominalTargetKbps != null
                      ? 'LHDC V5 quality: ${active.lhdcV5NominalTargetKbps} kbps target'
                      : 'LHDC V5 quality: Not reported',
                ),
              if (active.nominalTargetKbps != null)
                Text('Nominal target: ${active.nominalTargetKbps} kbps'),
              const Text('Bluetooth bitrate: Not reported by Android.'),
              const SizedBox(height: 12),
              Text(
                name ?? 'Selected audio speaker',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                switch (snapshot?.source) {
                  'direct' => 'Source: Android query',
                  'broadcast' => 'Source: Android broadcast',
                  _ => 'Source: Not reported',
                },
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              Text(
                controller.hasFreshObservation
                    ? 'Read within the last 5 seconds'
                    : 'This reading needs a refresh',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (!controller.hasFreshObservation) ...[
                const SizedBox(height: 12),
                _notice(
                  'Connection information is out of date. Refresh to see current audio quality.',
                ),
              ],
            ] else if (controller.busy)
              const Text('Reading the connected audio device…')
            else
              Text(
                'No current audio quality information',
                style: Theme.of(context).textTheme.titleMedium,
              ),
          ],
        ),
      ),
    );
  }

  Widget _preferences(BuildContext context, CodecSnapshot snapshot) {
    final preference = controller.preference!;
    final qualityChoices =
        preference.codecType == 4 &&
            const [1, 2, 4, 8].contains(preference.sampleRateMask)
        ? snapshot.ldacQualities
        : const <LdacQuality>[];
    final lhdcChoices = controller.lhdcV5Qualities;
    final lhdcSelected =
        preference.lhdcV5Quality ?? snapshot.active?.lhdcV5Quality;
    final lhdcValue = lhdcChoices.contains(lhdcSelected)
        ? lhdcSelected!.wireValue
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Preference', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Choose a supported configuration. Apply checks the current connection before confirming.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        _choice(
          label: 'Codec',
          controlKey: 'codec-selector',
          value: preference.codecType,
          choices: controller.codecTypes,
          labelFor: snapshot.codecName,
          onSelected: controller.selectCodec,
        ),
        const SizedBox(height: 12),
        Text(
          '${CodecConfiguration.sampleRateLabel(preference.sampleRateMask)} · ${CodecConfiguration.bitDepthLabel(preference.bitsMask)} · ${CodecConfiguration.channelLabel(preference.channelMask)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 10, bottom: 16),
          title: const Text('Advanced preferences'),
          children: [
            _choice(
              label: 'Sample rate',
              controlKey: 'rate-selector',
              value: preference.sampleRateMask,
              choices: controller.sampleRates,
              labelFor: CodecConfiguration.sampleRateLabel,
              onSelected: controller.selectSampleRate,
            ),
            const SizedBox(height: 16),
            _choice(
              label: 'Bit depth',
              controlKey: 'depth-selector',
              value: preference.bitsMask,
              choices: controller.bitDepths,
              labelFor: CodecConfiguration.bitDepthLabel,
              onSelected: controller.selectBitDepth,
            ),
            const SizedBox(height: 16),
            _choice(
              label: 'Channels',
              controlKey: 'channel-selector',
              value: preference.channelMask,
              choices: controller.channelModes,
              labelFor: CodecConfiguration.channelLabel,
              onSelected: controller.selectChannelMode,
            ),
            const SizedBox(height: 14),
            if (qualityChoices.isNotEmpty) ...[
              _choice(
                label: 'Bitrate / quality',
                controlKey: 'quality-selector',
                value:
                    (preference.ldacQuality ?? snapshot.active!.ldacQuality)
                        ?.wireValue ??
                    0,
                choices: [
                  if (preference.ldacQuality == null &&
                      snapshot.active!.ldacQuality == null)
                    0,
                  ...qualityChoices.map((q) => q.wireValue),
                ],
                disabledChoices: const {0},
                labelFor: (value) {
                  if (value == 0) return 'Device default · Choose a bitrate';
                  final quality = LdacQuality.fromWire(value)!;
                  final target = quality.nominalTargetKbps(
                    preference.sampleRateMask,
                  );
                  return target == null ? 'Adaptive' : '$target kbps';
                },
                onSelected: (value) =>
                    controller.selectLdacQuality(LdacQuality.fromWire(value)!),
              ),
              const SizedBox(height: 12),
              const Text(
                'Bitrate values are nominal LDAC targets; actual transmission bitrate is not reported. Apply refreshes capabilities before sending.',
              ),
            ] else if (lhdcChoices.isNotEmpty) ...[
              _choice(
                label: 'Bitrate / quality',
                controlKey: 'quality-selector',
                value: lhdcValue,
                choices: [
                  if (lhdcValue == 0) 0,
                  ...lhdcChoices.map((q) => q.wireValue),
                ],
                disabledChoices: const {0},
                labelFor: (value) => value == 0
                    ? 'Choose a bitrate target'
                    : LhdcV5Quality.fromWire(value)!.label,
                onSelected: (value) => controller.selectLhdcV5Quality(
                  LhdcV5Quality.fromWire(value)!,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'LHDC V5 targets are requests; Android or the speaker may clamp or refuse them. Apply refreshes capabilities before sending. Actual bitrate is not reported.',
              ),
            ] else
              const Text(
                'Quality and bitrate are managed by your device. Refresh to check available quality choices.',
              ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton(
          key: const ValueKey('apply-codec'),
          onPressed: _editing
              ? () => _action(controller.applyPreference)
              : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          child: Text(
            controller.phase == CodecOperationPhase.submitting
                ? 'Applying preference…'
                : controller.phase == CodecOperationPhase.verifying
                ? 'Checking connection…'
                : 'Apply preference',
          ),
        ),
      ],
    );
  }

  Widget _choice({
    required String label,
    required String controlKey,
    required int value,
    required List<int> choices,
    required String Function(int) labelFor,
    required ValueChanged<int> onSelected,
    bool enabled = true,
    Set<int> disabledChoices = const {},
  }) => SizedBox(
    key: ValueKey(controlKey),
    child: DropdownButtonFormField<int>(
      key: ValueKey('$controlKey-$value-${choices.join(',')}'),
      initialValue: choices.contains(value) ? value : null,
      isExpanded: true,
      itemHeight: null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final option in choices)
          DropdownMenuItem(
            value: option,
            enabled: !disabledChoices.contains(option),
            child: Text(labelFor(option)),
          ),
      ],
      onChanged: _editing && enabled
          ? (value) {
              if (value != null) _select(() => onSelected(value));
            }
          : null,
    ),
  );

  Widget _access(BuildContext context, CodecSnapshot? snapshot) {
    final access = snapshot?.access;
    final allowed = _changes && !controller.busy;
    final title = switch (access) {
      CodecAccess.permissionRequired =>
        'Allow Bluetooth access to read the connection.',
      CodecAccess.associationRequired =>
        'Allow companion access for this speaker. Android may still restrict manual selection.',
      CodecAccess.bluetoothOff || CodecAccess.noAudioDevice =>
        'Connect your speaker for Bluetooth audio, then refresh.',
      CodecAccess.initializing =>
        'Android is preparing audio connection information. Refresh in a moment.',
      CodecAccess.ready => 'Your device manages these preferences.',
      CodecAccess.unsupportedPlatform ||
      CodecAccess.apiUnavailable => 'Audio quality is managed by your device.',
      _ => 'Refresh to check the current audio connection.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 14),
        if (access == CodecAccess.permissionRequired)
          FilledButton(
            key: const ValueKey('codec-permission'),
            onPressed: allowed
                ? () => _action(controller.requestPermission)
                : null,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            child: const Text('Allow Bluetooth access'),
          ),
        if (access == CodecAccess.associationRequired)
          FilledButton(
            key: const ValueKey('codec-associate'),
            onPressed: allowed ? () => _action(controller.associate) : null,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            child: const Text('Allow companion access'),
          ),
        if (access != null && access != CodecAccess.unsupportedPlatform) ...[
          OutlinedButton.icon(
            onPressed: allowed
                ? () => _action(controller.openBluetoothSettings)
                : null,
            icon: const Icon(Icons.bluetooth),
            label: const Text('Open Bluetooth settings'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
          ),
          if (access == CodecAccess.noAudioDevice &&
              snapshot!.devices.isNotEmpty &&
              snapshot.selectedDeviceId == null) ...[
            const SizedBox(height: 16),
            const Text('Select your audio speaker'),
            for (final device in snapshot.devices)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton(
                  onPressed: allowed
                      ? () => _action(() => controller.selectDevice(device.id))
                      : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 56),
                  ),
                  child: Text(device.name),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _notice(String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: .25),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(text),
  );

  Widget _details(
    BuildContext context,
    CodecSnapshot? snapshot,
  ) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    title: const Text('About audio quality'),
    childrenPadding: const EdgeInsets.only(bottom: 16),
    children: [
      const Text(
        'Choices come from the connected audio device. Codec preferences may be refused by Android or the speaker.',
      ),
      const SizedBox(height: 10),
      const Text(
        'Bitrate drafts use recognized LDAC or LHDC V5 fields. Apply checks a fresh connection before sending and confirms only matching readback. Actual transmission bitrate is not available here.',
      ),
      if (snapshot?.source == 'broadcast') ...[
        const SizedBox(height: 10),
        const Text(
          'Current information came from a recent device-specific Android broadcast.',
        ),
      ],
      if (snapshot?.reason?.isNotEmpty == true) ...[
        const SizedBox(height: 10),
        Text(snapshot!.reason!),
      ],
      if (controller.errorDetails?.isNotEmpty == true) ...[
        const SizedBox(height: 10),
        Text(controller.errorDetails!),
      ],
    ],
  );
}
