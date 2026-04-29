import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_client_flutter/src/services/enrollment_service.dart';
import 'package:at_client_flutter/src/widgets/apkam_dialog.dart';
import 'package:at_client_flutter/src/widgets/cram_dialog.dart';
import 'package:at_client_flutter/src/widgets/pkam_dialog.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

class MockFlutterEnrollmentService extends Mock
    implements FlutterEnrollmentService {}

class FakeAtAuthRequest extends Fake implements AtAuthRequest {}

class FakeAtOnboardingRequest extends Fake implements AtOnboardingRequest {}

class FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(FakeAtAuthRequest());
    registerFallbackValue(FakeAtOnboardingRequest());
    registerFallbackValue(FakeEnrollmentRequest());
  });

  group('Dialog error handling', () {
    testWidgets('PkamDialog dismisses and shows snackbar on auth error', (
      tester,
    ) async {
      final mockAuthService = MockAuthService();
      when(
        () => mockAuthService.progressStream,
      ).thenAnswer((_) => const Stream<ProgressEvent>.empty());
      when(
        () => mockAuthService.authenticate(
          any(),
          backupKeys: any(named: 'backupKeys'),
        ),
      ).thenAnswer((_) async {
        throw Exception(
          'Registrar authentication failed: invalid or missing API key.',
        );
      });

      AtAuthResponse? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<AtAuthResponse>(
                    context: context,
                    builder: (context) => PkamDialog(
                      request: AtAuthRequest('@alice', atAuthKeys: AtKeys()),
                      authService: mockAuthService,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.textContaining('invalid or missing API key'), findsOneWidget);
    });

    testWidgets('CramDialog dismisses and shows snackbar on onboarding error', (
      tester,
    ) async {
      final mockAuthService = MockAuthService();
      when(
        () => mockAuthService.progressStream,
      ).thenAnswer((_) => const Stream<ProgressEvent>.empty());
      when(() => mockAuthService.onboard(any(), any())).thenAnswer((_) async {
        throw Exception('Onboarding failed due to network error.');
      });

      AtOnboardingResponse? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<AtOnboardingResponse>(
                    context: context,
                    builder: (context) => CramDialog(
                      request: AtOnboardingRequest('@alice'),
                      cramKey: '@alice:activation_key:secret',
                      authService: mockAuthService,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.textContaining('network error'), findsOneWidget);
    });

    testWidgets(
      'ApkamActivationDialog dismisses and shows snackbar on enrollment error',
      (tester) async {
        final mockEnrollmentService = MockFlutterEnrollmentService();
        when(
          () => mockEnrollmentService.enroll(
            any(),
            waitForApproval: any(named: 'waitForApproval'),
          ),
        ).thenAnswer((_) async {
          throw Exception(
            'Registrar authentication failed: invalid or missing API key.',
          );
        });

        AtEnrollmentResponse? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<AtEnrollmentResponse>(
                      context: context,
                      builder: (context) => ApkamActivationDialog(
                        atSign: '@alice',
                        rootDomain: AtRootDomain.atsignDomain,
                        appName: 'app',
                        deviceName: 'device',
                        namespaces: const {'*': 'rw'},
                        themeData: Theme.of(context),
                        enrollmentService: mockEnrollmentService,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(6));
        for (int i = 0; i < 6; i++) {
          await tester.enterText(textFields.at(i), '${i + 1}');
        }
        await tester.tap(find.widgetWithText(ElevatedButton, 'Activate APKAM'));
        await tester.pumpAndSettle();

        expect(result, isNull);
        expect(
          find.textContaining('invalid or missing API key'),
          findsOneWidget,
        );
      },
    );
  });
}
