import 'dart:convert';

import 'package:at_auth/at_auth.dart'
    show
        AtKeysValidationException,
        CryptographicMaterial,
        CryptographicMaterialAlgorithm,
        CryptographicMaterialRole;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger, LoggingHandler;
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBiometricStorage extends Mock implements BiometricStorage {}

class _MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

/// Every record logged, as its level's name, its logger's name and its
/// message.
class _RecordedLogs implements LoggingHandler {
  final List<({String level, String logger, String message})> records = [];

  @override
  void call(dynamic record) => records.add((
    level: record.level.name,
    logger: record.loggerName,
    message: record.message,
  ));
}

/// A keychain write that fails partway, on Windows where the entry is a
/// header and segments, leaves the entry as it was.
///
/// Catalogue: features/at_client_flutter/keychain_write_fails_partway.feature
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const atSign = '@alice';
  const current = '@atsigns:test';
  const legacy = '@atsigns_test';
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

  /// Each write and delete made, as `write <name>` or `delete <name>`.
  late List<String> calls;

  /// Whether the write being made to the store named is to fail.
  late bool Function(String name) failsWriteOf;

  setUpAll(() {
    // NOTE: before anything logs; a logger binds the handler on first use.
    AtSignLogger.defaultLoggingHandler = logs;
  });

  setUp(() {
    held = {};
    calls = [];
    failsWriteOf = (_) => false;
    logs.records.clear();
  });

  /// A keychain whose stores hold what is written to them, in [held], on
  /// Windows unless [windows] is false. A failed write throws a
  /// [PlatformException] whose message is the store's name.
  KeychainStorage keychain({bool windows = true}) {
    KeychainStorage.isWindows = windows;
    addTearDown(() => KeychainStorage.isWindows = false);
    final biometricStorage = _MockBiometricStorage();
    when(
      () => biometricStorage.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((invocation) async {
      final name = invocation.positionalArguments.first as String;
      final file = _MockBiometricStorageFile();
      when(file.read).thenAnswer((_) async => held[name]);
      when(() => file.write(any())).thenAnswer((invocation) async {
        calls.add('write $name');
        if (failsWriteOf(name)) {
          throw PlatformException(code: 'WriteFailed', message: name);
        }
        held[name] = invocation.positionalArguments.first as String;
      });
      when(file.delete).thenAnswer((_) async {
        calls.add('delete $name');
        held.remove(name);
      });
      return file;
    });
    return KeychainStorage(biometricStorage: biometricStorage);
  }

  /// Makes the next write to the store named [name] fail, once.
  void failNextWriteOf(String name) {
    var failed = false;
    failsWriteOf = (written) {
      if (failed || written != name) return false;
      return failed = true;
    };
  }

  /// A key of [bytes] bytes of [fill], with id [keyId].
  CryptographicMaterial material(
    String keyId, {
    int fill = 7,
    int bytes = 6000,
  }) => CryptographicMaterial(
    keyId: keyId,
    role: CryptographicMaterialRole.of('publicEncryption'),
    algorithm: CryptographicMaterialAlgorithm.of('rsa2048'),
    bytes: AtBytes.fromString(base64Encode(List.filled(bytes, fill))),
    createdAt: DateTime.utc(2026),
  );

  /// Keys for [atSign] whose entry spans several Windows segments.
  AtKeys largeKeys(String atSign, {int fill = 7}) => AtKeys()
    ..atsign = atSign.toAtsign()
    ..addKey(material('enc:rsa2048:1', fill: fill));

  /// How many segments of the keys entry are held.
  int segmentsHeld() =>
      held.keys.where((name) => name.startsWith('${current}_segment_')).length;

  /// The atSigns the keychain's entry reads back as.
  Future<List<String>> atSignsIn(KeychainStorage storage) async {
    final data = await storage.readAtKeysData();
    expect(data, isNotNull, reason: 'the keychain still has its entry');
    return data!.keys.map((k) => '${k.atsign}').toList();
  }

  test(
    'A keychain write that fails partway on Windows leaves the entry as it was',
    () async {
      final storage = keychain();
      await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
      final before = Map.of(held);
      final aliceSegments = segmentsHeld();
      calls.clear();
      failNextWriteOf('${current}_segment_${aliceSegments + 1}');

      await expectLater(
        storage.appendAtKeysToKeychain(keys: largeKeys('@bob', fill: 9)),
        throwsA(isA<PlatformException>()),
      );

      expect(
        calls,
        contains('write ${current}_segment_$aliceSegments'),
        reason:
            'the control: the failed write went past the segments '
            "@alice's keys fill",
      );
      expect(await atSignsIn(storage), [atSign]);
      expect(held, before, reason: "no segment of @bob's keys is left");
    },
  );

  group('On Windows, a keychain write that fails partway', () {
    test('removing an atSign from a keychain holding others', () async {
      final storage = keychain();
      await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
      await storage.appendAtKeysToKeychain(keys: largeKeys('@bob'));
      expect(
        held.keys,
        contains('${current}_segment_4'),
        reason: 'the control: the entry spans five segments',
      );
      final before = Map.of(held);
      failNextWriteOf('${current}_segment_1');

      await expectLater(
        storage.removeAtsignFromKeychain(atSign),
        throwsA(isA<PlatformException>()),
      );

      expect(await atSignsIn(storage), [atSign, '@bob']);
      expect(held, before);
    });

    test('adding the first keys to an empty keychain', () async {
      final storage = keychain();
      failNextWriteOf('${current}_segment_1');

      await expectLater(
        storage.appendAtKeysToKeychain(keys: largeKeys(atSign)),
        throwsA(isA<PlatformException>()),
      );

      expect(await storage.readAtKeysData(), isNull);
      expect(held, isEmpty, reason: 'nothing is left of the failed write');
    });

    for (final (name, change) in [
      (
        'flushing an atSign\'s grown keys',
        (KeychainAtKeysIo io, AtKeys grown) =>
            io.flush(atSign.toAtsign(), grown),
      ),
      (
        'updating an atSign\'s keys',
        (KeychainAtKeysIo io, AtKeys grown) =>
            io.update(atSign.toAtsign(), (keys) {
              keys.addKey(material('enc:rsa2048:2', fill: 3));
              return true;
            }),
      ),
    ]) {
      test(name, () async {
        final storage = keychain();
        await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
        await storage.appendAtKeysToKeychain(keys: largeKeys('@bob'));
        final before = Map.of(held);
        final segments = segmentsHeld();
        calls.clear();
        failNextWriteOf('${current}_segment_${segments + 1}');

        await expectLater(
          change(
            KeychainAtKeysIo(keychainStorage: storage),
            largeKeys(atSign)..addKey(material('enc:rsa2048:2', fill: 3)),
          ),
          throwsA(isA<PlatformException>()),
        );

        expect(
          calls,
          contains('write ${current}_segment_$segments'),
          reason: 'the control: the failed write went past the old segments',
        );
        expect(await atSignsIn(storage), [atSign, '@bob']);
        expect(held, before, reason: 'no segment of the failed write is left');
      });
    }

    test('migrating the legacy store', () async {
      final storage = keychain();
      await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
      for (final name in held.keys.toList()) {
        held[name.replaceFirst(current, legacy)] = held.remove(name)!;
      }
      final before = Map.of(held);
      calls.clear();
      failNextWriteOf('${current}_segment_1');

      await expectLater(
        storage.readAtKeysData(),
        throwsA(isA<PlatformException>()),
      );

      expect(
        calls,
        contains('write $current'),
        reason: 'the control: the migration began writing the entry',
      );
      expect(held, before, reason: 'only the legacy store is left');
    });

    test(
      'logs a failed undo at severe, and throws the write\'s own failure',
      () async {
        final storage = keychain();
        await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
        var segmentFailed = false;
        failsWriteOf = (name) {
          if (!segmentFailed && name == '${current}_segment_1') {
            return segmentFailed = true;
          }
          return segmentFailed && name == current;
        };

        await expectLater(
          storage.appendAtKeysToKeychain(keys: largeKeys('@bob')),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.message,
              'the store whose write failed',
              '${current}_segment_1',
            ),
          ),
        );

        expect(
          logs.records.where(
            (r) =>
                r.level == 'SEVERE' &&
                r.message.startsWith(
                  'Undoing a failed write of keychain entry "$current" failed',
                ),
          ),
          hasLength(1),
        );
      },
    );

    test(
      'keys that cannot be encoded are refused with nothing written',
      () async {
        final storage = keychain();
        await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
        final before = Map.of(held);
        calls.clear();

        await expectLater(
          storage.appendAtKeysToKeychain(
            keys: AtKeys()..addKey(material('enc:rsa2048:1')),
          ),
          throwsA(isA<AtKeysValidationException>()),
        );

        expect(calls, isEmpty, reason: 'nothing is written or deleted');
        expect(held, before);
      },
    );
  });

  test(
    'A successful shorter write on Windows leaves no segment past its own',
    () async {
      final aliceOnly = keychain();
      await aliceOnly.appendAtKeysToKeychain(keys: largeKeys(atSign));
      final expected = Map.of(held);
      held.clear();
      final storage = keychain();
      await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
      await storage.appendAtKeysToKeychain(keys: largeKeys('@bob', fill: 9));
      expect(
        segmentsHeld(),
        greaterThan(expected.length - 1),
        reason: 'the control: two Atsigns fill more segments than one',
      );

      await storage.removeAtsignFromKeychain('@bob');

      expect(held, expected);
    },
  );

  test('Off Windows, a failed keychain write is not undone', () async {
    final storage = keychain(windows: false);
    await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
    calls.clear();
    failNextWriteOf(current);

    await expectLater(
      storage.appendAtKeysToKeychain(keys: largeKeys('@bob')),
      throwsA(isA<PlatformException>()),
    );

    expect(calls, ['write $current'], reason: 'one write, and no undo');
  });

  test('Off Windows, a shorter keychain write deletes nothing', () async {
    final storage = keychain(windows: false);
    await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
    await storage.appendAtKeysToKeychain(keys: largeKeys('@bob'));
    calls.clear();

    await storage.removeAtsignFromKeychain('@bob');

    expect(calls, ['write $current'], reason: 'the entry is one store');
  });
}
