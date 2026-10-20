import 'dart:isolate';
import 'package:flutter/material.dart';
import '../imports/bounded_file_picker.dart';
import '../sound/widgets/preset_shape.dart';
import '../../persistence/profile_store.dart';
import 'preset_import.dart';

Future<List<SoundProfile>> _decodePresets(ImportedFile file) =>
    Isolate.run(() => PresetImport.parse(file.bytes));

class PresetImportScreen extends StatefulWidget {
  const PresetImportScreen({
    super.key,
    required this.picker,
    required this.onImport,
    this.decode,
  });
  final BoundedFilePicker picker;
  final Future<PresetMerge> Function(List<SoundProfile>) onImport;
  final Future<List<SoundProfile>> Function(ImportedFile)? decode;
  @override
  State<PresetImportScreen> createState() => _PresetImportScreenState();
}

class _PresetImportScreenState extends State<PresetImportScreen> {
  List<SoundProfile> _values = const [];
  Set<String> _selected = {};
  String? _name, _error;
  PresetMerge? _result;
  bool _reading = false, _saving = false;
  int _revision = 0;
  bool _current(int revision) => mounted && revision == _revision;
  @override
  void dispose() {
    _revision++;
    super.dispose();
  }

  Future<void> _choose() async {
    if (_reading || _saving) return;
    final revision = ++_revision;
    setState(() {
      _reading = true;
      _error = null;
      _result = null;
    });
    try {
      final file = await widget.picker.pick(
        maximumBytes: PresetImport.maximumBytes,
        extensions: const ['xml', 'json'],
      );
      if (!_current(revision) || file == null) return;
      final values = await (widget.decode ?? _decodePresets)(file);
      if (!_current(revision)) return;
      setState(() {
        _name = file.name;
        _values = values;
        _selected = values.map((p) => p.id).toSet();
      });
    } catch (error) {
      if (_current(revision)) {
        setState(() {
          _error = error is FormatException
              ? error.message
              : 'This preset file could not be read.';
        });
      }
    } finally {
      if (_current(revision)) setState(() => _reading = false);
    }
  }

  Future<void> _import() async {
    if (_reading || _saving || _selected.isEmpty) return;
    final revision = ++_revision;
    final values = _values
        .where((p) => _selected.contains(p.id))
        .toList(growable: false);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.onImport(values);
      if (_current(revision)) setState(() => _result = result);
    } catch (error) {
      if (_current(revision)) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Your presets could not be saved. Try again.',
        );
      }
    } finally {
      if (_current(revision)) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = _selected.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        const Text(
          'Bring saved presets from an Android backup or a BDK preset file.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: _button,
          onPressed: _reading || _saving ? null : _choose,
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Choose preset file'),
        ),
        if (_reading || _saving) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_saving ? 'Saving presets…' : 'Reading presets…'),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: colors.error)),
        ],
        if (_result != null) ...[
          const SizedBox(height: 28),
          Icon(Icons.check_circle_outline, color: colors.primary, size: 40),
          const SizedBox(height: 12),
          Text(
            _result!.addedCount == 0
                ? 'Already in your library'
                : 'Added ${_result!.addedCount} preset${_result!.addedCount == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_result!.skippedCount > 0) ...[
            const SizedBox(height: 8),
            Text('${_result!.skippedCount} already saved.'),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: _button,
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ] else if (_name != null && !_reading) ...[
          const SizedBox(height: 24),
          Text(_name!, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            _values.isEmpty
                ? 'This file has no saved presets.'
                : 'Choose which presets to add to your library.',
          ),
          const SizedBox(height: 12),
          for (final p in _values)
            Card(
              child: CheckboxListTile(
                value: _selected.contains(p.id),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        value == true
                            ? _selected.add(p.id)
                            : _selected.remove(p.id);
                      }),
                title: Text(p.name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: PresetShape(levels: p.gains.values),
                ),
              ),
            ),
          if (_values.isNotEmpty) ...[
            const SizedBox(height: 16),
            FilledButton(
              style: _button,
              onPressed: _saving || count == 0 ? null : _import,
              child: Text('Import $count preset${count == 1 ? '' : 's'}'),
            ),
          ],
        ],
      ],
    );
  }
}

final _button = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
);
