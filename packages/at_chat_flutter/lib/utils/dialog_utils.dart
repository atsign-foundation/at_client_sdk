import 'package:at_chat_flutter/utils/colors.dart';
import 'package:at_chat_flutter/widgets/bottom_sheet_dialog.dart';
import 'package:at_chat_flutter/widgets/button_widget.dart';
import 'package:at_common_flutter/services/size_config.dart';
import 'package:flutter/material.dart';

enum ConfirmTypes { approve, cancel }

void showBottomSheetDialog(BuildContext context, Function() deleteCallback) {
  SizeConfig().init(context);
  showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(15.0), topRight: Radius.circular(15.0)),
      ),
      builder: (context) {
        return BottomSheetDialog(deleteCallback);
      });
}

Future<bool> confirm(
  BuildContext context, {
  String? title,
  String? message,
  bool? isPositiveButtonVisible,
  String? positiveActionTitle,
  String? negativeActionTitle,
}) async {
  var confirmedType = await showConfirmDialog(
    context,
    title: title,
    body: message,
    isPositiveButtonVisible: isPositiveButtonVisible,
    positiveAction: positiveActionTitle,
    negativeAction: negativeActionTitle,
  );

  return confirmedType == ConfirmTypes.approve;
}

Future<dynamic> showConfirmDialog(
  BuildContext context, {
  bool? isPositiveButtonVisible,
  String? title,
  String? body,
  String? positiveAction,
  String? negativeAction,
}) async {
  return showDialog<dynamic>(
    context: context,
    barrierDismissible: false, // user must tap button!
    builder: (BuildContext context) {
      return AlertDialog(
        title: Center(
          child: Text(
            title ?? 'Confirm Dialog',
            style:
                const TextStyle(color: CustomColors.defaultColor, fontSize: 20),
          ),
        ),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Text(
                body ?? 'Do you want to delete this?',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black, fontSize: 14),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          Visibility(
            visible: isPositiveButtonVisible ?? true,
            child: ButtonWidget(
              height: 36,
              width: 100.0,
              marginBottom: 16.0,
              marginRight: 4.0,
              colorText: Colors.white,
              borderRadius: const BorderRadius.all(
                Radius.circular(5.0),
              ),
              colorButton: CustomColors.defaultColor,
              onPress: () {
                Navigator.of(context).pop(ConfirmTypes.approve);
              },
              textButton: positiveAction ?? 'Yes',
            ),
          ),
          ButtonWidget(
            height: 36,
            width: 100.0,
            marginBottom: 16.0,
            marginRight: 8.0,
            colorText: CustomColors.defaultColor,
            colorButton: Colors.white,
            borderRadius: const BorderRadius.all(
              Radius.circular(5.0),
            ),
            onPress: () {
              Navigator.of(context).pop(ConfirmTypes.cancel);
            },
            textButton: negativeAction ?? 'No',
          ),
        ],
      );
    },
  );
}
