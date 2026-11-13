import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme.dart';

extension RoleText on UserRole {
  String get title => this == UserRole.household ? 'Household' : 'Collector';
  String get pitch => this == UserRole.household
      ? 'I have bote, bakal, plastic or karton to give or sell'
      : 'I pick up and buy recyclables around Tagum';
  IconData get icon =>
      this == UserRole.household ? Icons.home_rounded : Icons.local_shipping;
}

/// Big tappable card: "I'm a Household / Collector — Continue with Google".
class RoleCard extends StatelessWidget {
  const RoleCard({
    super.key,
    required this.role,
    required this.onTap,
    this.busy = false,
    this.action = 'Continue with Google',
  });

  final UserRole role;
  final VoidCallback? onTap;
  final bool busy;
  final String action;

  @override
  Widget build(BuildContext context) {
    final household = role == UserRole.household;
    final accent = household ? Brand.forest : Brand.kraft;
    return Material(
      color: Brand.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: accent.withValues(alpha: 0.45), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(role.icon, size: 34, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "I'm a ${role.title}",
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Brand.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          role.pitch,
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: Brand.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const GoogleMark(size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            action,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_forward, color: Colors.white),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four-color "G" drawn with text, so no image asset is needed.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (r) => const SweepGradient(
      colors: [
        Color(0xFFEA4335),
        Color(0xFFFBBC05),
        Color(0xFF34A853),
        Color(0xFF4285F4),
        Color(0xFFEA4335),
      ],
      stops: [0.0, 0.3, 0.55, 0.8, 1.0],
    ).createShader(r),
    child: Text(
      'G',
      style: TextStyle(
        fontSize: size,
        height: 1,
        fontWeight: FontWeight.w900,
        color: Colors.white,
      ),
    ),
  );
}
