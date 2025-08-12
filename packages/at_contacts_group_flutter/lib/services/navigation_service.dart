import 'package:flutter/material.dart';

class NavService {
  static GlobalKey<NavigatorState> groupPckgLeftHalfNavKey = GlobalKey();
  static GlobalKey<NavigatorState> groupPckgRightHalfNavKey = GlobalKey();

  static void resetKeys() {
    groupPckgLeftHalfNavKey = GlobalKey();
    groupPckgRightHalfNavKey = GlobalKey();
  }
}
