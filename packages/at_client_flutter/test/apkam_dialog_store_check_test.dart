import 'dart:async';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger, LoggingHandler;
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_path_provider.dart';

class _MockAtsignFlows extends Mock implements AtsignFlows {}

class _MockBiometricStorage extends Mock implements BiometricStorage {}

class _MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

class _FakeAtClientPreference extends Fake implements AtClientPreference {}

class _RecordedLogs implements LoggingHandler {
  final List<({String level, String message})> records = [];

  @override
  void call(dynamic record) =>
      records.add((level: '${record.level}', message: record.message));

  List<String> at(String level) => [
    for (final r in records)
      if (r.level == level) r.message,
  ];
}

/// ApkamActivationDialog checks its AtKeys store for a pending enrollment as
/// it opens; a store it cannot use is shown and logged, and a defect is
/// logged and rethrown.
///
/// Catalogue: features/at_client_flutter/apkam_dialog.feature
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const atSign = '@alice';
  final logs = _RecordedLogs();

  setUpAll(() {
    // NOTE: before anything logs; a logger binds the handler on first use.
    AtSignLogger.defaultLoggingHandler = logs;
    AtSignLogger.root_level = 'info';
    registerFallbackValue(InMemoryAtKeysIo());
    registerFallbackValue(_FakeAtClientPreference());
    PathProviderPlatform.instance = FakePathProvider('/app/support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (MethodCall methodCall) async => methodCall.method == 'getAll'
              ? {
                  'appName': 'test',
                  'packageName': 'test',
                  'version': '1.0.0',
                  'buildNumber': '1',
                }
              : null,
        );
  });

  setUp(logs.records.clear);

  /// This device's keychain, whose every read the platform refuses, as it
  /// does when the user cancels the biometric prompt.
  WrittenAtKeysIo refusedKeychain() {
    final biometricStorage = _MockBiometricStorage();
    when(
      () => biometricStorage.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((_) async {
      final file = _MockBiometricStorageFile();
      when(file.read).thenAnswer(
        (_) async => throw PlatformException(
          code: 'AuthError:UserCanceled',
          message: 'User canceled the operation.',
        ),
      );
      return file;
    });
    return KeychainAtKeysIo(
      keychainStorage: KeychainStorage(biometricStorage: biometricStorage),
    );
  }

  /// Shows a button that opens ApkamActivationDialog for [atSign] over
  /// [keys], through [flows].
  Future<void> pumpOpener(
    WidgetTester tester, {
    required WrittenAtKeysIo keys,
    AtsignFlows flows = const AtsignFlows(),
    String opening = atSign,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<Object?>(
                context: context,
                builder: (_) => ApkamActivationDialog(
                  atSign: opening,
                  rootDomain: AtRootDomain.atsignDomain,
                  appName: 'app',
                  deviceName: 'device',
                  namespaces: const {'*': 'rw'},
                  preference: AtClientPreference(),
                  keys: keys,
                  themeData: ThemeData(),
                  flows: flows,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the dialog [pumpOpener] shows.
  Future<void> open(WidgetTester tester) async {
    // NOTE: the passcode field's cursor never stops blinking, so frames are
    // pumped by hand rather than settled.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Opens ApkamActivationDialog for [atSign] over [keys], through [flows].
  Future<void> openDialog(
    WidgetTester tester, {
    required WrittenAtKeysIo keys,
    AtsignFlows flows = const AtsignFlows(),
    String opening = atSign,
  }) async {
    await pumpOpener(tester, keys: keys, flows: flows, opening: opening);
    await open(tester);
  }

  /// The SnackBar's entrance.
  Future<void> letItShow(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
  }

  Finder textStartingWith(String start) => find.byWidgetPredicate(
    (w) => w is Text && (w.data?.startsWith(start) ?? false),
  );

  group(
    'The enrollment dialog says so when it cannot use its AtKeys store',
    () {
      testWidgets('cannot be read', (tester) async {
        await openDialog(tester, keys: refusedKeychain());
        await letItShow(tester);

        expect(
          textStartingWith(
            "The keys for @alice in the AtKeys store (this device's keychain) "
            'could not be read: ',
          ),
          findsOneWidget,
        );
        expect(
          logs.at('WARNING'),
          contains(
            allOf(
              contains(atSign),
              contains("this device's keychain) could not be read"),
            ),
          ),
        );
        expect(find.byType(EditableText), findsOneWidget);
      });

      testWidgets('holds keys recorded for @bob', (tester) async {
        await openDialog(
          tester,
          keys: InMemoryAtKeysIo.holding(
            atSign,
            AtKeys()..atsign = '@bob'.toAtsign(),
          ),
        );
        await letItShow(tester);

        expect(
          textStartingWith('The keys in the AtKeys store'),
          findsOneWidget,
        );
        expect(
          find.textContaining('are for @bob, not @alice.'),
          findsOneWidget,
        );
        expect(
          logs.at('WARNING'),
          contains(allOf(contains(atSign), contains('are for @bob'))),
        );
        expect(find.byType(EditableText), findsOneWidget);
      });
    },
  );

  testWidgets('A check of the AtKeys store that fails after the user has left '
      'is logged, not shown', (tester) async {
    final flows = _MockAtsignFlows();
    final check = Completer<PendingEnrollment?>();
    when(
      () => flows.resumeEnrollment(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer((_) => check.future);
    await openDialog(tester, keys: InMemoryAtKeysIo(), flows: flows);

    Navigator.of(tester.element(find.byType(ApkamActivationDialog))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byType(ApkamActivationDialog),
      findsNothing,
      reason: 'the control: the user has left before the check fails',
    );
    check.completeError(
      AtKeysUnusableException.anotherAtsign(
        atSign,
        '@bob',
        source: "this device's keychain",
      ),
    );
    await letItShow(tester);

    expect(
      logs.at('WARNING'),
      contains(allOf(contains(atSign), contains('are for @bob'))),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("A defect in the enrollment dialog's check of its AtKeys store "
      'is logged and rethrown', (tester) async {
    final flows = _MockAtsignFlows();
    final defect = StateError('the pending entry has no key');
    when(
      () => flows.resumeEnrollment(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer((_) => Future.error(defect));
    await pumpOpener(tester, keys: InMemoryAtKeysIo(), flows: flows);
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      await open(tester);
      await letItShow(tester);
    }, (error, _) => uncaught.add(error));

    expect(uncaught, [same(defect)]);
    expect(
      logs.at('SEVERE'),
      contains(
        allOf(contains(atSign), contains('Bad state: the pending entry')),
      ),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets('Given an Atsign that is not valid, when ApkamActivationDialog '
      'opens it, then the refusal is shown once the dialog is up, and the '
      'passcode form stays', (tester) async {
    await openDialog(tester, keys: InMemoryAtKeysIo(), opening: 'al ice');
    await letItShow(tester);

    expect(tester.takeException(), isNull);
    expect(
      textStartingWith('Something went wrong with al ice: '),
      findsOneWidget,
    );
    expect(logs.at('WARNING'), contains(contains('al ice')));
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets('Given AtsignFlows whose resumeEnrollment fails with a value '
      'that is no Exception, when ApkamActivationDialog opens, then it is '
      'logged at severe and rethrown', (tester) async {
    final flows = _MockAtsignFlows();
    when(
      () => flows.resumeEnrollment(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer((_) => Future.error('a bare string'));
    await pumpOpener(tester, keys: InMemoryAtKeysIo(), flows: flows);
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      await open(tester);
      await letItShow(tester);
    }, (error, _) => uncaught.add(error));

    expect(uncaught, ['a bare string']);
    expect(
      logs.at('SEVERE'),
      contains(allOf(contains(atSign), contains('a bare string'))),
    );
    expect(find.byType(SnackBar), findsNothing);
  });
}
