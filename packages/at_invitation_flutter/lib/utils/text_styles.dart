import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';

class CustomTextStyles {
  CustomTextStyles._();
  static final CustomTextStyles _instance = CustomTextStyles._();
  factory CustomTextStyles() => _instance;

  static TextStyle primaryBold18 = TextStyle(
    color: const Color(0xff131219),
    fontSize: 18.toFont,
    fontWeight: FontWeight.w700,
  );
}
