import 'package:flutter/material.dart';

import 'incoming.dart';
import 'screens/enter_invitation.dart';
import 'screens/home.dart';
import 'session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Incoming.instance.start();
  runApp(const InvitationsApp());
}

class InvitationsApp extends StatelessWidget {
  const InvitationsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Invitations',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const _LaunchScreen(),
    );
  }
}

/// Signs in, or activates a new atSign, and keeps any invitation that
/// arrived meanwhile for [Home] to open.
class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  Future<void> _go(
    BuildContext context,
    Future<bool> Function(BuildContext) signIn,
  ) async {
    try {
      if (!await signIn(context) || !context.mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const Home()));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invitations')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ValueListenableBuilder(
                  valueListenable: Incoming.instance,
                  builder: (context, link, _) => Text(
                    link == null
                        ? 'Invite people, whether or not they have an atSign '
                              'yet'
                        : '${link.inviter} invited you. Sign in, or get an '
                              'atSign, to open the invitation.',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                for (final atSign in Session.instance.recentAtSigns) ...[
                  FilledButton(
                    onPressed: () => _go(
                      context,
                      (context) => Session.instance.signInFromKeychain(
                        context,
                        atSign: atSign,
                      ),
                    ),
                    child: Text('Sign in as $atSign'),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: () =>
                      _go(context, Session.instance.signInFromKeychain),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => _go(context, Session.instance.getNewAtSign),
                  child: const Text('Get a new atSign'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => enterInvitation(context),
                  child: const Text('Paste an invitation'),
                ),
                const SizedBox(height: 32),
                Text(
                  'New atSigns come from the issuer beside the local '
                  'Ephemeral Environment. A real app gets them from a '
                  'registrar, e.g. my.noports.com/no-ports-plans.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
