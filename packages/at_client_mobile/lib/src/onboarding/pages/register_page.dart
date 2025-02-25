import 'dart:async';

import 'package:at_client_mobile/src/onboarding/providers/free_atsign_notifier_provider.dart';
import 'package:flutter/material.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  RegisterPageState createState() => RegisterPageState();
}

class RegisterPageState extends State<RegisterPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(FreeAtsignNotifierProvider.of(context).fetchFreeAtsign());
    });
  }

  @override
  Widget build(BuildContext context) {
    final freeAtSignNotifier = FreeAtsignNotifierProvider.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Get a free atSign',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: 24),
        // TODO: Add a nice animation when loading and loaded.
        IgnorePointer(
          ignoring: true,
          child: TextField(
            readOnly: true,
            controller: TextEditingController(
              text: freeAtSignNotifier.isFetching ? 'Fetching...' : freeAtSignNotifier.freeAtsign,
            ),
            decoration: InputDecoration(
              prefix: freeAtSignNotifier.isFetching ? null : Text('@'),
              prefixStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        if (freeAtSignNotifier.error != null)
          Text(
            'Error fetching free atSign: ${freeAtSignNotifier.error}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        SizedBox(height: 8),
        Text(
          'Refresh until you see an atSign that you like, then press Pair.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        SizedBox(height: 8),
        InkWell(
          onTap: () {
            // Open browser to more info.
          },
          child: Text(
            'Learn more about atSigns',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  decoration: TextDecoration.underline,
                ),
          ),
        ),
        SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            if (!freeAtSignNotifier.isFetching) {
              await freeAtSignNotifier.fetchFreeAtsign();
            }
          },
          icon: Icon(Icons.refresh),
          iconAlignment: IconAlignment.end,
          label: Text('Refresh'),
        ),
        SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {},
          icon: Icon(Icons.arrow_forward),
          iconAlignment: IconAlignment.end,
          label: Text('Pair'),
        ),
        SizedBox(height: 24),
        InkWell(
          onTap: () {
            // Go back.
          },
          child: Text(
            'Already have an atSign?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
      ],
    );
  }
}
