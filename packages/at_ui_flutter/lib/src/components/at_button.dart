import 'package:flutter/material.dart';

import '../tokens/at_colors.dart';
import '../tokens/at_radius.dart' show AtRadius;
import '../tokens/at_spacing.dart';
import '../tokens/at_typography.dart';

/// Defines the visual variant of the [AtButton].
enum AtButtonType { primary, secondary, tertiary, warning, link }

/// Defines the size of the [AtButton].
enum AtButtonSize { small, medium, large }

class AtButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AtButtonType type;
  final AtButtonSize size;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final bool isLoading;

  const AtButton._internal({
    super.key,
    required this.label,
    required this.onPressed,
    required this.type,
    required this.size,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
  });

  factory AtButton.primary({
    Key? key,
    required String label,
    VoidCallback? onPressed,
    AtButtonSize size = AtButtonSize.medium,
    Widget? leadingIcon,
    Widget? trailingIcon,
    bool isLoading = false,
  }) => AtButton._internal(
    key: key,
    label: label,
    onPressed: onPressed,
    type: AtButtonType.primary,
    size: size,
    leadingIcon: leadingIcon,
    trailingIcon: trailingIcon,
    isLoading: isLoading,
  );

  factory AtButton.secondary({
    Key? key,
    required String label,
    VoidCallback? onPressed,
    AtButtonSize size = AtButtonSize.medium,
    Widget? leadingIcon,
    Widget? trailingIcon,
    bool isLoading = false,
  }) => AtButton._internal(
    key: key,
    label: label,
    onPressed: onPressed,
    type: AtButtonType.secondary,
    size: size,
    leadingIcon: leadingIcon,
    trailingIcon: trailingIcon,
    isLoading: isLoading,
  );

  factory AtButton.tertiary({
    Key? key,
    required String label,
    VoidCallback? onPressed,
    AtButtonSize size = AtButtonSize.medium,
    Widget? leadingIcon,
    Widget? trailingIcon,
    bool isLoading = false,
  }) => AtButton._internal(
    key: key,
    label: label,
    onPressed: onPressed,
    type: AtButtonType.tertiary,
    size: size,
    leadingIcon: leadingIcon,
    trailingIcon: trailingIcon,
    isLoading: isLoading,
  );

  factory AtButton.warning({
    Key? key,
    required String label,
    VoidCallback? onPressed,
    AtButtonSize size = AtButtonSize.medium,
    Widget? leadingIcon,
    Widget? trailingIcon,
    bool isLoading = false,
  }) => AtButton._internal(
    key: key,
    label: label,
    onPressed: onPressed,
    type: AtButtonType.warning,
    size: size,
    leadingIcon: leadingIcon,
    trailingIcon: trailingIcon,
    isLoading: isLoading,
  );

  factory AtButton.link({
    Key? key,
    required String label,
    VoidCallback? onPressed,
    AtButtonSize size = AtButtonSize.medium,
    Widget? leadingIcon,
    Widget? trailingIcon,
    bool isLoading = false,
  }) => AtButton._internal(
    key: key,
    label: label,
    onPressed: onPressed,
    type: AtButtonType.link,
    size: size,
    leadingIcon: leadingIcon,
    trailingIcon: trailingIcon,
    isLoading: isLoading,
  );

  @override
  Widget build(BuildContext context) {
    // Fetch tokens
    final colors = Theme.of(context).extension<AtColors>()!;
    final typography = Theme.of(context).extension<AtTypography>()!;
    final radius = Theme.of(context).extension<AtRadius>()!;
    final spacing = Theme.of(context).extension<AtSpacing>()!;

    // Resolve Size Constraints
    final double height;
    final EdgeInsetsGeometry padding;
    final TextStyle textStyle;

    switch (size) {
      case AtButtonSize.small:
        height = spacing.s36;
        padding = EdgeInsets.symmetric(horizontal: spacing.s16, vertical: 10);
        textStyle = typography.buttonSm;
        break;
      case AtButtonSize.medium:
        height = 46;
        padding = EdgeInsets.symmetric(
          horizontal: spacing.s24,
          vertical: spacing.s12,
        );
        textStyle = typography.buttonMd;
        break;
      case AtButtonSize.large:
        height = 54;
        padding = EdgeInsets.symmetric(horizontal: spacing.s32, vertical: 14);
        textStyle = typography.buttonLg;
        break;
    }

    /// Resolve Background color state
    Color resolveBackgroundColor(Set<WidgetState> states) {
      final bool isDisabled = states.contains(WidgetState.disabled);
      final bool isPressed = states.contains(WidgetState.pressed);
      final bool isHovered = states.contains(WidgetState.hovered);
      final bool isFocused = states.contains(WidgetState.focused);

      switch (type) {
        case AtButtonType.primary:
          if (isDisabled) return colors.secondary.shade200;
          if (isPressed) return colors.primary.shade700;
          if (isHovered) return colors.primary.shade600;
          if (isFocused) return colors.primary.shade600;
          return colors.primary; // Default
        case AtButtonType.secondary:
          if (isDisabled) return colors.secondary.shade200;
          if (isPressed) return colors.secondary.shade200;
          if (isHovered) return colors.secondary.shade100;
          if (isFocused) return colors.secondary.shade100;
          return colors.secondary.shade50; // Default
        case AtButtonType.tertiary:
          if (isDisabled) return colors.secondary.shade300;
          if (isPressed) return colors.secondary.shade400;
          if (isHovered) return colors.secondary.shade200;
          if (isFocused) return colors.secondary.shade300;
          return colors.secondary.shade100; // Default
        case AtButtonType.warning:
          if (isDisabled) return colors.error.shade200;
          if (isPressed) return colors.error.shade700;
          if (isHovered) return colors.error.shade600;
          if (isFocused) return colors.error.shade600;
          return colors.error; // Default
        case AtButtonType.link:
          if (isDisabled) return Colors.transparent;
          if (isPressed) return Colors.transparent;
          if (isHovered) return Colors.transparent;
          if (isFocused) return Colors.transparent;
          return Colors.transparent; // Default
      }
    }

    /// Resolve Foreground Color
    Color resolveForegroundColor(Set<WidgetState> states) {
      final bool isDisabled = states.contains(WidgetState.disabled);
      final bool isPressed = states.contains(WidgetState.pressed);
      switch (type) {
        case AtButtonType.primary:
          return colors.secondary.shade50;
        case AtButtonType.secondary:
          if (isDisabled) return colors.secondary.shade300;
          return colors.secondary.shade700;
        case AtButtonType.tertiary:
          if (isDisabled) return colors.secondary.shade400;
          return colors.secondary.shade700;
        case AtButtonType.warning:
          if (isDisabled) return colors.warning.shade50;
          return colors.secondary.shade50;
        case AtButtonType.link:
          if (isDisabled) return colors.secondary.shade200;
          if (isPressed) return colors.secondary.shade800;
          return colors.secondary.shade700;
      }
    }

    /// Resolve Border
    BorderSide? resolveBorder(Set<WidgetState> states) {
      final bool isDisabled = states.contains(WidgetState.disabled);
      final bool isPressed = states.contains(WidgetState.pressed);
      final bool isFocused = states.contains(WidgetState.focused);

      switch (type) {
        // only focus state has border for primary button.
        case AtButtonType.primary:
          switch (size) {
            case AtButtonSize.small:
            case AtButtonSize.medium:
              if (isFocused) {
                return BorderSide(
                  width: spacing.s2,
                  color: colors.primary.shade300,
                );
              }
            case AtButtonSize.large:
              if (isFocused) {
                return BorderSide(
                  width: spacing.s2,
                  color: colors.primary.shade300,
                );
              }
          }
          return null; // No border for other states
        case AtButtonType.secondary:
          if (isPressed || isDisabled) {
            return BorderSide(width: 1, color: colors.secondary.shade300);
          }
          switch (size) {
            case AtButtonSize.small:
            case AtButtonSize.medium:
              if (isFocused) {
                return BorderSide(
                  width: spacing.s2,
                  color: colors.secondary.shade300,
                );
              }
            case AtButtonSize.large:
              if (isFocused) {
                return BorderSide(
                  width: spacing.s4,
                  color: colors.secondary.shade300,
                );
              }
          }
          return BorderSide(
            width: 1,
            color: colors.secondary.shade200,
          ); // isHover and Default uses the same border side
        case AtButtonType.tertiary:
          switch (size) {
            case AtButtonSize.small:
            case AtButtonSize.medium:
              if (isFocused) {
                return BorderSide(
                  width: spacing.s2,
                  color: colors.secondary.shade400,
                );
              }
            case AtButtonSize.large:
              if (isFocused) {
                return BorderSide(
                  width: spacing.s4,
                  color: colors.secondary.shade400,
                );
              }
          }
          return null; // No border for other states
        case AtButtonType.warning:
          switch (size) {
            case AtButtonSize.small:
            case AtButtonSize.medium:
              if (isFocused) {
                return BorderSide(
                  width: spacing.s2,
                  color: colors.error.shade300,
                );
              }
            case AtButtonSize.large:
              if (isFocused) {
                return BorderSide(
                  width: spacing.s4,
                  color: colors.error.shade300,
                );
              }
          }
          return null; // No border for other states
        case AtButtonType.link:
          switch (size) {
            case AtButtonSize.small:
            case AtButtonSize.medium:
            case AtButtonSize.large:
              if (isFocused) {
                return BorderSide(width: 1, color: colors.secondary.shade600);
              }
          }
          return null; // No border for other states
      }
    }

    /// Resolve Button TextStyle
    /// This is only used for link button in hover and pressed states, as other variants share the same text style across states.
    TextStyle resolveTextStyle(Set<WidgetState> states) {
      if (type == AtButtonType.link) {
        final bool ishovered = states.contains(WidgetState.hovered);
        final bool isPressed = states.contains(WidgetState.pressed);
        //TODO: hover and pressed states currently offers the same UI change, so the user can't differentiate between them
        if (ishovered || isPressed) {
          return textStyle.copyWith(decoration: TextDecoration.underline);
        }
      }
      return textStyle; // used text style set when size constraints were resolved for non-link buttons and non-hover/pressed states
    }

    // Compose Inner Content
    final Widget buttonContent;
    if (isLoading) {
      buttonContent = SizedBox(
        width: height * 0.5,
        height: height * 0.5,
        child: CircularProgressIndicator.adaptive(
          strokeWidth: spacing.s2,
          backgroundColor: resolveForegroundColor({}),
        ),
      );
    } else {
      buttonContent = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leadingIcon != null) ...[
            leadingIcon!,
            SizedBox(width: spacing.s8),
          ],
          Text(label, style: textStyle),
          if (trailingIcon != null) ...[
            SizedBox(width: spacing.s8),
            trailingIcon!,
          ],
        ],
      );
    }
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ButtonStyle(
          elevation: WidgetStateProperty.all(0),
          padding: WidgetStateProperty.all(padding),
          backgroundColor: WidgetStateProperty.resolveWith(
            resolveBackgroundColor,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            resolveForegroundColor,
          ),
          side: WidgetStateProperty.resolveWith(resolveBorder),
          // Disable the default ripple effect so color state can be clearly seen.
          textStyle: WidgetStateProperty.resolveWith(resolveTextStyle),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius.sm),
            ),
          ),
        ),
        child: buttonContent,
      ),
    );
  }
}
