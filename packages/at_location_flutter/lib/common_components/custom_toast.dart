import 'package:at_location_flutter/utils/constants/colors.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class CustomToast {
  CustomToast._();
  static final CustomToast _instance = CustomToast._();
  factory CustomToast() => _instance;

  /// pass [isError] true to have a red bg, [isSuccess] true to have a green bg.
  void show(String text, BuildContext? context,
      {Color? bgColor,
      Color? textColor,
      int duration = 3,
      bool isError = false,
      bool isSuccess = false}) {
    Fluttertoast.showToast(
        msg: text,
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: isError
            ? AllColors().RED
            : (isSuccess ? AllColors().GREEN : (bgColor ?? AllColors().ORANGE)),
        textColor: textColor ?? Colors.white,
        fontSize: 16.0);
  }
}
