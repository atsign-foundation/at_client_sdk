import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';

import 'onboarding.dart';
import 'screens/location_home.dart';

void main() {
  runApp(const LocationSharingApp());
}

class LocationSharingApp extends StatelessWidget {
  const LocationSharingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Location sharing',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loggingIn = false;

  Future<void> _login(Future<AtClient?> Function(BuildContext) flow) async {
    setState(() => _loggingIn = true);
    final client = await flow(context);
    if (!mounted) return;
    setState(() => _loggingIn = false);
    if (client == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LocationHome(atClient: client)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Share your live location over the Atsign Protocol',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              if (_loggingIn) const CircularProgressIndicator(),
              if (!_loggingIn) ...[
                FilledButton(
                  onPressed: () => _login(loginWithKeychain),
                  child: const Text('Continue with keychain'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _login(loginWithFile),
                  child: const Text('Onboard from .atKeys file'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
