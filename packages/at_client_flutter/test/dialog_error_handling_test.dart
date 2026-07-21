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

      // PkamDialog kicks off authentication in initState, so opening the dialog
      // is enough to drive the error path.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The dialog pops with null and surfaces a fixed, non-timeout message.
      expect(result, isNull);
      expect(find.textContaining('Authentication failed'), findsOneWidget);
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

      // CramDialog kicks off onboarding in initState.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The dialog pops with null and surfaces a fixed, non-timeout message.
      expect(result, isNull);
      expect(find.textContaining('Onboarding failed'), findsOneWidget);
    });

    testWidgets(
      'ApkamActivationDialog shows snackbar on enrollment error',
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

        // pumpAndSettle can't be used with this dialog: the autofocused Pinput
        // keeps a blinking cursor animating forever, so nothing ever "settles".
        // Pump fixed frames instead.
        await tester.tap(find.text('open'));
        await tester.pump(); // start the dialog route transition
        await tester.pump(const Duration(milliseconds: 400)); // finish it

        // The dialog uses a Pinput (single editable field), not six TextFields.
        // Entering all six digits triggers Pinput.onCompleted -> _submitOtp.
        await tester.enterText(find.byType(EditableText), '123456');
        await tester.pump(); // run onCompleted -> _submitOtp (sets _isLoading)
        await tester.pump(); // let the enrollment error path run and finish
        await tester.pump(const Duration(milliseconds: 750)); // SnackBar entrance

        // Unlike PKAM/CRAM, the APKAM dialog stays open on error so the user can
        // retry, so `result` is still null only because showDialog hasn't
        // returned — not because of a pop(null).
        expect(result, isNull);
        expect(find.textContaining('Activation failed'), findsOneWidget);
      },
    );
  });
}
