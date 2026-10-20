import 'package:flutter/material.dart';

/// One incoming handoff per controls mount. Accessibility changes preserve the
/// child tree and finish an in-progress reveal instead of replaying it.
class ConnectedControlsReveal extends StatefulWidget {
  const ConnectedControlsReveal({
    super.key,
    required this.child,
    required this.animate,
  });
  final Widget child;
  final bool animate;
  @override
  State<ConnectedControlsReveal> createState() =>
      _ConnectedControlsRevealState();
}

class _ConnectedControlsRevealState extends State<ConnectedControlsReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _began = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    if (!widget.animate ||
        media.disableAnimations ||
        media.accessibleNavigation) {
      _controller.value = 1;
    } else if (!_began) {
      _controller.forward();
    }
    _began = true;
  }

  @override
  void didUpdateWidget(covariant ConnectedControlsReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) _controller.value = 1;
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    child: widget.child,
    builder: (_, child) => Opacity(
      key: const ValueKey('connected-controls-reveal'),
      opacity: _progress.value,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - _progress.value)),
        child: child,
      ),
    ),
  );
}
