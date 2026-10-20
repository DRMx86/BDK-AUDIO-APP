import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../domain/speaker_state.dart';
import '../imports/bounded_file_picker.dart';
import 'firmware_image.dart';
import 'ota_transfer_controller.dart';
import 'ota_transfer_state.dart';

Future<FirmwareImage> _decodeUpdate(ImportedFile file, Uint8List? key) =>
    Isolate.run(
      () => FirmwareImage.parse(
        file.bytes,
        encrypted: file.name.toLowerCase().endsWith('.enc'),
        legacyAesKey: key,
      ),
    );

/// File/key UI is route-owned. The host keeps the transfer receipt alive across
/// reconnect navigation and owns disposal of the borrowed controller.
class FirmwareUpdateScreen extends StatefulWidget {
  const FirmwareUpdateScreen({
    super.key,
    required this.picker,
    required this.speaker,
    required this.allowChanges,
    this.controller,
    this.onReconnect,
    this.decode,
  });
  final BoundedFilePicker picker;
  final SpeakerState speaker;
  final bool allowChanges;
  final OtaTransferController? controller;
  final VoidCallback? onReconnect;
  final Future<FirmwareImage> Function(ImportedFile, Uint8List?)? decode;
  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateScreenState();
}

class _FirmwareUpdateScreenState extends State<FirmwareUpdateScreen>
    with WidgetsBindingObserver {
  final _key = TextEditingController(), _expected = TextEditingController();
  ImportedFile? _file;
  FirmwareImage? _image;
  String? _error;
  bool _working = false, _confirming = false;
  int _revision = 0;
  bool get _encrypted => _file?.name.toLowerCase().endsWith('.enc') ?? false;
  bool _current(int revision) => mounted && revision == _revision;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        widget.controller?.state.value.busy == true) {
      unawaited(widget.controller!.cancel());
    }
  }

  @override
  void dispose() {
    _revision++;
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller?.state.value.busy == true) {
      unawaited(widget.controller!.cancel());
    }
    _key.dispose();
    _expected.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    if (_working ||
        _confirming ||
        widget.controller?.state.value.busy == true) {
      return;
    }
    final revision = ++_revision;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final file = await widget.picker.pick(
        maximumBytes: FirmwareImage.maximumBytes + 32,
        extensions: const ['bin', 'enc'],
      );
      if (!_current(revision) || file == null) return;
      setState(() {
        _file = file;
        _image = null;
        _key.clear();
      });
      if (!file.name.toLowerCase().endsWith('.enc')) {
        await _parse(file, revision, null);
      }
    } catch (error) {
      if (_current(revision)) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'This update file could not be read.',
        );
      }
    } finally {
      if (_current(revision)) setState(() => _working = false);
    }
  }

  Future<void> _parse(ImportedFile file, int revision, Uint8List? key) async {
    final image = await (widget.decode ?? _decodeUpdate)(file, key);
    if (!mounted || revision != _revision) return;
    setState(() {
      _image = image;
      _expected.text = image.version;
      _key.clear();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _unlock() async {
    if (_working || _file == null || !_encrypted) return;
    final text = _key.text.trim();
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(text)) {
      setState(() => _error = 'Enter a 64-character hexadecimal key.');
      return;
    }
    final key = Uint8List.fromList(
      List.generate(
        32,
        (i) => int.parse(text.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
    final revision = ++_revision, file = _file!;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _parse(file, revision, key);
    } catch (error) {
      if (_current(revision)) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'This file could not be unlocked.',
        );
      }
    } finally {
      key.fillRange(0, key.length, 0);
      if (_current(revision)) setState(() => _working = false);
    }
  }

  Future<void> _install() async {
    final image = _image, controller = widget.controller;
    if (_working ||
        _confirming ||
        image == null ||
        controller == null ||
        !widget.allowChanges ||
        !controller.canTransfer) {
      return;
    }
    setState(() => _confirming = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Install this update?'),
          content: Text(
            '${image.projectName} · ${image.version}\n\nUse a file from a source you trust. Keep the speaker powered and this app open until the transfer finishes.',
          ),
          actions: [
            TextButton(
              style: _button,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: _button,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Install update'),
            ),
          ],
        ),
      );
      if (!mounted ||
          confirmed != true ||
          !widget.allowChanges ||
          !identical(_image, image) ||
          !controller.canTransfer) {
        return;
      }
      await controller.transfer(image, expectedVersion: _expected.text.trim());
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _sourceInfo() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Update source',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text('Local files'),
            const SizedBox(height: 8),
            const Text(
              'Choose an application .bin file, or an encrypted .enc file with its key.',
            ),
            const SizedBox(height: 20),
            const Text(
              'Online updates need a configured, trusted release source.',
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      if (widget.controller != null) widget.controller!.state,
    ]),
    builder: (context, _) {
      final state = widget.controller?.state.value ?? const OtaTransferState();
      final colors = Theme.of(context).colorScheme, image = _image;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(
            'Current version',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            widget.speaker.connected
                ? (widget.speaker.firmware.isEmpty
                      ? 'Unavailable'
                      : widget.speaker.firmware)
                : 'Connect a speaker to read its version.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (state.transferConfirmed) ...[
            Text(
              state.phase == OtaTransferPhase.versionMatched
                  ? 'Reported version matches'
                  : 'Transfer confirmed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Expected version · ${state.expectedVersion ?? 'Unavailable'}',
            ),
            if (state.reportedVersion != null)
              Text('Reported version · ${state.reportedVersion}'),
            const SizedBox(height: 12),
            const Text(
              'Reconnect to check the speaker’s reported version. File checks do not verify its publisher.',
            ),
            const SizedBox(height: 12),
            if (widget.allowChanges && widget.onReconnect != null)
              OutlinedButton(
                style: _button,
                onPressed: state.busy ? null : widget.onReconnect,
                child: const Text('Reconnect speaker'),
              ),
            FilledButton(
              style: _button,
              onPressed:
                  widget.allowChanges && widget.controller?.canVerify == true
                  ? () => unawaited(widget.controller!.verifyAfterReconnect())
                  : null,
              child: const Text('Check reported version'),
            ),
            const SizedBox(height: 24),
          ],
          if (state.busy) ...[
            Text(switch (state.phase) {
              OtaTransferPhase.starting => 'Preparing speaker…',
              OtaTransferPhase.finishing => 'Waiting for speaker confirmation…',
              OtaTransferPhase.verifying => 'Checking reported version…',
              OtaTransferPhase.aborting => 'Cancelling…',
              _ => 'Sending update…',
            }, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: state.totalBytes > 0 ? state.progress : null,
            ),
            const SizedBox(height: 8),
            Text(
              '${_size(state.attCompletedBytes)} of ${_size(state.totalBytes)} sent',
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              style: _button,
              onPressed: state.phase == OtaTransferPhase.aborting
                  ? null
                  : () => unawaited(widget.controller!.cancel()),
              child: const Text('Cancel transfer'),
            ),
          ] else ...[
            const Text('Choose an update file from a source you trust.'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: _button,
              onPressed: _working || _confirming ? null : _choose,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Choose update file'),
            ),
            if (_file != null) ...[
              const SizedBox(height: 16),
              Text(_file!.name, style: Theme.of(context).textTheme.titleSmall),
            ],
            if (_encrypted && image == null) ...[
              const SizedBox(height: 20),
              Text(
                'Unlock encrypted file',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text('Use the 32-byte AES key supplied with this file.'),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('firmware-aes-key'),
                controller: _key,
                obscureText: true,
                enabled: !_working,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Encryption key',
                  hintText: '64 hexadecimal characters',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: _button,
                onPressed: _working ? null : _unlock,
                child: const Text('Unlock file'),
              ),
            ],
            if (_working) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Reading file…'),
            ],
            if (image != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.task_alt, color: colors.primary),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('File checks passed')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        image.version,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text('${image.projectName} · ${_size(image.sizeBytes)}'),
                    ],
                  ),
                ),
              ),
              ExpansionTile(
                title: const Text('File details'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                children: [
                  Text('ESP32 application · ${image.idfVersion}'),
                  const SizedBox(height: 10),
                  const Text('SHA-256'),
                  Text(image.sha256Hex),
                  const SizedBox(height: 12),
                  const Text(
                    'No publisher signature is available. These checks describe this file, not the bytes installed on a speaker.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _expected,
                    maxLength: 64,
                    decoration: const InputDecoration(
                      labelText: 'Expected speaker version',
                      helperText:
                          'Used for the reported-version check after reconnecting.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!widget.allowChanges)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'File preview only. Speaker updates are unavailable.',
                  ),
                ),
              FilledButton(
                style: _button,
                onPressed:
                    widget.allowChanges &&
                        widget.controller?.canTransfer == true &&
                        !_confirming
                    ? _install
                    : null,
                child: const Text('Install update'),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              style: _button,
              onPressed: _sourceInfo,
              child: const Text('Update source'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: colors.error)),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 16),
            Text(
              state.message!,
              style: TextStyle(
                color: state.errorFamily == null
                    ? colors.onSurfaceVariant
                    : colors.error,
              ),
            ),
          ],
        ],
      );
    },
  );
}

final _button = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
);
String _size(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KiB';
