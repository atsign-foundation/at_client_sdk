import 'package:flutter/material.dart';

class TestMaterialApp extends StatelessWidget {
  final Widget home;

  const TestMaterialApp({required Key key, required this.home})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Widget Test', home: home);
  }
}
