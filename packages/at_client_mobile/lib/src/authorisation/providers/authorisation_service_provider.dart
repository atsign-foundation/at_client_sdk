import 'package:flutter/widgets.dart';

import '../services/authorisation_service.dart';

class AuthorisationServiceProvider extends InheritedWidget {
  const AuthorisationServiceProvider({
    required this.service,
    required super.child,
    super.key,
  });

  final AuthorisationService service;

  static AuthorisationService of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AuthorisationServiceProvider>()!
        .service;
  }

  @override
  bool updateShouldNotify(AuthorisationServiceProvider oldWidget) {
    return oldWidget.service != service;
  }
}
