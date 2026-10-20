import 'package:flutter/material.dart';
import 'audio_config_summary_controller.dart';

/// Shared compact strip; its caller owns observation and route lifecycle.
class AudioConfigSummary extends StatelessWidget {
  const AudioConfigSummary({
    super.key,
    required this.controller,
    required this.onTap,
  });
  final AudioConfigSummaryController controller;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      return SizedBox(
        width: double.infinity,
        child: Semantics(
          label: 'Audio quality',
          child: TextButton(
            key: const ValueKey('audio-config-summary'),
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              foregroundColor: colors.onSurfaceVariant,
              shape: const RoundedRectangleBorder(),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.high_quality_outlined,
                  size: 18,
                  color: controller.hasFreshObservation ? colors.primary : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.text,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ),
        ),
      );
    },
  );
}
