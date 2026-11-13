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

/// Every record logged, as the text of each of its fields.
class _RecordedLogs implements LoggingHandler {
  final List<String> records = [];

  @override
  void call(dynamic record) => records.add(
    [
      record.level,
      record.loggerName,
      record.message,
      record.object,
      record.error,
      record.stackTrace,
    ].join('\n'),
  );
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

  /// A keychain atKeys entry cut short partway through a private key.
  late String entry;

  setUpAll(() {
    // NOTE: before anything logs; a logger binds the handler on first use.
    AtSignLogger.defaultLoggingHandler = logs;
    AtSignLogger.root_level = 'all';
  });

  setUp(() {
    KeychainStorage.isWindows = false;
    logs.records.clear();
    keyMaterial = base64Url.encode(
      List.generate(33, (_) => random.nextInt(256)),
    );
    entry = '{"keys":[{"aesPkamPrivateKey":"$keyMaterial';
  });

  /// A keychain whose store [holding] serves [entry], and whose every other
  /// store is empty.
  KeychainStorage keychainWith({required String holding}) {
    final biometricStorage = _MockBiometricStorage();
    when(
      () => biometricStorage.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((invocation) async {
      final file = _MockBiometricStorageFile();
      final name = invocation.positionalArguments.first as String;
      when(file.read).thenAnswer((_) async => name == holding ? entry : null);
      when(() => file.write(any())).thenAnswer((_) async {});
      return file;
    });
    return KeychainStorage(biometricStorage: biometricStorage);
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
      }
    },
  );

  test('Opening with that entry logs and keeps none of its text', () async {
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

    final client = await Atsign(atSign).open(
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
    final state = client.connection.current;

    for (final record in logs.records) {
      expect(
        record,
        _holdsNoneOf(keyMaterial),
        reason: 'no log record holds the entry\'s text',
      );
    }
    for (final field in [
      state,
      state.outcome,
      state.cause,
      state.error,
      state.at,
    ]) {
      expect(
        field,
        _holdsNoneOf(keyMaterial),
        reason: 'no field of connection.current holds the entry\'s text',
      );
    }
    expect(
      logs.records.where(
        (r) => r.contains('Could not read the keys for $atSign'),
      ),
      isNotEmpty,
      reason: 'the recorder is bound, and heard the keychain read fail',
    );
    expect(
      state.error,
      isA<FormatException>(),
      reason: 'the connection attempt failed on reading the keychain',
    );
  });
}
