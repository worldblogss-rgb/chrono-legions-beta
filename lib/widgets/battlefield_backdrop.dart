import 'package:flutter/material.dart';

import '../theme/chrono_assets.dart';
import '../theme/chrono_theme.dart';

class BattlefieldBackdrop extends StatelessWidget {
  const BattlefieldBackdrop({
    super.key,
    required this.child,
    this.assetPath = ChronoAssets.battlefield,
    this.overlayOpacity = .46,
  });

  final Widget child;
  final String assetPath;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ChronoPalette.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF261812),
                      ChronoPalette.battlefield,
                      Color(0xFF0D1310),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withAlpha(
                  (255 * overlayOpacity).round(),
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x29190D08),
                      Color(0x10101410),
                      Color(0x45100B08),
                    ],
                    stops: [0, .50, 1],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
