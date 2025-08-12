import 'package:at_onboarding_flutter/localizations/generated/l10n.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_button.dart';
import 'package:flutter/material.dart';

class AtOnboardingDialog extends StatefulWidget {
  static Future showError({
    required BuildContext context,
    String? title,
    required String message,
    VoidCallback? onCancel,
    ThemeData? themeData,
  }) async {
    return showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: themeData ?? Theme.of(context),
          child: AtOnboardingDialog(
            title: title ?? AtOnboardingLocalizations.current.notice,
            message: message,
            actions: [
              AtOnboardingSecondaryButton(
                child: Text(
                  AtOnboardingLocalizations.current.btn_close,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onCancel?.call();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  final String title;
  final String message;
  final String? subMessage;
  final List<Widget> actions;

  const AtOnboardingDialog({
    Key? key,
    required this.title,
    required this.message,
    required this.actions,
    this.subMessage,
  }) : super(key: key);

  @override
  State<AtOnboardingDialog> createState() => _AtOnboardingDialogState();
}

class _AtOnboardingDialogState extends State<AtOnboardingDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          Visibility(
            visible: (widget.subMessage ?? '').isNotEmpty,
            child: const SizedBox(height: 8),
          ),
          Text(
            widget.subMessage ?? '',
            style: const TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          )
        ],
      ),
      actions: widget.actions,
    );
  }
}
