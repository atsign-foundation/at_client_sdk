import 'package:at_location_flutter/service/at_location_notification_listener.dart';
import 'package:flutter/material.dart';

import 'custom_popup_route.dart';

class LoadingDialog {
  LoadingDialog._();

  static final LoadingDialog _instance = LoadingDialog._();

  factory LoadingDialog() => _instance;
  bool _showing = false;

  /// Shows a custom popup with a CircularProgressIndicator
  void show() {
    if (!_showing) {
      _showing = true;
      AtLocationNotificationListener()
          .navKey
          .currentState!
          .push(CustomPopupRoutes(
              pageBuilder: (_, __, ___) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              },
              barrierDismissible: false))
          .then((_) {});
    }
  }

  /// Hides the custom popup
  void hide() {
    if (_showing) {
      AtLocationNotificationListener().navKey.currentState!.pop();
      _showing = false;
    }
  }
}
