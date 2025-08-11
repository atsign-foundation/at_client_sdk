import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_location_flutter/service/at_location_notification_listener.dart';
import 'package:at_location_flutter/utils/constants/colors.dart';
import 'package:at_location_flutter/utils/constants/text_strings.dart';
import 'package:at_location_flutter/utils/constants/text_styles.dart';
import 'package:flutter/material.dart';

/// Displays a confirmation dialog with the given [title]
Future<void> confirmationDialog(String title,
    {required Function() onYesPressed, Function()? onNoPressed}) async {
  return showDialog<void>(
    context: AtLocationNotificationListener().navKey.currentContext!,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return StatefulBuilder(builder: (_context, _setDialogState) {
        var _dialogLoading = false;

        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(15, 30, 15, 20),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: CustomTextStyles().grey16,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                _dialogLoading
                    ? const CircularProgressIndicator()
                    : CustomButton(
                        onPressed: () async {
                          _setDialogState(() {
                            _dialogLoading = true;
                          });

                          await onYesPressed();

                          _setDialogState(() {
                            _dialogLoading = false;
                          });
                          Navigator.of(context).pop();
                        },
                        buttonColor: AllColors().Black,
                        width: 164.toWidth,
                        height: 48.toHeight,
                        buttonText: AllText().YES,
                        fontColor: AllColors().WHITE,
                      ),
                const SizedBox(height: 5),
                _dialogLoading
                    ? const SizedBox()
                    : CustomButton(
                        onPressed: () async {
                          if (onNoPressed != null) {
                            await onNoPressed();
                          }
                          Navigator.of(context).pop();
                        },
                        buttonColor: AllColors().WHITE,
                        width: 140.toWidth,
                        height: 36.toHeight,
                        buttonText: AllText().NO,
                        fontColor: AllColors().Black,
                      ),
              ],
            ),
          ),
        );
      });
    },
  );
}
