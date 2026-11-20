import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator, AtLookupImpl;
import 'package:at_utils/at_logger.dart' show AtSignLogger, LoggingHandler;
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBiometricStorage extends Mock implements BiometricStorage {}

class _MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

/// A lookup that, asked to authenticate, runs the authenticator the client
/// installed on it, so the attempt reads the keys as a real connection would.
class _LookUpRunningItsAuthenticator extends Mock implements AtLookupImpl {
  @override
  AtAuthenticator? authenticator;

  @override
  Future<bool> pkamAuthenticate() => authenticator!(this);
}

/// Every record logged, as its logger's name, its message and its error,
/// without its stack trace, whose frames name the files of the checkout.
class _RecordedLogs implements LoggingHandler {
  final List<({String logger, String message, Object? error})> records = [];

  @override
  void call(dynamic record) => records.add((
    logger: record.loggerName,
    message: record.message,
    error: record.error,
  ));
}

/// Matches an object whose text holds no run of [window] consecutive
/// characters of [value].
Matcher _holdsNoneOf(String value, {int window = 8}) =>
    predicate<Object?>((actual) {
      final text = '$actual';
      for (var i = 0; i + window <= value.length; i++) {
        if (text.contains(value.substring(i, i + window))) return false;
      }
      return true;
    }, 'text holding no $window-character run of the value');

