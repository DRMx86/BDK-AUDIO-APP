import 'package:flutter/material.dart';

/// A quiet waiting cue. Readiness and connection status come from the caller.
class ConnectionHalo extends StatefulWidget {
  const ConnectionHalo({
    super.key,
    this.active = true,
    this.size = 112,
    this.child,
  });
  final bool active;
  final double size;
  final Widget? child;

  @override
  State<ConnectionHalo> createState() => _ConnectionHaloState();
}

class _ConnectionHaloState extends State<ConnectionHalo>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  void _syncMotion() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(ConnectionHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _pulse,
            child:
                widget.child ??
                Icon(
                  Icons.speaker_outlined,
                  size: widget.size * .32,
                  color: primary,
                ),
            builder: (context, child) {
              final value = Curves.easeInOut.transform(_pulse.value);
              return Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: .88 + value * .12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary.withValues(alpha: .035 + value * .025),
                        border: Border.all(
                          color: primary.withValues(alpha: .16 + value * .16),
                        ),
                      ),
                      child: SizedBox.expand(),
                    ),
                  ),
                  child!,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
