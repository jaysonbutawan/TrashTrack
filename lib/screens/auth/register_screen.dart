import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  UserRole? _role;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (_role == null) {
      showMessage(ScaffoldMessenger.of(context),
          'Please choose: Household or Collector', error: true);
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().register(
            email: _email.text,
            password: _password.text,
            name: _name.text,
            phone: _phone.text,
            role: _role!,
          );
      // AuthGate switches to the home screen; drop this route.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        showMessage(ScaffoldMessenger.of(context), friendlyAuthError(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _roleCard(UserRole role, IconData icon, String title, String sub) {
    final selected = _role == role;
    final color = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _role = role),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : null,
            border: Border.all(
                color: selected ? color : Colors.grey.shade400,
                width: selected ? 3 : 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            Icon(icon, size: 52, color: selected ? color : Colors.grey),
            const SizedBox(height: 6),
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('I am a…',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(children: [
                  _roleCard(UserRole.household, Icons.home, 'Household',
                      'I have recyclables'),
                  const SizedBox(width: 12),
                  _roleCard(UserRole.collector, Icons.local_shipping,
                      'Collector', 'I pick up recyclables'),
                ]),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(fontSize: 19),
                  decoration: const InputDecoration(
                      labelText: 'Full name', prefixIcon: Icon(Icons.person)),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 19),
                  decoration: const InputDecoration(
                      labelText: 'Mobile number (09xx…)',
                      prefixIcon: Icon(Icons.phone)),
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    return digits.length < 10
                        ? 'Enter a valid mobile number'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 19),
                  decoration: const InputDecoration(
                      labelText: 'Email', prefixIcon: Icon(Icons.email)),
                  validator: (v) =>
                      (v ?? '').contains('@') ? null : 'Enter a valid email',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  style: const TextStyle(fontSize: 19),
                  decoration: const InputDecoration(
                      labelText: 'Password (6+ characters)',
                      prefixIcon: Icon(Icons.lock)),
                  validator: (v) => (v ?? '').length < 6
                      ? 'At least 6 characters'
                      : null,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _busy ? null : _register,
                  icon: const Icon(Icons.check),
                  label: Text(_busy ? 'Creating…' : 'Create Account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
