import 'package:flutter/material.dart';

class LoadingDialog extends StatelessWidget {
  final String title;
  final String description;
  final ThemeData? themeData;

  const LoadingDialog({
    super.key,
    required this.title,
    required this.description,
    this.themeData,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Loading indicator
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    themeData?.colorScheme.secondary ?? Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: themeData?.colorScheme.primary ?? Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: themeData?.colorScheme.secondary ?? Colors.black87,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show the loading dialog
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String description,
    ThemeData? themeData,
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => LoadingDialog(
        title: title,
        description: description,
        themeData: themeData,
      ),
    );
  }

  /// Hide the loading dialog
  static void hide(BuildContext context) {
    Navigator.of(context).pop();
  }
}
