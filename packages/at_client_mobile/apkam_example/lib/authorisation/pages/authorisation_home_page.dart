import 'package:apkam_example/authorisation/services/authorisation_service.dart';
import 'package:apkam_example/theme/theme_constants.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

import '../../theme/at_theme.dart';
import '../models/models.dart';

class AuthorisationHomePage extends StatefulWidget {
  const AuthorisationHomePage({super.key});

  @override
  AuthorisationHomePageState createState() => AuthorisationHomePageState();
}

class AuthorisationHomePageState extends State<AuthorisationHomePage> {
  late final service = AuthorisationService(AtClientManager.getInstance().atClient);

  late Future<bool> isManagerKey;

  @override
  void initState() {
    super.initState();
    isManagerKey = service.isManagerKey();
  }

  @override
  Widget build(BuildContext context) {
    return AtTheme(
      child: Scaffold(
        appBar: AppBar(
          title: Text(AtClientManager.getInstance().atClient.getCurrentAtSign()!),
        ),
        body: FutureBuilder<bool>(
          future: isManagerKey,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }
            if (snapshot.hasError) {
              return Text('Error ${snapshot.error}');
            }
            final isManagerKey = snapshot.data as bool;
            if (!isManagerKey) {
              return Text('Your key is not a manager key');
            } else {
              print(Theme.of(context).colorScheme.surface);
              return Padding(
                padding: const EdgeInsets.all(64.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(kBorderRadius),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 500,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Card(
                                  elevation: 0,
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.key,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
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
                                  'The app on this device can be used as an authenticator for all future apps & devices.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Card(
                                  elevation: 0,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'OTP',
                                              style: Theme.of(context).textTheme.headlineSmall,
                                            ),
                                            IconButton(
                                              tooltip: 'Refresh OTP',
                                              icon: Icon(
                                                Icons.refresh,
                                                color: Theme.of(context).colorScheme.primary,
                                                size: 32,
                                              ),
                                              onPressed: () {},
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'Use this to enroll other apps and devices.',
                                        ),
                                        const SizedBox(height: 8),
                                        FutureBuilder<Otp>(
                                          future: service.generateOtp(),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState == ConnectionState.waiting) {
                                              return const Center(
                                                child: CircularProgressIndicator(),
                                              );
                                            }
                                            if (snapshot.hasError) {
                                              return Text('Error: ${snapshot.error}');
                                            }
                                            // TODO: This needs to work with many characters so maybe using Wrap or scaling the
                                            // text down if needed will be needed.
                                            return Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: snapshot.data!.otp.split('').map(
                                                (e) {
                                                  return Padding(
                                                    padding: const EdgeInsets.all(8.0),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Padding(
                                                        padding: const EdgeInsets.all(8.0),
                                                        child: Text(
                                                          e,
                                                          style: Theme.of(context).textTheme.headlineMedium,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ).toList(),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        TextButton.icon(
                                          onPressed: () {},
                                          icon: const Icon(Icons.copy),
                                          label: const Text('Copy OTP'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              AuthorisationListTile(
                                leading: Icons.password,
                                title: 'Set pin',
                                onTap: () {},
                                isSelected: false,
                              ),
                              AuthorisationListTile(
                                leading: Icons.question_mark_outlined,
                                title: 'Requests',
                                onTap: () {},
                                isSelected: true,
                                badgeCount: 4,
                              ),
                              AuthorisationListTile(
                                leading: Icons.check,
                                title: 'Approved Enrollments',
                                onTap: () {},
                                isSelected: false,
                              ),
                              AuthorisationListTile(
                                leading: Icons.history,
                                title: 'History',
                                onTap: () {},
                                isSelected: false,
                              ),
                              const Spacer(),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: OutlinedButton.icon(
                                  label: const Text('Backup atSign'),
                                  icon: const Icon(Icons.backup_outlined),
                                  onPressed: () {},
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text('Selected content here'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}

/// {@template authorisation_list_tile}
/// A list tile for switching between different sections.
///
/// If [isSelected] is true, the tile will be highlighted.
/// {@endtemplate}
class AuthorisationListTile extends StatelessWidget {
  /// {@macro authorisation_list_tile}
  const AuthorisationListTile({
    required this.isSelected,
    required this.title,
    required this.leading,
    required this.onTap,
    this.badgeCount,
    super.key,
  });

  /// Whether the tile is selected.
  /// Will highlight the tile if true.
  final bool isSelected;

  /// The text to display in the tile.
  final String title;

  /// The icon to display in the tile.
  final IconData leading;

  /// The function to call when the tile is tapped.
  final VoidCallback onTap;

  /// The number to display in the badge.
  /// If null, the badge will not be displayed.
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                width: 4,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Icon(
                        leading,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const Spacer(),
                      if (badgeCount != null)
                        Badge(
                          padding: const EdgeInsets.all(4),
                          textColor: Theme.of(context).colorScheme.primary,
                          textStyle: Theme.of(context).textTheme.bodyMedium,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          label: Text(
                            badgeCount.toString(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
