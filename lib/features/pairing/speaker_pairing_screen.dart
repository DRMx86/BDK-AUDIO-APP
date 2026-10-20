import 'package:bdk_audio/connection/ble_transport.dart';
import 'package:bdk_audio/widgets/surface_decoration.dart';
import 'package:flutter/material.dart';

import 'speaker_discovery_hero.dart';

enum PairingStage { audio, controls, connecting }

class PairingAudioDevice {
  const PairingAudioDevice({required this.id, required this.name});
  final String id, name;
}

/// One discovery page. Device identity and readiness always come from the caller.
class SpeakerPairingScreen extends StatelessWidget {
  const SpeakerPairingScreen({
    super.key,
    required this.stage,
    this.audioDevices = const [],
    this.selectedAudioId,
    this.controlDevices = const [],
    this.busy = false,
    this.searching = false,
    this.checkingAudio = false,
    this.permissionRequired = false,
    this.audioVerificationAvailable = true,
    this.searchCompleted = false,
    this.audioSearchCompleted = false,
    this.continuousDiscovery = false,
    this.message,
    required this.onOpenBluetoothSettings,
    required this.onRequestPermission,
    required this.onSelectAudioDevice,
    required this.onSearchControls,
    required this.onConnectControls,
    required this.onCancel,
    required this.onExploreDemo,
    this.onConfirmAudioConnection,
    this.onRetryAudio,
  });
  final PairingStage stage;
  final List<PairingAudioDevice> audioDevices;
  final String? selectedAudioId;
  final List<DiscoveredSpeaker> controlDevices;
  final bool busy,
      searching,
      checkingAudio,
      permissionRequired,
      audioVerificationAvailable,
      searchCompleted,
      audioSearchCompleted,
      continuousDiscovery;
  final String? message;
  final VoidCallback onOpenBluetoothSettings,
      onRequestPermission,
      onSearchControls,
      onCancel,
      onExploreDemo;
  final ValueChanged<String> onSelectAudioDevice, onConnectControls;
  final VoidCallback? onConfirmAudioConnection, onRetryAudio;

  bool get _connecting => stage == PairingStage.connecting;
  bool get _checking =>
      !permissionRequired &&
      (checkingAudio || (stage == PairingStage.audio && busy));
  bool get _finding =>
      !permissionRequired &&
      (searching || (stage == PairingStage.controls && busy));
  bool get _working => _connecting || _checking || _finding;
  bool get _persistentHelp =>
      continuousDiscovery &&
      _working &&
      !_connecting &&
      !permissionRequired &&
      (audioSearchCompleted || searchCompleted);
  bool get _hasMessage => message?.trim().isNotEmpty == true;
  bool get _audioSearchEmpty =>
      stage == PairingStage.audio &&
      audioVerificationAvailable &&
      audioSearchCompleted &&
      audioDevices.isEmpty;
  bool get _waitingForAudio =>
      stage == PairingStage.audio &&
      !permissionRequired &&
      audioVerificationAvailable &&
      audioDevices.isEmpty &&
      !audioSearchCompleted &&
      !_hasMessage;

