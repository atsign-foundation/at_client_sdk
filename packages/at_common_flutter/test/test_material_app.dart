import 'package:flutter/material.dart';

class TestMaterialApp extends StatelessWidget {
  final Widget? home;

  const TestMaterialApp({Key? key, this.home}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Widget Test', home: home);
    // return MediaQuery(
    //     data: MediaQueryData(),
    //     child: MaterialApp(title: 'Widget Test', home: home));
  }
}
