import 'package:flutter/material.dart';
import '../../../widgets/surface_decoration.dart';

class SoundOptionsPanel extends StatelessWidget {
  const SoundOptionsPanel({
    super.key,
    required this.controlFlags,
    required this.onChanged,
  });
  final int controlFlags;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final fullRange = controlFlags & 0x04 != 0;
    final swapped = controlFlags & 0x02 != 0;
    final colors = Theme.of(context).colorScheme;
    void change(int mask, bool enabled) =>
        onChanged(enabled ? controlFlags | mask : controlFlags & ~mask);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OptionCard(
          child: _OptionSwitch(
            title: 'Bass boost',
            description:
                'Add weight to low frequencies. Works in both output modes.',
            controlKey: const ValueKey('bass-boost'),
            value: controlFlags & 0x01 != 0,
            onChanged: (value) => change(0x01, value),
          ),
        ),
        const SizedBox(height: 16),
        _OptionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OptionSwitch(
                title: 'Full-range stereo',
                description:
                    'Send the complete frequency range to each output.',
                controlKey: const ValueKey('full-range'),
                value: fullRange,
                onChanged: (value) => change(0x04, value),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        fullRange ? 'Stereo outputs' : 'Crossover outputs',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          _RouteLabel(
                            text:
                                'Left · ${fullRange
                                    ? 'Full range'
                                    : swapped
                                    ? 'High'
                                    : 'Low'}',
                          ),
                          _RouteLabel(
                            text:
                                'Right · ${fullRange
                                    ? 'Full range'
                                    : swapped
                                    ? 'Low'
                                    : 'High'}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Equalizer stays active in both modes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),
              _OptionSwitch(
                title: 'Swap low / high outputs',
                description: fullRange
                    ? 'Available in crossover mode. Your swap setting is remembered.'
                    : 'Exchange the low and high output assignments.',
                controlKey: const ValueKey('output-swap'),
                value: swapped,
                onChanged: fullRange ? null : (value) => change(0x02, value),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: bdkSurfaceDecoration(
      context,
      radius: 22,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
    ),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
}

class _OptionSwitch extends StatelessWidget {
  const _OptionSwitch({
    required this.title,
    required this.description,
    required this.controlKey,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String description;
  final Key controlKey;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(width: 10),
          Semantics(
            label: title,
            child: Switch(
              key: controlKey,
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
        ],
      ),
      const SizedBox(height: 3),
      Text(
        description,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _RouteLabel extends StatelessWidget {
  const _RouteLabel({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
  );
}
