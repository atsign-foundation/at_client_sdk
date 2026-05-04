import 'package:flutter/material.dart';

/// {@template manage_device_card}
/// This widget displays a card with an icon and text indicating that the
/// device can be used as an authenticator for future apps and devices.
/// {@endtemplate}
class ManageDeviceCard extends StatelessWidget {
  /// {@macro manage_device_card}
  const ManageDeviceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.key, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Manager Device',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: const Text(
            'The keys on this device can be used as an authenticator for apps & devices.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
