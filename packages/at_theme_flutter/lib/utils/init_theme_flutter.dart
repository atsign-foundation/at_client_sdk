import 'package:at_theme_flutter/at_theme_flutter.dart';
import 'package:at_theme_flutter/services/theme_service.dart';

void initializeThemeService({rootDomain = 'root.atsign.wtf', rootPort = 64}) {
  ThemeService().initThemeService(rootDomain, rootPort);
}

/// returns [AppTheme] if theme data is saved else returns null.
Future<AppTheme?> getThemeData() async {
  return await ThemeService().getThemeData();
}

/// [setAppTheme] sets theme data with [appTheme]
Future<bool> setAppTheme(AppTheme appTheme) async {
  return await ThemeService().updateThemeData(appTheme);
}
