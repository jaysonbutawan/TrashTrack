import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories.dart';
import '../../models/app_user.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/role_card.dart';

/// Rarely seen: sign-in normally saves the role picked on the login screen
/// by itself. This appears only for an account that still has no role
/// (e.g. the connection dropped half-way) and asks once more.
class FinishSignUpScreen extends StatefulWidget {
  const FinishSignUpScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<FinishSignUpScreen> createState() => _FinishSignUpScreenState();
}

class _FinishSignUpScreenState extends State<FinishSignUpScreen> {
  UserRole? _saving;
  String? _error;

  Future<void> _save(UserRole role) async {
    setState(() {
      _saving = role;
      _error = null;
    });
    try {
      // AuthGate opens the home screen once the profile has its role.
      await context.read<AuthRepository>().finishSignUp(role);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = null;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = _saving;
    return Scaffold(
      body: SafeArea(
        child: saving != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      'Setting up your ${saving.title} account…',
                      style: const TextStyle(
                        fontSize: 19,
                        color: Brand.inkSoft,
                      ),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Hi ${widget.user.firstName}!',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'One last thing — who are you?',
                    style: TextStyle(fontSize: 17, color: Brand.inkSoft),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Brand.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 15.5,
                          color: Brand.danger,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  for (final role in UserRole.values) ...[
                    RoleCard(
                      role: role,
                      action: 'Continue as ${role.title}',
                      onTap: () => _save(role),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextButton(
                    onPressed: () => context.read<AuthRepository>().signOut(),
                    child: const Text('Use a different Google account'),
                  ),
                ],
              ),
      ),
    );
  }
}
