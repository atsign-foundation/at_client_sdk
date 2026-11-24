import 'dart:async';

import 'package:at_client_flutter/at_client_flutter.dart' show AtException;
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger, LoggingHandler;
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart'
    show MethodChannel, MethodCall, PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBiometricStorage extends Mock implements BiometricStorage {}

class _MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

/// The level, message and error of every record logged.
class _RecordedLogs implements LoggingHandler {
  final List<({String level, String message, Object? error})> records = [];

  @override
  void call(dynamic record) => records.add((
    level: '${record.level}',
    message: record.message,
    error: record.error,
  ));
}

/// Clearing the keychain throws what the keychain throws.
///
/// Each test titled as a scenario proves that scenario; each titled
/// Given/When/Then pins a detail no scenario names.
///
/// Catalogue: features/at_client_flutter/keychain_clear_reports_failure.feature
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const current = '@atsigns:test';
  const legacy = '@atsigns_test';
  const entry = '{"keys":[]}';
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

  final logs = _RecordedLogs();

  /// What each store holds, by name.
  late Map<String, String> held;

  /// The store file the keychain was handed for each name it asked for.
  late Map<String, _MockBiometricStorageFile> files;

  setUpAll(() {
    final handler = AtSignLogger.defaultLoggingHandler;
    final level = AtSignLogger.root_level;
    addTearDown(() {
      AtSignLogger.defaultLoggingHandler = handler;
      AtSignLogger.root_level = level;
    });
    // NOTE: before anything logs; a logger binds the handler on first use.
    AtSignLogger.defaultLoggingHandler = logs;
    AtSignLogger.root_level = 'all';
  });

  setUp(() {
    final wasWindows = KeychainStorage.isWindows;
    addTearDown(() => KeychainStorage.isWindows = wasWindows);
    KeychainStorage.isWindows = false;
    held = {};
    files = {};
    logs.records.clear();
  });

  /// A delete that removes what the store holds and answers as
  /// biometric_storage does on Android, Windows and Linux: `false` when the
  /// store held nothing. On iOS and macOS it answers `true` either way.
  Future<void> deletes(String name) =>
      Future<bool?>.value(held.remove(name) != null);

  /// A delete that fails as Android and Windows report it: it answers
  /// `false` and leaves the store as it was.
  Future<void> leavesStored(String name) => Future<bool?>.value(false);

  /// A keychain whose stores hold what [held] holds, each deleted as
  /// [deleting] answers for its name, else as [deletes] does, and each read
  /// as [reading] answers for its name, else as what it holds.
  KeychainStorage keychain({
    Map<String, Future<void> Function(String name)> deleting = const {},
    Map<String, Future<String?> Function()> reading = const {},
  }) {
    final biometricStorage = _MockBiometricStorage();
    when(
      () => biometricStorage.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((invocation) async {
      final name = invocation.positionalArguments.first as String;
      return files.putIfAbsent(name, () {
        final file = _MockBiometricStorageFile();
        when(file.delete).thenAnswer((_) => (deleting[name] ?? deletes)(name));
        when(
          file.read,
        ).thenAnswer((_) => (reading[name] ?? () async => held[name])());
        when(() => file.write(any())).thenAnswer((invocation) async {
          held[name] = invocation.positionalArguments.first as String;
        });
        return file;
      });
    });
    return KeychainStorage(biometricStorage: biometricStorage);
  }

  /// What [action] threw, with its stack trace, failing the test when it
  /// completes.
  Future<(Object, StackTrace)> thrownBy(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, s) {
      return (e, s);
    }
    fail('it completed');
  }

  /// Expects the store named [name] to have been asked for, and deleted once.
  void expectDeleted(String name) {
    expect(files.keys, contains(name), reason: 'the store "$name" is tried');
    verify(files[name]!.delete).called(1);
  }

  Iterable<({String level, String message, Object? error})> warnings() =>
      logs.records.where((r) => r.level == 'WARNING');

  test('Clearing a keychain whose delete fails throws that failure', () async {
    held[current] = entry;
    final failure = PlatformException(
      code: 'SecurityError',
      message:
          'Error while writing data: -25308: User interaction is not '
          'allowed.',
    );
    final failureStack = StackTrace.fromString('the platform delete');
    final storage = keychain(
      deleting: {current: (_) => Future.error(failure, failureStack)},
    );

    final (error, stack) = await thrownBy(storage.deleteAllAtKeysData);

    expect(
      identical(error, failure),
      isTrue,
      reason: 'the error the delete threw is thrown, not another: $error',
    );
    expect('$stack', '$failureStack', reason: 'with its own stack trace');
    expectDeleted(legacy);
  });

  test('Clearing a keychain that holds nothing completes', () async {
    final storage = keychain();

    await storage.deleteAllAtKeysData();

    expectDeleted(current);
    expectDeleted(legacy);
    expect(warnings(), isEmpty);
  });

  test(
    'Clearing a keychain whose delete leaves the entry stored throws',
    () async {
      held[current] = entry;
      final storage = keychain(deleting: {current: leavesStored});

      final (error, _) = await thrownBy(storage.deleteAllAtKeysData);

      expect(
        error,
        isA<AtException>().having(
          (e) => e.message,
          'message',
          'Keychain store "$current" is still stored after its delete',
        ),
      );
      expectDeleted(legacy);
    },
  );

  test('Given a delete that leaves the AtKeys entry stored and a read-back '
      'that throws, when the keychain is cleared, then it throws an '
      'AtException saying the entry may still be stored', () async {
    held[current] = entry;
    final storage = keychain(
      deleting: {current: leavesStored},
      reading: {
        current: () async => throw PlatformException(
          code: 'Unexpected Error',
          message: 'javax.crypto.AEADBadTagException',
        ),
      },
    );

    final (error, _) = await thrownBy(storage.deleteAllAtKeysData);

    expect(
      error,
      isA<AtException>().having(
        (e) => e.message,
        'message',
        startsWith(
          'Keychain store "$current" could not be read back after its '
          'delete, so it may still be stored: ',
        ),
      ),
    );
    expectDeleted(legacy);
  });

  test(
    'Given a Windows legacy header naming 2 segments, the second of which '
    'stays stored at its first delete, when the keychain is cleared twice, '
    'then the first clear throws and the second deletes both segments',
    () async {
      KeychainStorage.isWindows = true;
      held[current] = '2';
      held['test_data_0'] = 'part0';
      held['test_data_1'] = 'part1';
      var firstDelete = true;
      final storage = keychain(
        deleting: {
          'test_data_1': (name) async {
            if (firstDelete) {
              firstDelete = false;
              return;
            }
            held.remove(name);
          },
        },
      );

      final (error, _) = await thrownBy(storage.deleteAllAtKeysData);
      expect(
        error,
        isA<AtException>().having(
          (e) => e.message,
          'message',
          contains('"test_data_1" is still stored'),
        ),
        reason: 'the control: the first clear stops at the second segment',
      );
      expect(held, isNot(contains(current)), reason: 'the header is deleted');

      await storage.deleteAllAtKeysData();

      expect(held.keys.where((name) => name.startsWith('test_data_')), isEmpty);
    },
  );

  test('Given a Windows header that throws when read, over 2 legacy segments, '
      'when the keychain is cleared, then the header and both segments are '
      'deleted', () async {
    KeychainStorage.isWindows = true;
    held[current] = '2';
    held['test_data_0'] = 'part0';
    held['test_data_1'] = 'part1';
    final storage = keychain(
      reading: {
        current: () async => held.containsKey(current)
            ? throw const FormatException('Unexpected extension byte')
            : null,
      },
    );

    await storage.deleteAllAtKeysData();

    expect(held, isEmpty);
  });

  test('Given only the legacy-named store fails to delete, when the keychain '
      'is cleared, then that failure is thrown', () async {
    final failure = PlatformException(code: 'SecurityError');
    final storage = keychain(deleting: {legacy: (_) => Future.error(failure)});

    final (error, _) = await thrownBy(storage.deleteAllAtKeysData);

    expect(identical(error, failure), isTrue, reason: '$error');
  });

  test('Given both stores fail to delete, when the keychain is cleared, then '
      'the first failure is thrown and the second is logged at warning, '
      'naming its store', () async {
    final first = PlatformException(code: 'SecurityError', message: 'current');
    final second = PlatformException(code: 'SecurityError', message: 'legacy');
    final storage = keychain(
      deleting: {
        current: (_) => Future.error(first),
        legacy: (_) => Future.error(second),
      },
    );

    final (error, _) = await thrownBy(storage.deleteAllAtKeysData);

    expect(
      identical(error, first),
      isTrue,
      reason: 'the first failure is thrown: $error',
    );
    expect(warnings(), hasLength(1));
    final warning = warnings().single;
    expect(
      identical(warning.error, second),
      isTrue,
      reason: 'the second failure is logged: ${warning.error}',
    );
    expect(warning.message, contains('"$legacy"'));
  });

  test('A read in flight while the keychain is cleared does not bring the '
      'cleared keys back', () async {
    held[legacy] = entry;
    final legacyReadHoldingKeys = Completer<void>();
    final storage = keychain(
      reading: {
        legacy: () async {
          final stored = held[legacy];
          if (stored != null && !legacyReadHoldingKeys.isCompleted) {
            legacyReadHoldingKeys.complete();
          }
          return stored;
        },
      },
    );

    final clear = storage.writing(() async {
      await legacyReadHoldingKeys.future;
      await storage.deleteAllAtKeysData();
    });
    final read = storage.readAtKeysData();
    await clear;
    await read;

    expect(held[current], isNull, reason: 'no keys under the current name');
    expect(held[legacy], isNull, reason: 'no keys under the legacy name');
  });
}
