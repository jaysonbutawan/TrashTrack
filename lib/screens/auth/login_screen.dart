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
import '../../widgets/role_card.dart';

/// Pick Household or Collector, then Google's one-tap account sheet opens.
/// Google is the only way in: every account has an email Google already
/// verified, which keeps spam and throwaway accounts out.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              color: Brand.ink,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (final role in UserRole.values) ...[
                            RoleCard(
                              role: role,
                              busy: _busy == role,
                              onTap: _busy == null ? () => _signIn(role) : null,
                            ),
                            const SizedBox(height: 12),
                          ],
                          const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.verified_user,
                                size: 19,
                                color: Brand.leaf,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Only verified Google accounts can join. '
                                  'Already have an account? Tap either one.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Brand.inkSoft,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