  String? get _selectedName {
    for (final device in audioDevices) {
      if (device.id == selectedAudioId && device.name.trim().isNotEmpty) {
        return device.name;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 840 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24;
        final padding = constraints.maxWidth < 340 ? 16.0 : 24.0;
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 844.0;
        final heroHeight = wide
            ? 460.0
            : (availableHeight * .43).clamp(270.0, 430.0).toDouble();
        final hero = SizedBox(
          key: const ValueKey('pairing-discovery-hero'),
          height: heroHeight,
          child: SpeakerDiscoveryHero(
            active: _working || _waitingForAudio,
            found:
                !_working &&
                !permissionRequired &&
                stage == PairingStage.controls &&
                controlDevices.isNotEmpty,
          ),
        );
        final status = _statusSurface(context);
        return ColoredBox(
          color: colors.surface,
          child: SingleChildScrollView(
            key: const ValueKey('pairing-page-scroll'),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: availableHeight),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padding, 12, padding, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(context),
                        if (wide) ...[
                          const SizedBox(height: 40),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(flex: 6, child: hero),
                              const SizedBox(width: 36),
                              Expanded(flex: 5, child: status),
                            ],
                          ),
                        ] else ...[
                          hero,
                          const SizedBox(height: 8),
                          status,
                        ],
                        if (!_working || _persistentHelp) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: TextButton(
                              key: const ValueKey('pairing-demo'),
                              onPressed: onExploreDemo,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                foregroundColor: colors.onSurfaceVariant,
                              ),
                              child: const Text('Explore Demo'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded, color: colors.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'BDK AUDIO',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        TextButton(
          key: const ValueKey('pairing-cancel'),
          onPressed: onCancel,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: colors.onSurfaceVariant,
          ),
          child: Text(_working ? 'Cancel setup' : 'Close'),
        ),
      ],
    );
  }

  Widget _statusSurface(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final (eyebrow, title, description) = _copy;
    final narrowLargeText =
        MediaQuery.sizeOf(context).width <= 320 &&
        MediaQuery.textScalerOf(context).scale(16) > 24;
    return Container(
      key: const ValueKey('pairing-status-surface'),
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 340 ? 20 : 24),
      decoration: bdkSurfaceDecoration(context, radius: 28, emphasis: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow,
            style: text.labelSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            header: true,
            child: Text(
              title,
              style: text.headlineMedium?.copyWith(
                fontSize: narrowLargeText ? 18 : 28,
                height: 1.12,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: text.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (_hasMessage && message != description) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Text(message!, style: text.bodyMedium),
            ),
          ],
          if (_selectedName != null && stage != PairingStage.audio) ...[
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.bluetooth_audio_rounded,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedName!, style: text.titleSmall),
                      if (!_connecting) ...[
                        const SizedBox(height: 3),
                        Text(
                          audioVerificationAvailable
                              ? 'Bluetooth audio connected'
                              : 'Audio connection confirmed by you',
                          style: text.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
          ..._actions(context),
        ],
      ),
    );
  }

  (String, String, String) get _copy {
    if (_connecting) {
      return (
        'ALMOST THERE',
        'Connecting…',
        'Waiting for verified speaker settings. Keep your speaker nearby.',
      );
    }
    if (permissionRequired) {
      return (
        'BLUETOOTH ACCESS',
        'Let’s find your speaker',
        'Allow Bluetooth access so BDK can find your speaker nearby.',
      );
    }
    if (_persistentHelp) {
      return (
        'STILL LOOKING',
        'Connected to your speaker?',
        stage == PairingStage.audio
            ? 'We’ll keep checking for Bluetooth audio. Connect your speaker in Bluetooth settings.'
            : 'We’ll keep looking nearby. Make sure your speaker is connected for Bluetooth audio.',
      );
    }
    if (_checking) {
      return (
        'BLUETOOTH AUDIO',
        'Checking Bluetooth audio…',
        'Looking for the speaker connected to your device’s audio.',
      );
    }
    if (_finding) {
      return (
        'DISCOVERING NEARBY',
        'Finding your speaker…',
        'Keep your speaker on and close by. This can take a moment.',
      );
    }
    if (stage == PairingStage.controls && controlDevices.isNotEmpty) {
      return (
        'NEARBY SPEAKERS',
        'Speaker found',
        'Choose your speaker to connect its sound and light controls.',
      );
    }
    if (stage == PairingStage.controls && (searchCompleted || _hasMessage)) {
      return (
        'LET’S TRY AGAIN',
        _hasMessage ? 'Let’s reconnect' : 'No speaker found',
        'Keep your speaker close and check its Bluetooth audio connection, then search again.',
      );
    }
    if (stage == PairingStage.controls) {
      return (
        'AUDIO CONNECTED',
        'Find your speaker',
        'Your audio is ready. Find the speaker to connect sound and light controls.',
      );
    }
    if (!audioVerificationAvailable) {
      return (
        'BLUETOOTH AUDIO',
        'Connect your sound',
        'This device cannot check Bluetooth audio. Connect your speaker in Bluetooth settings, then confirm below.',
      );
    }
    if (_audioSearchEmpty) {
      return (
        'LET’S TRY AGAIN',
        'No speaker found',
        'Connect your speaker for Bluetooth audio to make it available here.',
      );
    }
    if (audioDevices.isNotEmpty) {
      return (
        'BLUETOOTH AUDIO',
        'Choose your speaker',
        'Select the Bluetooth audio speaker you want to use.',
      );
    }
    return (
      'BLUETOOTH AUDIO',
      _hasMessage ? 'Connect your speaker' : 'Waiting for your speaker',
      'Turn on your speaker and connect it in Bluetooth settings. We’ll look for it when you return.',
    );
  }

  List<Widget> _actions(BuildContext context) {
    if (_persistentHelp) {
      return [
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('pairing-open-settings'),
          onPressed: onOpenBluetoothSettings,
          style: _primaryStyle(),
          icon: const Icon(Icons.bluetooth_rounded),
          label: const Text('Connect speaker', textAlign: TextAlign.center),
        ),
      ];
    }
    if (_working) return const [];
    if (permissionRequired) {
      return [
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('pairing-permission'),
          onPressed: busy ? null : onRequestPermission,
          style: _primaryStyle(),
          child: const Text(
            'Allow Bluetooth access',
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    if (stage == PairingStage.audio) {
      return [
        const SizedBox(height: 24),
        if (_audioSearchEmpty) ...[
          FilledButton.icon(
            key: const ValueKey('pairing-retry-audio'),
            onPressed: busy ? null : onRetryAudio,
            style: _primaryStyle(),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Search again', textAlign: TextAlign.center),
          ),
          const SizedBox(height: 10),
          _settingsButton(),
        ] else if (!audioVerificationAvailable) ...[
          FilledButton(
            key: const ValueKey('pairing-confirm-audio'),
            onPressed: busy ? null : onConfirmAudioConnection,
            style: _primaryStyle(),
            child: const Text(
              'I connected Bluetooth audio',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          _settingsButton(),
        ] else ...[
          for (final device in audioDevices) ...[
            _DeviceButton(
              controlKey: ValueKey('pairing-audio-${device.id}'),
              name: device.name.trim().isEmpty ? 'Audio speaker' : device.name,
              subtitle: 'Use this Bluetooth audio device',
              onPressed: busy ? null : () => onSelectAudioDevice(device.id),
            ),
            const SizedBox(height: 10),
          ],
          _settingsButton(primary: audioDevices.isEmpty),
        ],
      ];
    }
    if (controlDevices.isNotEmpty) {
      return [
        const SizedBox(height: 24),
        for (var index = 0; index < controlDevices.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          _DeviceButton(
            controlKey: ValueKey('pairing-control-${controlDevices[index].id}'),
            name: controlDevices[index].name.trim().isEmpty
                ? 'Speaker controls'
                : controlDevices[index].name,
            subtitle: 'Connect speaker controls',
            onPressed: busy
                ? null
                : () => onConnectControls(controlDevices[index].id),
          ),
        ],
      ];
    }
    return [
      const SizedBox(height: 24),
      FilledButton.icon(
        key: const ValueKey('pairing-search-controls'),
        onPressed: busy ? null : onSearchControls,
        style: _primaryStyle(),
        icon: const Icon(Icons.search_rounded),
        label: Text(
          searchCompleted || _hasMessage ? 'Search again' : 'Find speaker',
          textAlign: TextAlign.center,
        ),
      ),
      if (searchCompleted || _hasMessage) ...[
        const SizedBox(height: 10),
        _settingsButton(),
      ],
    ];
  }

  Widget _settingsButton({bool primary = false}) {
    const label = Text('Open Bluetooth settings', textAlign: TextAlign.center);
    const icon = Icon(Icons.bluetooth_rounded);
    return primary
        ? FilledButton.icon(
            key: const ValueKey('pairing-open-settings'),
            onPressed: busy ? null : onOpenBluetoothSettings,
            style: _primaryStyle(),
            icon: icon,
            label: label,
          )
        : OutlinedButton.icon(
            key: const ValueKey('pairing-open-settings'),
            onPressed: busy ? null : onOpenBluetoothSettings,
            style: _primaryStyle(),
            icon: icon,
            label: label,
          );
  }

  ButtonStyle _primaryStyle() => FilledButton.styleFrom(
    minimumSize: const Size(48, 56),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

class _DeviceButton extends StatelessWidget {
  const _DeviceButton({
    required this.controlKey,
    required this.name,
    required this.subtitle,
    required this.onPressed,
  });
  final Key controlKey;
  final String name, subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: controlKey,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 80),
      padding: const EdgeInsets.all(16),
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: .3),
    ),
    child: Row(
      children: [
        const Icon(Icons.speaker_outlined, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, size: 20),
      ],
    ),
  );
}
