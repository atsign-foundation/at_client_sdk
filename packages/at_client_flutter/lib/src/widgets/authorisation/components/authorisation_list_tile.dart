import 'package:flutter/material.dart';

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
    this.trailing,
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

  /// The widget to display at the end of the tile.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 4,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  color: isSelected
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1)
                      : Colors.transparent,
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
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      if (badgeCount != null && badgeCount! > 0)
                        Badge(
                          padding: const EdgeInsets.all(4),
                          textColor: Theme.of(context).colorScheme.primary,
                          textStyle: Theme.of(context).textTheme.bodyMedium,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.3),
                          label: Text(badgeCount.toString()),
                        ),
                      if (trailing != null) trailing!,
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
