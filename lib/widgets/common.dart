import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/format.dart';

/// A number that eases to its new value instead of jumping.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount(
    this.value, {
    super.key,
    this.style,
    this.format = fmtInt,
    this.suffix = '',
  });

  final num value;
  final TextStyle? style;
  final String Function(num) format;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: Motion.of(context, Motion.long),
      curve: Motion.enter,
      builder: (context, v, _) => Text(
        '${format(v)}$suffix',
        style: (style ?? DefaultTextStyle.of(context).style).copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A page section drawn straight on the surface (no card): a full-width
/// divider, a Title Medium header with optional supporting text, then the
/// content.
class Section extends StatelessWidget {
  const Section({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.divider = true,
    required this.child,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final bool divider;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (divider) const Divider(height: 1),
        SizedBox(height: divider ? 20 : 0),
        if (title != null) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title!, style: t.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: t.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 16),
        ],
        child,
        const SizedBox(height: 4),
      ],
    );
  }
}

/// One figure with a short label under it.
class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.onTap,
  });

  final Widget value;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DefaultTextStyle.merge(
          style: t.headlineSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: value,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: body,
    );
  }
}

/// Figures side by side, split by thin vertical dividers.
class MetricRow extends StatelessWidget {
  const MetricRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const VerticalDivider(width: 32),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// Fades and lifts its child in once, with an optional stagger delay.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 8,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.long,
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Motion.enter,
  );
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted || _delay != null) return;
    if (Motion.of(context, Motion.long) == Duration.zero) {
      _c.value = 1;
    } else {
      _delay = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _a.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// M3 (2024) linear progress indicator that animates its fill.
class WarmProgress extends StatelessWidget {
  const WarmProgress({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: Motion.of(context, Motion.long),
      curve: Motion.enter,
      builder: (context, v, _) => LinearProgressIndicator(
        value: v,
        minHeight: 8,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
