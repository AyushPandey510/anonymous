import 'package:flutter/material.dart';

/// Locally rendered Three.js frames, with no network or WebView at startup.
class OrbitAnimation extends StatelessWidget {
  const OrbitAnimation({
    super.key,
    required this.size,
    this.interactive = true,
  });

  final double size;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final imageAsset = reduceMotion
        ? dark
              ? 'assets/orbit/crystals-still.webp'
              : 'assets/orbit/crystals-still-warm.webp'
        : dark
        ? 'assets/orbit/crystals.webp'
        : 'assets/orbit/crystals-warm.webp';

    return SizedBox(
      width: size + 36,
      height: size + 36,
      child: Center(
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? const Color(0xFF242637) : const Color(0xFFF4E7D0),
            ),
            child: Image.asset(
              imageAsset,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}
