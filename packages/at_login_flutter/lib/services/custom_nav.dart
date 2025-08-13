import 'package:flutter/material.dart';

class CustomNav {
  static final CustomNav _singleton = CustomNav._internal();

  CustomNav._internal();
  factory CustomNav() {
    return _singleton;
  }

  push(Widget widget, context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => widget));
    });
  }

  pop(context) {
    Navigator.pop(context);
  }
}
