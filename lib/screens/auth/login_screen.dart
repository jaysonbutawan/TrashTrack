import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../theme.dart';
import '../../widgets/brand_splash.dart';
import '../../widgets/common.dart';
import '../../widgets/recyclable_style.dart';
import '../../widgets/role_card.dart' show GoogleMark, RoleText;

/// Pick Household or Collector, then Google's one-tap account sheet opens.
/// Google is the only way in: every account has an email Google already
/// verified, which keeps spam and throwaway accounts out.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Role tapped; Google sign-in starts from the button below.
  UserRole? _role;
  UserRole? _busy;

  Future<void> _signIn(UserRole role) async {
    setState(() => _busy = role);
    try {
      final existing = await context.read<AuthRepository>().signInWithGoogle(
        role,
      );
      // An existing account keeps its role; say so if it differs.
      if (existing != null && existing != role) {
        showMessage(
          rootMessenger.currentState!,
          'Welcome back! This Google account is registered as a '
          '${existing.title}.',
        );
      }
      // Success: keep the loading view up; AuthGate fades to the home screen.
    } on SignInCancelled {
      // The user closed the account sheet — back to the choices.
      if (mounted) setState(() => _busy = null);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = null);
        showMessage(
          ScaffoldMessenger.of(context),
          friendlyError(e),
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Brand.forestDark,
        body: Stack(
          children: [
            Column(
              children: [
                const Expanded(child: _Hero()),
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Brand.paper,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Who are you?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Brand.ink,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              for (final role in UserRole.values) ...[
                                if (role != UserRole.values.first)
                                  const SizedBox(width: 12),
                                Expanded(
                                  child: _RoleTile(
                                    role: role,
                                    selected: _role == role,
                                    onTap: _busy == null
                                        ? () => setState(() => _role = role)
                                        : null,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 18),
                          _GoogleButton(
                            role: _role,
                            onPressed: _role == null || _busy != null
                                ? null
                                : () => _signIn(_role!),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // One calm screen for the whole sign-in, behind Google's sheet
            // and until the home screen is ready.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _busy == null,
                child: AnimatedOpacity(
                  opacity: _busy == null ? 0 : 1,
                  duration: const Duration(milliseconds: 220),
                  child: BrandSplash(
                    message: _busy == null
                        ? null
                        : 'Signing you in as a ${_busy!.title}…',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Square choice: big icon and one word. Fills with the role color when
/// picked.
class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.role,
    required this.selected,
    required this.onTap,
  });
  final UserRole role;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = role == UserRole.household ? Brand.forest : Brand.kraft;
    return Semantics(
      button: true,
      selected: selected,
      label: role.title,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? accent : Brand.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? accent : Brand.line, width: 2),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.18)
                              : accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          role.icon,
                          size: 36,
                          color: selected ? Colors.white : accent,
                        ),
                      ),
                      if (selected)
                        const Positioned(
                          right: -4,
                          top: -4,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.check,
                              size: 17,
                              color: Brand.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    role.title,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : Brand.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Continue with Google" — greyed out until a role is picked.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.role, required this.onPressed});
  final UserRole? role;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = role == UserRole.collector ? Brand.kraft : Brand.forest;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        disabledBackgroundColor: Brand.line,
        disabledForegroundColor: Brand.inkSoft,
        minimumSize: const Size.fromHeight(58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onPressed == null ? Colors.white70 : Colors.white,
              shape: BoxShape.circle,
            ),
            child: const GoogleMark(size: 20),
          ),
          const SizedBox(width: 12),
          const Flexible(
            child: Text(
              'Continue with Google',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo with the material types orbiting it, app name and tagline.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    const types = RecyclableType.values;
    return SafeArea(
      bottom: false,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox(
                width: 168,
                height: 168,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 168,
                      height: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 2,
                        ),
                      ),
                    ),
                    Container(
                      width: 92,
                      height: 92,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Brand.kraft,
                      ),
                      child: const Icon(
                        Icons.recycling,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                    for (var i = 0; i < types.length; i++)
                      Align(
                        alignment: Alignment(
                          0.98 * _cos(i / types.length),
                          0.98 * _sin(i / types.length),
                        ),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            types[i].icon,
                            size: 19,
                            color: types[i].color,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Bote-Bakal Tagum',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'May halaga ang basura mo.\nYour recyclables, picked up from home.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.5,
                  height: 1.35,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Positions on a circle, starting at the top.
  static double _sin(double t) => math.sin((t * 2 - 0.5) * math.pi);
  static double _cos(double t) => math.cos((t * 2 - 0.5) * math.pi);
}
