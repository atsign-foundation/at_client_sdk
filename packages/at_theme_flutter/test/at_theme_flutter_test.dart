import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_theme_flutter/at_theme_flutter.dart';
import 'package:at_theme_flutter/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  @override
  Future<bool> put(AtKey key, dynamic value,
      {bool isDedicated = false, PutRequestOptions? putRequestOptions}) async {
    return true;
  }

  @override
  Future<AtValue> get(
    AtKey key, {
    bool isDedicated = false,
    GetRequestOptions? getRequestOptions,
  }) async {
    return AtValue()
      ..value = AppTheme(
        brightness: Brightness.light,
        primaryColor: const Color(0xfff44336),
        secondaryColor: Colors.orange,
        backgroundColor: Colors.white,
      ).encoded();
  }
}

void main() {
  MockAtClientManager mockAtClientManager = MockAtClientManager();

  group('Theme data tests', () {
    var mockAtClient = MockAtClient();

    when(() => mockAtClientManager.atClient).thenAnswer((_) => mockAtClient);
    ThemeService().atClientManager = mockAtClientManager;

    test('Update theme data', () async {
      var updateThemeDataResult = await ThemeService().updateThemeData(
        AppTheme(
          brightness: Brightness.light,
          primaryColor: Colors.red,
          secondaryColor: Colors.orange,
          backgroundColor: Colors.white,
        ),
      );
      expect(updateThemeDataResult, true);
    });

    test('Get theme data', () async {
      var updateThemeDataResult = await ThemeService().getThemeData();
      expect(updateThemeDataResult.runtimeType, AppTheme);

      expect(updateThemeDataResult!.primaryColor, const Color(0xfff44336));
    });
  });
}
