import 'package:flutter/material.dart';
import 'profile_mutations.dart';

/// The controller lives through the entire modal route, including reverse
/// animation, rather than a guessed delay after the pop future completes.
class PresetNameDialog extends StatefulWidget {
  const PresetNameDialog({
    super.key,
    required this.title,
    required this.initialName,
    required this.existingNames,
  });
  final String title, initialName;
  final Set<String> existingNames;
  @override
  State<PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<PresetNameDialog> {
  late final TextEditingController _input;
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _input.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _input,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Preset name',
          counterText: '',
        ),
        onFieldSubmitted: (_) => _submit(),
        validator: (value) {
          try {
            ProfileMutations.name(value ?? '', widget.existingNames);
            return null;
          } on FormatException catch (error) {
            return error.message;
          }
        },
      ),
    ),
    actions: [
      TextButton(
        style: _button,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: _button,
        onPressed: _submit,
        child: const Text('Save'),
      ),
    ],
  );
}

final _button = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
);
