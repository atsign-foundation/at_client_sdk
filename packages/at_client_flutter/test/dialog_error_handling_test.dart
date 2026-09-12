import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_client_flutter/src/widgets/apkam_dialog.dart';
import 'package:at_client_flutter/src/widgets/cram_dialog.dart';
import 'package:at_client_flutter/src/widgets/pkam_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtsignFlows extends Mock implements AtsignFlows {}

class MockAtClient extends Mock implements AtClient {}

class MockPendingEnrollment extends Mock implements PendingEnrollment {}

class FakeAtClientPreference extends Fake implements AtClientPreference {}

/// The three dialogs over the lifecycle verbs: a failure is shown and the
/// dialog answers as it always has, and what reaches the verb is what the
/// caller asked for. The verbs are async, so a failure reaches a dialog as a
/// failed future, which is how the stubs fail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(InMemoryAtKeysIo());
    registerFallbackValue(FakeAtClientPreference());
  });

  late MockAtsignFlows flows;
  setUp(() => flows = MockAtsignFlows());

  Future<void> pumpOpener(
    WidgetTester tester,
    Widget Function(BuildContext) dialog,
    void Function(Object?) onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                onResult(
                  await showDialog<Object?>(context: context, builder: dialog),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  group('Dialog error handling', () {
    testWidgets('PkamDialog dismisses and shows snackbar on an open failure', (
      tester,
    ) async {
      when(
        () => flows.open(
          any(),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          storage: any(named: 'storage'),
        ),
      ).thenAnswer(
        (_) => Future.error(Exception('the atServer refused this device')),
      );

      Object? result = 'unset';
      await pumpOpener(
        tester,
        (context) => PkamDialog(
          atSign: '@alice',
          keys: InMemoryAtKeysIo(),
          preference: AtClientPreference(),
          flows: flows,
        ),
        (r) => result = r,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(result, isNull, reason: 'the dialog popped with no client');
      expect(find.textContaining('Authentication failed'), findsOneWidget);
    });

    testWidgets('CramDialog dismisses and shows snackbar on an activation '
        'failure', (tester) async {
      when(
        () => flows.activate(
          any(),
          cramSecret: any(named: 'cramSecret'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          storage: any(named: 'storage'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer(
        (_) => Future.error(Exception('Registrar authentication failed')),
      );

      Object? result = 'unset';
      await pumpOpener(
        tester,
        (context) => CramDialog(
          atSign: '@alice',
          cramKey: '@alice:activation_key:the-secret',
          preference: AtClientPreference(),
          keys: InMemoryAtKeysIo(),
          flows: flows,
        ),
        (r) => result = r,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.textContaining('Onboarding failed'), findsOneWidget);
      // The registrar's spelling of the key is unwrapped to the bare secret.
      verify(
        () => flows.activate(
          '@alice',
          cramSecret: 'the-secret',
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          storage: any(named: 'storage'),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);
    });

    testWidgets('ApkamActivationDialog shows snackbar on an enrollment error '
        'and stays open', (tester) async {
      when(
        () => flows.resumeEnrollment(
          any(),
          app: any(named: 'app'),
          device: any(named: 'device'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => flows.enroll(
          any(),
          otp: any(named: 'otp'),
          app: any(named: 'app'),
          device: any(named: 'device'),
          namespaces: any(named: 'namespaces'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          signingAlgo: any(named: 'signingAlgo'),
          keyExchangeMode: any(named: 'keyExchangeMode'),
        ),
      ).thenAnswer((_) => Future.error(Exception('invalid otp')));

      Object? result = 'unset';
      await pumpOpener(
        tester,
        (context) => ApkamActivationDialog(
          atSign: '@alice',
          rootDomain: AtRootDomain.atsignDomain,
          appName: 'app',
          deviceName: 'device',
          namespaces: const {'*': 'rw'},
          preference: AtClientPreference(),
          keys: InMemoryAtKeysIo(),
          themeData: ThemeData(),
          flows: flows,
        ),
        (r) => result = r,
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
      // retry, so `result` is still unset only because showDialog hasn't
      // returned — not because of a pop(null).
      expect(result, 'unset');
      expect(find.textContaining('Activation failed'), findsOneWidget);
    });

    testWidgets('ApkamActivationDialog enrols towards the caller\'s keys and '
        'pops the client the approval opens', (tester) async {
      final destination = InMemoryAtKeysIo();
      final pending = MockPendingEnrollment();
      final client = MockAtClient();
      when(
        () => flows.resumeEnrollment(
          any(),
          app: any(named: 'app'),
          device: any(named: 'device'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => flows.enroll(
          any(),
          otp: any(named: 'otp'),
          app: any(named: 'app'),
          device: any(named: 'device'),
          namespaces: any(named: 'namespaces'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          signingAlgo: any(named: 'signingAlgo'),
          keyExchangeMode: any(named: 'keyExchangeMode'),
        ),
      ).thenAnswer((_) async => pending);
      when(() => pending.enrollmentId).thenReturn('enroll-1');
      when(() => pending.progress).thenAnswer((_) => const Stream.empty());
      when(
        () => pending.client(any(), storage: any(named: 'storage')),
      ).thenAnswer((_) async => client);

      Object? result = 'unset';
      await pumpOpener(
        tester,
        (context) => ApkamActivationDialog(
          atSign: '@alice',
          rootDomain: AtRootDomain.atsignDomain,
          appName: 'app',
          deviceName: 'device',
          namespaces: const {'*': 'rw'},
          preference: AtClientPreference(),
          keys: destination,
          themeData: ThemeData(),
          flows: flows,
        ),
        (r) => result = r,
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(EditableText), '123456');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(result, same(client));
      final keys = verify(
        () => flows.enroll(
          '@alice',
          otp: '123456',
          app: 'app',
          device: 'device',
          namespaces: const {'*': 'rw'},
          keys: captureAny(named: 'keys'),
          preference: any(named: 'preference'),
          signingAlgo: any(named: 'signingAlgo'),
          keyExchangeMode: any(named: 'keyExchangeMode'),
        ),
      ).captured.single;
      expect(
        keys,
        same(destination),
        reason:
            'the request files its keys in the caller\'s own store, not '
            'a copy and not one this widget chose: it is the resume record '
            'and where the completed keys land',
      );
    });

    testWidgets('ApkamActivationDialog resumes a request its store holds '
        'without asking for a passcode', (tester) async {
      final pending = MockPendingEnrollment();
      final client = MockAtClient();
      when(
        () => flows.resumeEnrollment(
          any(),
          app: any(named: 'app'),
          device: any(named: 'device'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
        ),
      ).thenAnswer((_) async => pending);
      when(() => pending.enrollmentId).thenReturn('enroll-1');
      when(() => pending.progress).thenAnswer((_) => const Stream.empty());
      when(
        () => pending.client(any(), storage: any(named: 'storage')),
      ).thenAnswer((_) async => client);

      Object? result = 'unset';
      await pumpOpener(
        tester,
        (context) => ApkamActivationDialog(
          atSign: '@alice',
          rootDomain: AtRootDomain.atsignDomain,
          appName: 'app',
          deviceName: 'device',
          namespaces: const {'*': 'rw'},
          preference: AtClientPreference(),
          keys: InMemoryAtKeysIo(),
          themeData: ThemeData(),
          flows: flows,
        ),
        (r) => result = r,
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(result, same(client));
      verifyNever(
        () => flows.enroll(
          any(),
          otp: any(named: 'otp'),
          app: any(named: 'app'),
          device: any(named: 'device'),
          namespaces: any(named: 'namespaces'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          signingAlgo: any(named: 'signingAlgo'),
          keyExchangeMode: any(named: 'keyExchangeMode'),
        ),
      );
    });
  });
}
