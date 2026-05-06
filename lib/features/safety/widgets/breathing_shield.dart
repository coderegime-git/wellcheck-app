import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';

class BreathingShield extends StatefulWidget {
  final Color color;
  final double size;
  final Widget? child;
  final bool isUrgent;

  const BreathingShield({
    super.key,
    this.color = ShieldColors.activeTeal,
    this.size = 200,
    this.child,
    this.isUrgent = false,
    this.isDeescalating = false,
  });

  final bool isDeescalating;

  @override
  State<BreathingShield> createState() => _BreathingShieldState();
}

class _BreathingShieldState extends State<BreathingShield>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        seconds: widget.isUrgent
            ? 1
            : (widget.isDeescalating ? 10 : 4),
      ),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    _glowAnimation = Tween<double>(begin: 10.0, end: 40.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    _controller.addListener(() {
      // Sophisticated Haptic Sync: Fire a soft tick at the peak of the breath
      if (_controller.value > 0.98) {
        HapticFeedback.selectionClick();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.size * _pulseAnimation.value,
          height: widget.size * _pulseAnimation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4),
                blurRadius: _glowAnimation.value,
                spreadRadius: _glowAnimation.value / 2,
              ),
            ],
            gradient: RadialGradient(
              colors: [
                widget.color,
                widget.color.withValues(alpha: 0.8),
                widget.color.withValues(alpha: 0.4),
              ],
            ),
          ),
          child: Center(
            child: widget.child ??
                Icon(
                  widget.isUrgent ? Icons.warning_rounded : Icons.shield,
                  color: Colors.white,
                  size: widget.size * 0.4,
                ),
          ),
        );
      },
    );
  }
}
