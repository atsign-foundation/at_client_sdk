import 'package:flutter/material.dart';

class LoadingDialog extends StatelessWidget {
  final String title;
  final String description;
  final Color primaryColor;
  final Color secondaryColor;
  final Color? progressColor;

  const LoadingDialog({
    super.key,
    required this.title,
    required this.description,
    this.primaryColor = Colors.black87,
    this.secondaryColor = Colors.black87,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
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
                  progressColor ?? primaryColor,
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
                color: primaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: secondaryColor,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Show the loading dialog
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String description,
    Color primaryColor = Colors.black87,
    Color secondaryColor = Colors.black87,
    Color? progressColor,
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => LoadingDialog(
        title: title,
        description: description,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        progressColor: progressColor,
      ),
    );
  }

  /// Hide the loading dialog
  static void hide(BuildContext context) {
    Navigator.of(context).pop();
  }
}