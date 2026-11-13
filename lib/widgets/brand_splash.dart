import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Full-screen branded loading view: the turning recycling mark, the app name
/// and one line saying what is happening. Used at start-up and during
/// sign-in, so the user sees one calm screen instead of several spinners.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key, this.message});

  /// e.g. "Signing you in…". Null shows only the logo.
  final String? message;

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: Brand.forestDark,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(
                  color: Brand.kraft,
                  shape: BoxShape.circle,
                ),
                child: RotationTransition(
                  turns: _turn,
                  child: const Icon(
                    Icons.recycling,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Bote-Bakal Tagum',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  widget.message ?? '',
                  key: ValueKey(widget.message),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16.5,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
