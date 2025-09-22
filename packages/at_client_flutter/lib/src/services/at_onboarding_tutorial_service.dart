import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const int _tutorialVersion = 2;

enum AtOnboardingTutorialDisplay {
  normal,

  /// show once

  always,

  /// always show tutorial when opening app

  never,

  /// never show tutorial when opening app
}

class AtTutorialServiceInfo {
  int versionInfo;
  bool hasShowSignInPage;
  bool hasShowSignUpPage;

  AtTutorialServiceInfo({
    this.versionInfo = _tutorialVersion,
    this.hasShowSignInPage = false,
    this.hasShowSignUpPage = false,
  });

  factory AtTutorialServiceInfo.fromJson(Map<String, dynamic> json) {
    return AtTutorialServiceInfo(
      versionInfo: json['versionInfo'],
      hasShowSignInPage: json['hasShowSignInPage'],
      hasShowSignUpPage: json['hasShowSignUpPage'],
    );
  }

  Map<String, dynamic> toJson() => {
        "versionInfo": versionInfo,
        "hasShowSignInPage": hasShowSignInPage,
        "hasShowSignUpPage": hasShowSignUpPage,
      };
}

class AtOnboardingTutorialService {
  static const _tutorialInfo = 'tutorialInfo';

  static Future<AtTutorialServiceInfo?> getTutorialInfo() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return AtTutorialServiceInfo.fromJson(
        jsonDecode(
          prefs.getString(_tutorialInfo) ?? '',
        ),
      );
    } catch (e) {
      return null;
    }
  }

  static Future<void> setTutorialInfo(AtTutorialServiceInfo info) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    info.versionInfo = _tutorialVersion;
    final data = jsonEncode(info);
    await prefs.setString(_tutorialInfo, data);
  }

  static Future<bool> hasShowTutorialSignIn() async {
    final tutorialInfo = await getTutorialInfo();
    return tutorialInfo?.hasShowSignInPage ?? false;
  }

  static Future<bool> hasShowTutorialSignUp() async {
    final tutorialInfo = await getTutorialInfo();
    return tutorialInfo?.hasShowSignUpPage ?? false;
  }

  static Future<bool> checkShowTutorial() async {
    final tutorialInfo = await getTutorialInfo();
    final showPageDone = tutorialInfo?.hasShowSignUpPage != true ||
        tutorialInfo?.hasShowSignInPage != true;
    final checkNewestVersion =
        _tutorialVersion > (tutorialInfo?.versionInfo ?? 0);

    if (checkNewestVersion || showPageDone) {
      if (checkNewestVersion) {
        final tutorialInfo = AtTutorialServiceInfo();
        await setTutorialInfo(tutorialInfo);
      }
      return false;
    }
    return true;
  }
}