/// Reading a keychain atKeys entry that is not JSON.
///
/// Catalogue: features/at_client_flutter/keychain_entry_not_json.feature
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  final random = Random.secure();

  /// Key material no log line, message or field could hold by chance.
  late String keyMaterial;

  /// The text of [entry] before its key material.
  const opening = '{"keys":[{"aesPkamPrivateKey":"';

  /// A keychain atKeys entry cut short partway through a private key.
  late String entry;

  /// The keychain stores written to or deleted, by name.
  final changed = <String>[];

  setUpAll(() {
    // NOTE: before anything logs; a logger binds the handler on first use.
    AtSignLogger.defaultLoggingHandler = logs;
    AtSignLogger.root_level = 'all';
  });

  setUp(() {
    KeychainStorage.isWindows = false;
    logs.records.clear();
    changed.clear();
    keyMaterial = base64Url.encode(
      List.generate(33, (_) => random.nextInt(256)),
    );
    entry = '$opening$keyMaterial';
  });

  /// A keychain whose store [holding] serves [entry], whose every other store
  /// is empty, and which records each store written to or deleted in
  /// [changed].
  KeychainStorage keychainWith({required String holding}) {
    final biometricStorage = _MockBiometricStorage();
    when(
      () => biometricStorage.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((invocation) async {
      final file = _MockBiometricStorageFile();
      final name = invocation.positionalArguments.first as String;
      when(file.read).thenAnswer((_) async => name == holding ? entry : null);
      when(() => file.write(any())).thenAnswer((_) async => changed.add(name));
      when(file.delete).thenAnswer((_) async => changed.add(name));
      return file;
    });
    return KeychainStorage(biometricStorage: biometricStorage);
  }

  /// Expects [actual] to hold none of [entry]: no 8-character run of its key
  /// material, and no 5-character run of its [opening].
  void expectHoldsNoneOfEntry(Object? actual, String reason) {
    expect(actual, _holdsNoneOf(keyMaterial), reason: reason);
    expect(actual, _holdsNoneOf(opening, window: 5), reason: reason);
  }

  /// Expects no log record's message or error to hold any of [entry], and the
  /// recorder to hear the logger the keychain logs through.
  void expectNoLogHoldsEntry() {
    for (final record in logs.records) {
      expectHoldsNoneOfEntry(
        record.message,
        'no log record\'s message holds the entry\'s text',
      );
      expectHoldsNoneOfEntry(
        record.error,
        'no log record\'s error holds the entry\'s text',
      );
    }
    const heard = 'a record the keychain logs';
    KeychainStorage(
      biometricStorage: _MockBiometricStorage(),
    ).log(heard, false);
    expect(
      logs.records.where((r) => r.message.contains(heard)),
      isNotEmpty,
      reason: 'the recorder hears the logger the keychain logs through',
    );
  }

  /// Expects [error] to be an [AtKeysFormatException] holding none of the
  /// entry's text, no log record to hold any of it, and [store] to be
  /// unchanged.
  void expectRefusedLeaving(String store, Object? error) {
    expect(
      '$error',
      _holdsNoneOf(entry),
      reason: 'the error with $store holding the entry holds none of its text',
    );
    expect(error, isA<AtKeysFormatException>(), reason: 'with $store');
    final format = error as AtKeysFormatException;
    for (final held in [format.message, format.reason]) {
      expect(
        held,
        _holdsNoneOf(entry),
        reason: 'no field of the error with $store holds the entry',
      );
    }
    for (final held in [error, format.message, format.reason]) {
      expectHoldsNoneOfEntry(
        held,
        'no field of the error with $store holds the entry\'s text',
      );
    }
    expectNoLogHoldsEntry();
    expect(
      changed,
      isEmpty,
      reason: 'nothing is written or deleted with $store holding the entry',
    );
  }

  FormatException parserErrorOf(String text) {
    try {
      jsonDecode(text);
    } on FormatException catch (e) {
      return e;
    }
    fail('the text parsed');
  }

  test(
    'A keychain entry that is not JSON names the reason and none of its text',
    () async {
      final parserError = parserErrorOf(entry);
      for (final store in ['@atsigns:test', '@atsigns_test']) {
        Object? error;
        try {
          await KeychainAtKeysIo(
            keychainStorage: keychainWith(holding: store),
          ).read('@alice');
        } catch (e) {
          error = e;
        }

        expect(
          '$error',
          _holdsNoneOf(entry),
          reason: 'the error reading $store holds none of the entry\'s text',
        );
        expect(
          error,
          isA<AtKeysFormatException>()
              .having((e) => e.reason, 'reason', parserError.message)
              .having((e) => e.position, 'position', entry.length + 1)
              .having((e) => e.source, 'source', isNull),
          reason: 'reading $store',
        );
        final format = error as AtKeysFormatException;
        for (final held in [format.message, format.reason]) {
          expect(
            held,
            _holdsNoneOf(entry),
            reason: 'no field of the error reading $store holds the entry',
          );
        }
        for (final held in [error, format.message, format.reason]) {
          expectHoldsNoneOfEntry(
            held,
            'no field of the error reading $store holds the entry\'s text',
          );
        }
        expectNoLogHoldsEntry();
      }
    },
  );

  /// Opens `@alice` with a keychain whose current store serves [entry], and
  /// expects [AtKeysUnusableException], with no log record and no field of the
  /// exception holding the entry's text.
  Future<void> expectOpeningLogsAndKeepsNone() async {
    const atSign = '@alice';
    final dir = Directory.systemTemp.createTempSync('keychain_not_json_');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = socket.port;
    await socket.close();
    addTearDown(() async {
      for (final client in List<AtClient>.from(
        AtClientImpl.atClientInstanceMap.values,
      )) {
        await client.stop();
      }
      AtClientImpl.atClientInstanceMap.clear();
      dir.deleteSync(recursive: true);
    });
    final lookUp = _LookUpRunningItsAuthenticator();
    when(lookUp.close).thenAnswer((_) async {});
    when(lookUp.stop).thenAnswer((_) async {});
    when(lookUp.isConnectionAvailable).thenReturn(false);

    Object? thrown;
    try {
      await Atsign(atSign).open(
        keys: KeychainAtKeysIo(
          keychainStorage: keychainWith(holding: '@atsigns:test'),
        ),
        preference: AtClientPreference()
          ..rootDomain = InternetAddress.loopbackIPv4.address
          ..rootPort = closedPort
          ..namespace = 'keychain',
        storage: HiveAtClientStorage(
          atSign: atSign.toAtsign(),
          storagePath: dir.path,
          closedByClient: true,
        ),
        atLookUp: lookUp,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: CacheableSecondaryAddressFinder(
          InternetAddress.loopbackIPv4.address,
          closedPort,
        ),
      );
    } catch (e) {
      thrown = e;
    }

    expect(
      thrown,
      isA<AtKeysUnusableException>()
          .having((e) => e.cause, 'cause', AtKeysUnusableCause.unreadable)
          .having((e) => e.error, 'error', isA<AtKeysFormatException>()),
    );
    final unusable = thrown as AtKeysUnusableException;
    for (final field in [
      unusable,
      unusable.message,
      unusable.atSign,
      unusable.cause,
      unusable.source,
      unusable.error,
    ]) {
      expectHoldsNoneOfEntry(
        field,
        'no field of the exception holds the entry\'s text',
      );
    }
    expectNoLogHoldsEntry();
  }

  test(
    'Opening with that entry logs and keeps none of its text',
    expectOpeningLogsAndKeepsNone,
  );

  group('On Windows', () {
    test('Opening with that entry logs and keeps none of its text', () async {
      KeychainStorage.isWindows = true;
      addTearDown(() => KeychainStorage.isWindows = false);

      await expectOpeningLogsAndKeepsNone();

      expect(
        logs.records.where(
          (r) =>
              r.logger == 'KeychainStorage' &&
              r.message.contains('READ: Fetched') &&
              r.message.contains('from @atsigns:test'),
        ),
        isNotEmpty,
        reason: 'the recorder hears the Windows read of the current store',
      );
    });

    test(
      'Deleting all atKeys data with a header that does not parse deletes its segments',
      () async {
        KeychainStorage.isWindows = true;
        addTearDown(() => KeychainStorage.isWindows = false);
        const header = '@atsigns:test';
        final held = <String, String>{
          header: '{bad',
          '${header}_segment_0': entry.substring(0, 20),
          '${header}_segment_1': entry.substring(20),
        };
        final biometricStorage = _MockBiometricStorage();
        when(
          () => biometricStorage.getStorage(
            any(),
            options: any(named: 'options'),
          ),
        ).thenAnswer((invocation) async {
          final file = _MockBiometricStorageFile();
          final name = invocation.positionalArguments.first as String;
          when(file.read).thenAnswer((_) async => held[name]);
          when(file.delete).thenAnswer((_) async {
            held.remove(name);
            changed.add(name);
          });
          return file;
        });

        await KeychainStorage(
          biometricStorage: biometricStorage,
        ).deleteAllAtKeysData();

        expect(
          held,
          isEmpty,
          reason: 'the header and every segment holding atKeys are deleted',
        );
        expect(changed, isNot(contains('${header}_segment_2')));
        expectNoLogHoldsEntry();
      },
    );

    group(
      'Given a header that parses but records no segment count, and three segments',
      () {
        test(
          'when all atKeys data is deleted, then every segment is gone and none past them is deleted',
          () async {
            KeychainStorage.isWindows = true;
            addTearDown(() => KeychainStorage.isWindows = false);
            const header = '@atsigns:test';
            final held = <String, String>{
              header: '{}',
              '${header}_segment_0': entry.substring(0, 15),
              '${header}_segment_1': entry.substring(15, 30),
              '${header}_segment_2': entry.substring(30),
            };
            final biometricStorage = _MockBiometricStorage();
            when(
              () => biometricStorage.getStorage(
                any(),
                options: any(named: 'options'),
              ),
            ).thenAnswer((invocation) async {
              final file = _MockBiometricStorageFile();
              final name = invocation.positionalArguments.first as String;
              when(file.read).thenAnswer((_) async => held[name]);
              when(file.delete).thenAnswer((_) async {
                held.remove(name);
                changed.add(name);
              });
              return file;
            });

            await KeychainStorage(
              biometricStorage: biometricStorage,
            ).deleteAllAtKeysData();

            expect(
              held,
              isEmpty,
              reason: 'the header and all three segments are deleted',
            );
            expect(
              changed,
              isNot(contains('${header}_segment_3')),
              reason: 'no segment past the third is deleted',
            );
            expectNoLogHoldsEntry();
          },
        );
      },
    );
  });

  test(
    'Adding keys to a keychain whose entry does not parse says why, and none of its text',
    () async {
      final bobKeys = AtKeys.legacy(
        apkamPublicKey: base64Encode(utf8.encode('apkam')),
        selfEncryptionKey: base64Encode(utf8.encode('self')),
      )..atsign = '@bob'.toAtsign();
      for (final store in ['@atsigns:test', '@atsigns_test']) {
        changed.clear();
        Object? error;
        try {
          await keychainWith(
            holding: store,
          ).appendAtKeysToKeychain(keys: bobKeys);
        } catch (e) {
          error = e;
        }

        expectRefusedLeaving(store, error);
      }
    },
  );

  test(
    'Removing an atSign from a keychain whose entry does not parse says why, and none of its text',
    () async {
      for (final store in ['@atsigns:test', '@atsigns_test']) {
        changed.clear();
        Object? error;
        try {
          await keychainWith(holding: store).removeAtsignFromKeychain('@alice');
        } catch (e) {
          error = e;
        }

        expectRefusedLeaving(store, error);
      }
    },
  );
}
