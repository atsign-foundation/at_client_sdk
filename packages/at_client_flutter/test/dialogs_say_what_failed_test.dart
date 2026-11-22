import 'dart:async';
import 'dart:io';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_utils/at_progress.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_path_provider.dart';
import 'loopback_flows.dart';

class _MockAtsignFlows extends Mock implements AtsignFlows {}

class _MockRegistrarService extends Mock implements RegistrarService {}

class _MockBiometricStorage extends Mock implements BiometricStorage {}

class _MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

class _FakeAtClientPreference extends Fake implements AtClientPreference {}

class _FakeAtClientStorage extends Fake implements AtClientStorage {}

class _MockAtClient extends Mock implements AtClient {}

/// Records each route the navigator pops.
class _PopRecorder extends NavigatorObserver {
  final popped = <Route<dynamic>>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add(route);
}

/// The onboarding dialogs say what failed, with no stack trace.
///
/// Catalogue: features/at_client_flutter/dialogs_say_what_failed.feature
///
/// A dialog runs its operation through a mocked `AtsignFlows`, except where
/// the failure is the keychain's: there the real verbs run on a keychain
/// whose platform store is mocked, and fail before anything is sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const atSign = '@alice';
  const keychain = "this device's keychain";
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        MethodChannel('dev.fluttercommunity.plus/package_info'),
        (MethodCall methodCall) async => methodCall.method == 'getAll'
            ? {
                'appName': 'test',
                'packageName': 'test',
                'version': '1.0.0',
                'buildNumber': '1',
              }
            : null,
      );

  late _MockAtsignFlows flows;
  late int closedPort;

  setUpAll(() async {
    registerFallbackValue(InMemoryAtKeysIo());
    registerFallbackValue(_FakeAtClientPreference());
    registerFallbackValue(_FakeAtClientStorage());
    PathProviderPlatform.instance = FakePathProvider('/app/support');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    closedPort = socket.port;
    await socket.close();
  });

  setUp(() {
    KeychainStorage.isWindows = false;
    flows = _MockAtsignFlows();
  });

  /// A preference whose atDirectory is a loopback port nothing listens on.
  AtClientPreference loopback() => AtClientPreference()
    ..rootDomain = InternetAddress.loopbackIPv4.address
    ..rootPort = closedPort;

  /// A keychain whose platform store answers each read with [read].
  KeychainAtKeysIo keychainReading(Future<String?> Function() read) {
    final biometricStorage = _MockBiometricStorage();
    when(
      () => biometricStorage.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((_) async {
      final file = _MockBiometricStorageFile();
      when(file.read).thenAnswer((_) => read());
      return file;
    });
    return KeychainAtKeysIo(
      keychainStorage: KeychainStorage(biometricStorage: biometricStorage),
    );
  }

  void whenOpenFails(Object error) => when(
    () => flows.open(
      any(),
      keys: any(named: 'keys'),
      preference: any(named: 'preference'),
      storage: any(named: 'storage'),
      lookUps: any(named: 'lookUps'),
    ),
  ).thenAnswer((_) => Future.error(error));

  /// Pumps an app whose button shows [dialog], and returns what the dialog
  /// popped with once it has, or 'unset' while it is open.
  Future<Object? Function()> pumpOpener(
    WidgetTester tester,
    Widget Function(BuildContext) dialog,
  ) async {
    Object? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<Object?>(
                  context: context,
                  builder: dialog,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    return () => result;
  }

  Widget pkamDialog(BuildContext _, {AtKeysIo? keys, AtsignFlows? using}) =>
      PkamDialog(
        atSign: atSign,
        keys: keys ?? InMemoryAtKeysIo(),
        preference: loopback(),
        flows: using ?? flows,
      );

  /// Lets real time pass, frame by frame, until a snack bar is up: the real
  /// verbs' own work runs on real time, and a dialog's progress indicator
  /// never settles.
  Future<void> letRealTimePass(WidgetTester tester) async {
    for (var i = 0; i < 200 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 750));
  }

  /// What [snackBar] text shows; fails unless exactly one snack bar is up.
  String shown(WidgetTester tester) =>
      (tester.widget<SnackBar>(find.byType(SnackBar)).content as Text).data!;

  testWidgets('A dialog with no keys shows the keys message', (tester) async {
    final keys = keychainReading(() async => null);
    final result = await pumpOpener(
      tester,
      (context) =>
          pkamDialog(context, keys: keys, using: const LoopbackFlows()),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      shown(tester),
      'No keys for $atSign in the AtKeys store ($keychain), so this device '
      'cannot authenticate as $atSign. Activate $atSign, enroll this device, '
      'or use the keyfile it already has.',
    );
    expect(result(), isNull, reason: 'the dialog returns no client');
  });

  group(
    'Keys with no credential, or an enrollment PkamDialog cannot wait on, say '
    'what to do in plain words',
    () {
      testWidgets('hold no credential', (tester) async {
        whenOpenFails(AtNoCredentialException(atSign));
        final result = await pumpOpener(tester, pkamDialog);

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          shown(tester),
          "This device's enrollment for $atSign was denied, cancelled or "
          'expired, or never completed. Enroll this device again to use '
          '$atSign here.',
        );
        expect(result(), isNull, reason: 'the dialog returns no client');
      });
    },
  );

  group('An atServer refusal shows its cause in plain words', () {
    final examples = {
      AtConnectionCause.revoked:
          "This device's access to $atSign has been revoked.",
      AtConnectionCause.enrollmentNotApproved:
          "This device's enrollment for $atSign has not been approved yet.",
      AtConnectionCause.enrollmentDenied:
          "This device's enrollment for $atSign was denied.",
      AtConnectionCause.noAtServer: '$atSign is not in the atDirectory.',
    };
    for (final MapEntry(key: cause, value: message) in examples.entries) {
      testWidgets(cause.name, (tester) async {
        whenOpenFails(
          AtOpenRefusedException(
            atSign,
            cause == AtConnectionCause.noAtServer
                ? AtConnectionState.offline(cause)
                : AtConnectionState.refused(cause),
          ),
        );
        final result = await pumpOpener(tester, pkamDialog);

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(shown(tester), message);
        expect(result(), isNull, reason: 'the dialog returns no client');
      });
    }
  });

  testWidgets('A network failure still says to check the connection', (
    tester,
  ) async {
    // NOTE: the real verbs, enrolling against an atDirectory on a loopback
    // port nothing listens on.
    await pumpOpener(
      tester,
      (context) => ApkamActivationDialog(
        atSign: atSign,
        rootDomain: AtRootDomain(
          InternetAddress.loopbackIPv4.address,
          closedPort,
        ),
        appName: 'app',
        deviceName: 'device',
        namespaces: const {'*': 'rw'},
        preference: loopback(),
        keys: InMemoryAtKeysIo(),
        themeData: ThemeData(),
        flows: const LoopbackFlows(),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(EditableText), '123456');
    await letRealTimePass(tester);

    expect(
      shown(tester),
      'The atServer for $atSign could not be reached. Please check your '
      'connection and try again.',
    );
  });

  testWidgets('PkamDialog shows its own advice for a wait that ran out', (
    tester,
  ) async {
    whenOpenFails(AtTimeoutException('the atServer did not answer'));
    await pumpOpener(tester, pkamDialog);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      shown(tester),
      'Authentication timed out — the atServer could not be reached. Please '
      'check your connection and try again.',
    );
  });

  testWidgets('CramDialog shows its provisioning advice for a wait that ran '
      'out', (tester) async {
    when(
      () => flows.activate(
        any(),
        cramSecret: any(named: 'cramSecret'),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        storage: any(named: 'storage'),
        lookUps: any(named: 'lookUps'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) => Future.error(AtTimeoutException('still provisioning')));
    await pumpOpener(
      tester,
      (context) => CramDialog(
        atSign: atSign,
        cramKey: 'cram-secret-6d1f0b',
        preference: loopback(),
        keys: InMemoryAtKeysIo(),
        flows: flows,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      shown(tester),
      'Onboarding is taking longer than expected — your atSign may still be '
      'provisioning. Please try again in a moment.',
    );
  });

  testWidgets('Activation with a keychain it cannot read says so', (
    tester,
  ) async {
    final keys = keychainReading(
      () async => throw PlatformException(
        code: 'AuthError:UserCanceled',
        message: 'User canceled the operation.',
      ),
    );
    await pumpOpener(
      tester,
      (context) => CramDialog(
        atSign: atSign,
        cramKey: 'cram-secret-6d1f0b',
        preference: loopback(),
        keys: keys,
        flows: const LoopbackFlows(),
      ),
    );

    await tester.tap(find.text('open'));
    await letRealTimePass(tester);

    expect(
      shown(tester),
      allOf(
        startsWith(
          'The keys for $atSign in the AtKeys store ($keychain) could not '
          'be read: ',
        ),
        contains('User canceled the operation.'),
        isNot(contains('Please check your connection')),
      ),
    );
  });

  testWidgets('ApkamActivationDialog shows its own advice for a wait that ran '
      'out', (tester) async {
    when(
      () => flows.resumeEnrollment(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        lookUps: any(named: 'lookUps'),
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
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer(
      (_) => Future.error(AtTimeoutException('the atServer did not answer')),
    );
    await pumpOpener(
      tester,
      (context) => ApkamActivationDialog(
        atSign: atSign,
        rootDomain: AtRootDomain(
          InternetAddress.loopbackIPv4.address,
          closedPort,
        ),
        appName: 'app',
        deviceName: 'device',
        namespaces: const {'*': 'rw'},
        preference: loopback(),
        keys: InMemoryAtKeysIo(),
        themeData: ThemeData(),
        flows: flows,
      ),
    );

    // NOTE: the autofocused Pinput animates its cursor for ever, so fixed
    // frames are pumped rather than settling.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(EditableText), '123456');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(
      shown(tester),
      'Activation timed out — the atServer could not be reached. Please '
      'check your connection and try again.',
    );
  });

  group('RegistrarCramDialog says the registrar could not be reached', () {
    for (final (name, error) in [
      ('for a connection that failed', const SocketException('refused')),
      ('for a wait that ran out', TimeoutException('no answer')),
    ]) {
      testWidgets(name, (tester) async {
        final registrar = _MockRegistrarService();
        when(
          () => registrar.verifyActivation(
            atSign: any(named: 'atSign'),
            otp: any(named: 'otp'),
          ),
        ).thenAnswer((_) => Future.error(error));
        await pumpOpener(
          tester,
          (context) => RegistrarCramDialog(
            atSign: atSign,
            registrar: registrar,
            themeData: ThemeData(),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.byType(EditableText), 'ABCD');
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));

        expect(
          shown(tester),
          'The registrar could not be reached. Please check your connection '
          'and try again.',
        );
        // NOTE: the resend countdown runs until it has finished.
        await tester.pump(const Duration(seconds: 31));
      });
    }
  });

  group("Anything else shows the exception's message and no stack trace", () {
    const message = 'Something went wrong with $atSign: boom';

    testWidgets('PkamDialog', (tester) async {
      whenOpenFails(Exception('boom'));
      await pumpOpener(tester, pkamDialog);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(shown(tester), message);
    });

    testWidgets('CramDialog', (tester) async {
      when(
        () => flows.activate(
          any(),
          cramSecret: any(named: 'cramSecret'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          storage: any(named: 'storage'),
          lookUps: any(named: 'lookUps'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) => Future.error(Exception('boom')));
      await pumpOpener(
        tester,
        (context) => CramDialog(
          atSign: atSign,
          cramKey: 'cram-secret-6d1f0b',
          preference: loopback(),
          keys: InMemoryAtKeysIo(),
          flows: flows,
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(shown(tester), message);
    });

    testWidgets('ApkamDialog', (tester) async {
      when(
        () => flows.resumeEnrollment(
          any(),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          lookUps: any(named: 'lookUps'),
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
          lookUps: any(named: 'lookUps'),
        ),
      ).thenAnswer((_) => Future.error(Exception('boom')));
      await pumpOpener(
        tester,
        (context) => ApkamActivationDialog(
          atSign: atSign,
          rootDomain: AtRootDomain(
            InternetAddress.loopbackIPv4.address,
            closedPort,
          ),
          appName: 'app',
          deviceName: 'device',
          namespaces: const {'*': 'rw'},
          preference: loopback(),
          keys: InMemoryAtKeysIo(),
          themeData: ThemeData(),
          flows: flows,
        ),
      );

      // NOTE: the autofocused Pinput animates its cursor for ever, so fixed
      // frames are pumped rather than settling.
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(EditableText), '123456');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(shown(tester), message);
    });

    testWidgets('RegistrarCramDialog', (tester) async {
      final registrar = _MockRegistrarService();
      when(
        () => registrar.verifyActivation(
          atSign: any(named: 'atSign'),
          otp: any(named: 'otp'),
        ),
      ).thenAnswer((_) => Future.error(Exception('boom')));
      await pumpOpener(
        tester,
        (context) => RegistrarCramDialog(
          atSign: atSign,
          registrar: registrar,
          themeData: ThemeData(),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(EditableText), 'ABCD');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(shown(tester), message);
      // NOTE: the resend countdown runs until it has finished.
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('a message spanning lines shows its first line', (
      tester,
    ) async {
      whenOpenFails(Exception('boom\n#0      main (package:app/main.dart:1)'));
      await pumpOpener(tester, pkamDialog);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(shown(tester), message);
    });
  });

  testWidgets(
    "Anything else shows the exception's message escaped and clipped",
    (tester) async {
      // NOTE: built from code points, so this source holds no bidi character.
      final rlo = String.fromCharCode(0x202e);
      final esc = String.fromCharCode(0x1b);
      whenOpenFails(Exception('a$esc[2Jb${rlo}c${'x' * 500}'));
      await pumpOpener(tester, pkamDialog);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final message = shown(tester);
      expect(
        message,
        startsWith('Something went wrong with $atSign: a\\u001b[2Jb\\u202ec'),
      );
      expect(message, isNot(contains(esc)));
      expect(message, isNot(contains(rlo)));
      expect(message, endsWith('...'));
    },
  );

  for (final withCallback in [false, true]) {
    final title = withCallback
        ? 'Given CramDialog onboarding @alice with onOnboardingComplete, when '
              'the user leaves before the client is handed back, then '
              'onOnboardingComplete receives that client, the dialog does not '
              'stop it, and nothing beneath the dialog is popped'
        : 'Leaving CramDialog before it hands back its client, with no '
              'onOnboardingComplete, stops that client';
    testWidgets(title, (tester) async {
      final activated = Completer<AtClient>();
      when(
        () => flows.activate(
          any(),
          cramSecret: any(named: 'cramSecret'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          storage: any(named: 'storage'),
          lookUps: any(named: 'lookUps'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) => activated.future);
      final client = _MockAtClient();
      var stops = 0;
      when(() => client.stop()).thenAnswer((_) async => stops++);
      when(() => client.enrollmentId).thenReturn('first-1');
      final completed = <AtClient>[];
      final pops = _PopRecorder();
      final results = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [pops],
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  results.add(
                    await showDialog<Object?>(
                      context: context,
                      builder: (context) => CramDialog(
                        atSign: atSign,
                        cramKey: 'cram-secret-6d1f0b',
                        preference: loopback(),
                        keys: InMemoryAtKeysIo(),
                        onOnboardingComplete: withCallback
                            ? completed.add
                            : null,
                        flows: flows,
                      ),
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(CramDialog),
        findsOneWidget,
        reason: 'the control: CramDialog is onboarding',
      );

      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      activated.complete(client);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      if (withCallback) {
        expect(completed, [
          client,
        ], reason: 'onOnboardingComplete receives that client');
        expect(stops, 0, reason: 'the dialog does not stop it');
      } else {
        expect(
          stops,
          1,
          reason: 'that client is stopped, so @alice can be opened again',
        );
      }
      expect(
        pops.popped.whereType<PageRoute<dynamic>>(),
        isEmpty,
        reason: 'nothing beneath the dialog is popped',
      );
      expect(results, [null]);
    });
  }

  testWidgets(
    'Given CramDialog onboarding @alice, when its activation fails after the '
    'user has left, then nothing beneath the dialog is popped',
    (tester) async {
      final activated = Completer<AtClient>();
      when(
        () => flows.activate(
          any(),
          cramSecret: any(named: 'cramSecret'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          storage: any(named: 'storage'),
          lookUps: any(named: 'lookUps'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) => activated.future);
      final pops = _PopRecorder();
      final results = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [pops],
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  results.add(
                    await showDialog<Object?>(
                      context: context,
                      builder: (context) => CramDialog(
                        atSign: atSign,
                        cramKey: 'cram-secret-6d1f0b',
                        preference: loopback(),
                        keys: InMemoryAtKeysIo(),
                        flows: flows,
                      ),
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(CramDialog),
        findsOneWidget,
        reason: 'the control: CramDialog is onboarding',
      );

      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      activated.completeError(Exception('boom'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        shown(tester),
        'Something went wrong with $atSign: boom',
        reason:
            'the control: the failure landed while the dialog was still '
            'there to report it',
      );
      expect(
        pops.popped.whereType<PageRoute<dynamic>>(),
        isEmpty,
        reason: 'nothing beneath the dialog is popped',
      );
      expect(results, [null]);
    },
  );

  testWidgets('Given CramDialog onboarding @alice, when its activation reports '
      'progress after the user has left, then the dialog takes it without '
      'throwing', (tester) async {
    final activated = Completer<AtClient>();
    void Function(ProgressEvent event)? onProgress;
    when(
      () => flows.activate(
        any(),
        cramSecret: any(named: 'cramSecret'),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        storage: any(named: 'storage'),
        lookUps: any(named: 'lookUps'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((invocation) {
      onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(ProgressEvent event)?;
      return activated.future;
    });
    final client = _MockAtClient();
    when(() => client.stop()).thenAnswer((_) async {});
    when(() => client.enrollmentId).thenReturn('first-1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<Object?>(
                context: context,
                builder: (context) => CramDialog(
                  atSign: atSign,
                  cramKey: 'cram-secret-6d1f0b',
                  preference: loopback(),
                  keys: InMemoryAtKeysIo(),
                  flows: flows,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    ProgressEvent event(String msg) =>
        ProgressEvent(group: 'CRAM', msg: msg, type: ProgressEventType.info);
    expect(
      () => onProgress!(event('while showing')),
      returnsNormally,
      reason: 'the control: the dialog hears progress while it is showing',
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(
      find.byType(CramDialog),
      findsNothing,
      reason: 'the control: the user has left the dialog',
    );

    expect(
      () => onProgress!(event('after the user left')),
      returnsNormally,
      reason: 'progress after the user left is taken without throwing',
    );
    activated.complete(client);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Given CramDialog onboarding @alice with an onOnboardingComplete that '
    'throws, when the activation completes, then the dialog stops the client '
    'and closes with none',
    (tester) async {
      final client = _MockAtClient();
      when(
        () => flows.activate(
          any(),
          cramSecret: any(named: 'cramSecret'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          storage: any(named: 'storage'),
          lookUps: any(named: 'lookUps'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => client);
      var stops = 0;
      when(() => client.stop()).thenAnswer((_) async => stops++);
      when(() => client.enrollmentId).thenReturn('first-1');
      final received = <AtClient>[];
      final results = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  results.add(
                    await showDialog<Object?>(
                      context: context,
                      builder: (context) => CramDialog(
                        atSign: atSign,
                        cramKey: 'cram-secret-6d1f0b',
                        preference: loopback(),
                        keys: InMemoryAtKeysIo(),
                        onOnboardingComplete: (given) {
                          received.add(given);
                          throw Exception('the app could not take it');
                        },
                        flows: flows,
                      ),
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

      expect(received, [
        client,
      ], reason: 'the control: onOnboardingComplete was given the client');
      expect(stops, 1, reason: 'the dialog stops the client');
      expect(results, [null], reason: 'the dialog closes with no client');
      expect(
        shown(tester),
        'Something went wrong with $atSign: the app could not take it',
      );
    },
  );
}
