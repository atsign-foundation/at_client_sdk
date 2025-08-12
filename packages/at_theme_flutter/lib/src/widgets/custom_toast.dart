import 'package:at_theme_flutter/at_theme_flutter.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class CustomToast {
  CustomToast._();
  static final CustomToast _instance = CustomToast._();
  factory CustomToast() => _instance;

  // ignore: always_declare_return_types
  show(String text, BuildContext context,
      {Color? bgColor, Color? textColor, int duration = 3, int gravity = 0}) {
    final appTheme = AppTheme.of(context);

    Fluttertoast.showToast(
        msg: text,
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: bgColor ?? appTheme.primaryColor,
        textColor: textColor ?? Colors.white,
        fontSize: 16.0);
  }
}
