import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_events_flutter/services/at_event_notification_listener.dart';
import 'package:at_events_flutter/utils/colors.dart';
import 'package:flutter/material.dart';

import 'custom_popup_route.dart';
import 'triple_dot_loading.dart';

class LoadingDialog {
  LoadingDialog._();

  static final LoadingDialog _instance = LoadingDialog._();

  factory LoadingDialog() => _instance;
  bool _showing = false;

  /// display a custom popup with an optional text parameter
  void show({String? text}) {
    if (!_showing) {
      _showing = true;
      AtEventNotificationListener()
          .navKey!
          .currentState!
          .push(CustomPopupRoutes(
              pageBuilder: (_, __, ___) {
                return Center(
                  child: (text != null)
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                text,
                                textScaler: const TextScaler.linear(1),
                                style: TextStyle(
                                    color: AllColors().MILD_GREY,
                                    fontSize: 20.toFont,
                                    fontWeight: FontWeight.w400,
                                    decoration: TextDecoration.none),
                              ),
                            ),
                            TypingIndicator(
                              showIndicator: true,
                              flashingCircleBrightColor: AllColors().LIGHT_GREY,
                              flashingCircleDarkColor: AllColors().DARK_GREY,
                            ),
                          ],
                        )
                      : const CircularProgressIndicator(),
                );
              },
              barrierDismissible: false))
          .then((_) {});
    }
  }

  /// hide the currently displayed popup
  void hide() {
    if (_showing) {
      AtEventNotificationListener().navKey!.currentState!.pop();
      _showing = false;
    }
  }
}
