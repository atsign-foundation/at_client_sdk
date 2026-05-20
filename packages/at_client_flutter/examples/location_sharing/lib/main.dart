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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const _LaunchScreen(),
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  Future<void> _tryLogin(
    BuildContext context,
    Future<bool> Function(BuildContext) login,
  ) async {
    try {
      final ok = await login(context);
      if (!ok || !context.mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LocationHome()));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location sharing')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Share latest location with another atSign',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => _tryLogin(context, loginWithKeychain),
                  child: const Text('Login with existing atSign'),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => _tryLogin(context, loginWithFile),
                  child: const Text('Login from .atKeys file'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _tryLogin(context, loginWithApkam),
                  child: const Text('Enroll via APKAM'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
