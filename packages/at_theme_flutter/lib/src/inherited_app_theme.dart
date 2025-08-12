import 'package:flutter/widgets.dart';

import 'app_theme.dart';

class InheritedAppTheme extends InheritedWidget {
  /// Creates [InheritedWidget] from a provided [AppTheme] class
  const InheritedAppTheme({
    Key? key,
    required this.theme,
    required Widget child,
  }) : super(key: key, child: child);

  /// Represents chat theme
  final AppTheme theme;

  @override
  bool updateShouldNotify(InheritedAppTheme oldWidget) =>
      theme.hashCode != oldWidget.theme.hashCode;
}
