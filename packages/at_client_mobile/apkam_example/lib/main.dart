import 'dart:async';
import 'package:apkam_example/constants.dart';
import 'package:apkam_example/onboarding/pages/onboarding_page.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
// ignore: unused_import
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationSupportDirectory();
  final pref = AtClientPreference()
    ..isLocalStoreRequired = true
    ..namespace = appNamespace
    ..hiveStoragePath = dir.path
    ..commitLogPath = dir.path;

  // AtSignLogger.root_level = 'finest';

  runApp(
    MyApp(
      atClientPreference: pref,
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({required this.atClientPreference, super.key});

  final AtClientPreference atClientPreference;

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: OnboardingPage(
        atClientPreference: widget.atClientPreference,
      ),
    );
  }
}
