import 'package:at_sync_ui_flutter/at_sync_material.dart';
import 'package:flutter/material.dart';

abstract class AtOnboardingButton extends StatelessWidget {
  final Color? backgroundColor;
  final Color? borderColor;
  final double? height;
  final double? width;
  final double? borderRadius;
  final bool isLoading;
  final VoidCallback? onPressed;
  final Widget child;

  const AtOnboardingButton({
    Key? key,
    required this.backgroundColor,
    required this.borderColor,
    required this.height,
    required this.width,
    required this.borderRadius,
    required this.isLoading,
    required this.onPressed,
    required this.child,
  }) : super(key: key);
}

class AtOnboardingPrimaryButton extends AtOnboardingButton {
  const AtOnboardingPrimaryButton({
    Key? key,
    Color? backgroundColor,
    Color? borderColor,
    double? height,
    double? width,
    double? borderRadius,
    bool isLoading = false,
    VoidCallback? onPressed,
    required Widget child,
  }) : super(
          key: key,
          backgroundColor: backgroundColor,
          borderColor: borderColor,
          height: height,
          width: width,
          borderRadius: borderRadius,
          isLoading: isLoading,
          onPressed: onPressed,
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    ThemeData themeData = Theme.of(context);
    return SizedBox(
      height: height,
      width: width,
      child: TextButton(
        onPressed: isLoading ? null : onPressed,
        style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all<Color>(
                backgroundColor ?? themeData.primaryColor),
            foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
            shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(borderRadius ?? 4),
                    side: BorderSide(
                        color: borderColor ?? themeData.primaryColor)))),
        child: Container(
          child: isLoading ? const AtSyncIndicator(color: Colors.white) : child,
        ),
      ),
    );
  }
}

class AtOnboardingSecondaryButton extends AtOnboardingButton {
  const AtOnboardingSecondaryButton({
    Key? key,
    Color? backgroundColor,
    Color? borderColor,
    double? height,
    double? width,
    double? borderRadius,
    bool isLoading = false,
    VoidCallback? onPressed,
    required Widget child,
  }) : super(
          key: key,
          backgroundColor: backgroundColor,
          borderColor: borderColor,
          height: height,
          width: width,
          borderRadius: borderRadius,
          isLoading: isLoading,
          onPressed: onPressed,
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    ThemeData themeData = Theme.of(context);
    return SizedBox(
      height: height,
      width: width,
      child: TextButton(
        onPressed: isLoading ? null : onPressed,
        style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all<Color>(
                backgroundColor ?? Colors.transparent),
            foregroundColor:
                WidgetStateProperty.all<Color>(themeData.primaryColor),
            shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(borderRadius ?? 4),
                    side: BorderSide(
                        color: borderColor ?? themeData.primaryColor)))),
        child: Container(
          child: isLoading
              ? AtSyncIndicator(color: themeData.primaryColor)
              : child,
        ),
      ),
    );
  }
}
