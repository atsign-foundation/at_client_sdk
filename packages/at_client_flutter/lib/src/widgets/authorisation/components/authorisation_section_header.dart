import 'package:flutter/material.dart';

/// {@template authorisation_section_header}
/// Simple widget to be displayed at the top of a section in the authorisation
/// page. It displays an icon to the left of the title.
/// {@endtemplate}
class AuthorisationSectionHeader extends StatelessWidget {
  /// {@macro authorisation_section_header}
  const AuthorisationSectionHeader({
    required this.title,
    required this.icon,
    super.key,
  });

  /// The title text to display in the header.
  final String title;

  /// The icon to display to the left of the title.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
