import 'package:flutter/material.dart';

import 'onboarding.dart';
import 'screens/todos_home.dart';

void main() {
  runApp(const TodosApp());
}

class TodosApp extends StatelessWidget {
  const TodosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todos',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
    Future<bool> Function(BuildContext) fn,
  ) async {
    try {
      final ok = await fn(context);
      if (!ok || !context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TodosHome()),
      );
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
      appBar: AppBar(title: const Text('Todos')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Shared todos over the atPlatform',
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
                const SizedBox(height: 32),
                Text(
                  'Get a free atSign at my.noports.com/no-ports-plans',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
