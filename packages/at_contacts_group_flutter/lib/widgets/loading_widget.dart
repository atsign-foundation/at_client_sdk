import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/widgets/triple_dot_loading.dart';
import 'package:flutter/material.dart';

import 'custom_popup_route.dart';

class LoadingDialog {
  LoadingDialog._();

  static final LoadingDialog _instance = LoadingDialog._();

  factory LoadingDialog() => _instance;
  bool _showing = false;

  show(GlobalKey<NavigatorState> key, {String? text}) {
    if (!_showing) {
      _showing = true;
      key.currentState!
          .push(CustomPopupRoutes(
              pageBuilder: (_, __, ___) {
                return Center(
                  child: (text != null)
                      ? onlyText(text)
                      : const CircularProgressIndicator(),
                );
              },
              barrierDismissible: false))
          .then((_) {});
    }
  }

  hide(GlobalKey<NavigatorState> key) {
    if (_showing) {
      key.currentState!.pop();
      _showing = false;
    }
  }

  onlyText(String text, {TextStyle? style}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            text,
            textScaler: const TextScaler.linear(1),
            style: style ??
                TextStyle(
                    color: ColorConstants.mildGrey,
                    fontSize: 20.toFont,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none),
          ),
        ),
        const TypingIndicator(
          showIndicator: true,
          flashingCircleBrightColor: ColorConstants.dullText,
          flashingCircleDarkColor: ColorConstants.fadedText,
        ),
      ],
    );
  }
}
