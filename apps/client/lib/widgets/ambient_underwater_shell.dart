import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/zalmanim_icons.dart';

class AmbientUnderwaterShell extends StatefulWidget {
  const AmbientUnderwaterShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AmbientUnderwaterShell> createState() => _AmbientUnderwaterShellState();
}

class _AmbientUnderwaterShellState extends State<AmbientUnderwaterShell> {
  final math.Random _random = math.Random();
  Timer? _nextAppearanceTimer;
  Timer? _fadeOutTimer;

  bool _travelFromLeft = true;
  bool _inFlight = false;
  double _topFactor = 0.22;
  double _size = 112;
  double _opacity = 0;
  Duration _travelDuration = const Duration(seconds: 18);

  @override
  void initState() {
    super.initState();
    _scheduleNextAppearance(initial: true);
  }

  @override
  void dispose() {
    _nextAppearanceTimer?.cancel();
    _fadeOutTimer?.cancel();
    super.dispose();
  }

  void _scheduleNextAppearance({bool initial = false}) {
    _nextAppearanceTimer?.cancel();
    final waitSeconds =
        initial ? 5 + _random.nextInt(5) : 18 + _random.nextInt(20);
    _nextAppearanceTimer =
        Timer(Duration(seconds: waitSeconds), _launchJellyfish);
  }

  void _launchJellyfish() {
    if (!mounted) return;
    final fromLeft = _random.nextBool();
    final travelSeconds = 16 + _random.nextInt(10);
    setState(() {
      _travelFromLeft = fromLeft;
      _topFactor = 0.08 + (_random.nextDouble() * 0.68);
      _size = 84 + (_random.nextDouble() * 42);
      _travelDuration = Duration(seconds: travelSeconds);
      _inFlight = false;
      _opacity = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _inFlight = true;
        _opacity = 0.18;
      });
    });

    _fadeOutTimer?.cancel();
    _fadeOutTimer = Timer(
      Duration(seconds: math.max(8, travelSeconds - 4)),
      () {
        if (!mounted) return;
        setState(() => _opacity = 0);
      },
    );

    _scheduleNextAppearance();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 1200.0;
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 900.0;
        final startLeft = _travelFromLeft ? -_size * 1.3 : width + (_size * 0.3);
        final endLeft = _travelFromLeft ? width + (_size * 0.3) : -_size * 1.3;

        return Stack(
          children: [
            const Positioned.fill(child: AmbientBackdrop()),
            Positioned.fill(child: widget.child),
            if (!reduceMotion)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          duration: _travelDuration,
                          curve: Curves.easeInOutSine,
                          left: _inFlight ? endLeft : startLeft,
                          top: height * _topFactor,
                          child: AnimatedOpacity(
                            duration: const Duration(seconds: 3),
                            curve: Curves.easeInOut,
                            opacity: _opacity,
                            child: _FloatingJellyfish(
                              size: _size,
                              flipX: !_travelFromLeft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF6FCFD),
              Color(0xFFEAF7F4),
              Color(0xFFFDF7EF),
            ],
            stops: [0.0, 0.58, 1.0],
          ),
        ),
        child: Stack(
          children: const [
            Positioned(
              top: -70,
              left: -40,
              child: _GlowOrb(
                size: 260,
                colors: [Color(0x33A9F2D9), Color(0x00A9F2D9)],
              ),
            ),
            Positioned(
              top: 90,
              right: -50,
              child: _GlowOrb(
                size: 220,
                colors: [Color(0x33FFD4A8), Color(0x00FFD4A8)],
              ),
            ),
            Positioned(
              bottom: -40,
              left: 120,
              child: _GlowOrb(
                size: 240,
                colors: [Color(0x22F3A6C8), Color(0x00F3A6C8)],
              ),
            ),
            Positioned(
              bottom: 40,
              right: 60,
              child: _GlowOrb(
                size: 180,
                colors: [Color(0x22A6D8FF), Color(0x00A6D8FF)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.colors,
  });

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    );
  }
}

class _FloatingJellyfish extends StatelessWidget {
  const _FloatingJellyfish({
    required this.size,
    required this.flipX,
  });

  final double size;
  final bool flipX;

  @override
  Widget build(BuildContext context) {
    const shellTint = Color(0xFFE57CA6);

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.rotationZ(flipX ? -0.08 : 0.08),
      child: Transform.flip(
        flipX: flipX,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size * 0.82,
                height: size * 0.82,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x55FFD2E2), Color(0x00FFD2E2)],
                  ),
                ),
              ),
              ZalmanimIcons.jellyfishIcon(
                size: size,
                color: shellTint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
