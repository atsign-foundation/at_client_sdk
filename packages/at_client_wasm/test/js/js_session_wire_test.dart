import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_client_wasm/src/js/at_error_code.dart';
import 'package:at_client_wasm/src/js/js_session.dart';
import 'package:test/test.dart';

import '../session/wire_fakes.dart';
import '../test_utils.dart';

void main() {
  late Wire wire;
  late AtClientJsSession session;

  setUp(() async {
    wire = Wire();
    final client = await portalSession(
        atSign: '@alice',
        app: 'wavi',
        keys: classicalAtKeys(),
        transport: (
          lookUps: wire.lookUps,
          finder: FixedSecondaryAddressFinder('atserver.test', 1)
        ));
    session = AtClientJsSession(client, namespace: 'wavi');
  });

  tearDown(() async {
    await session.close();
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
  });

  test('put sends one update for <key>.<namespace>@<atSign>', () async {
    wire.answer = (command) => command.startsWith('update') ? 'data:1' : null;

    await session.put(const JsKey('k'), 'v');

    expect(wire.commands.where((c) => c.startsWith('update')).single,
        contains('k.wavi@alice'));
  });

  test('get of a key the atServer does not hold is null', () async {
    // at_lookup throws the atServer's AT0015 as a KeyNotFoundException and
    // AtClientImpl.get rethrows it as an AtKeyNotFoundException.
    wire.answer = (command) => throw KeyNotFoundException('absent');

    expect(await session.get(const JsKey('absent')), isNull);
    expect(wire.commands, contains(contains('absent')));
  });

  test('put of bytes then get returns equal bytes', () async {
    final bytes = Uint8List.fromList([0, 1, 2, 250, 251, 255, 128, 7, 9]);
    String? stored;
    String? iv;
    wire.answer = (command) {
      if (command.startsWith('update')) {
        iv = RegExp(r'ivNonce:([^:]+)').firstMatch(command)?.group(1);
        stored = command.substring(command.lastIndexOf(' ') + 1).trim();
        return 'data:1';
      }
      if (command.startsWith('llookup') || command.startsWith('lookup')) {
        return 'data:${jsonEncode({
              'key': '@alice:k.wavi@alice',
              'data': stored,
              'metaData': {'isBinary': true, 'isEncrypted': true, 'ivNonce': iv}
            })}';
      }
      return null;
    };

    await session.put(const JsKey('k'), bytes);
    final got = await session.get(const JsKey('k'));

    expect(got, isA<Uint8List>());
    expect(got, bytes);
  });

  group('pairing', () {
    String record(String id, String status,
            {String app = 'tally', String device = 'Phone'}) =>
        '"$id.new.enrollments.__manage@alice":${jsonEncode({
              'appName': app,
              'deviceName': device,
              'namespace': {app: 'rw'},
              'status': status,
              'encryptedAPKAMSymmetricKey': 'wrapped',
            })}';

    // What an enrollment without __manage is told: its own record, whatever
    // the filter asked for.
    final ownRecord = 'data:{${record('own', 'approved', app: 'wavi')}}';

    Future<Object> thrownBy(Future<Object?> Function() call) async {
      try {
        await call();
      } catch (e) {
        return e;
      }
      fail('did not throw');
    }

    group('otp', () {
      test('asks for a passcode and returns it', () async {
        wire.answer =
            (command) => command.startsWith('otp:get') ? 'data:Z9Y8X7' : null;

        expect(await session.otp(), 'Z9Y8X7');
        expect(
            wire.commands.where((c) => c.startsWith('otp:get')), hasLength(1));
      });

      test('a refusal for want of __manage is unsupported', () async {
        wire.answer = (command) => throw UnAuthorizedException(
            'otp:get requires access to the __manage namespace');

        final error = await thrownBy(session.otp);

        expect(atErrorCode(error), 'unsupported');
      });
    });

    group('pendingEnrollments', () {
      test('lists only the pending requests, as filed', () async {
        wire.answer = (command) => command.startsWith('enroll:list')
            ? 'data:{${record('e1', 'pending')},${record('e2', 'pending', app: 'chat', device: 'Tab')}}'
            : null;

        final pending = await session.pendingEnrollments();

        expect(
            pending.map((e) => [e.id, e.appName, e.deviceName, e.namespaces]), [
          [
            'e1',
            'tally',
            'Phone',
            {'tally': 'rw'}
          ],
          [
            'e2',
            'chat',
            'Tab',
            {'chat': 'rw'}
          ],
        ]);
        expect(wire.commands.firstWhere((c) => c.startsWith('enroll:list')),
            contains('pending'));
      });

      test('no pending request is an empty list', () async {
        wire.answer = (command) => 'data:{}';

        expect(await session.pendingEnrollments(), isEmpty);
      });

      test('an answer that ignores the filter is unsupported', () async {
        wire.answer = (command) => ownRecord;

        final error = await thrownBy(session.pendingEnrollments);

        expect(atErrorCode(error), 'unsupported');
      });

      test('a refusal is unsupported', () async {
        wire.answer =
            (command) => throw UnAuthorizedException('not allowed to list');

        final error = await thrownBy(session.pendingEnrollments);

        expect(atErrorCode(error), 'unsupported');
      });
    });

    group('deny', () {
      test('denies the pending request', () async {
        wire.answer = (command) {
          if (command.startsWith('enroll:list')) {
            return 'data:{${record('e1', 'pending')}}';
          }
          if (command.startsWith('enroll:deny')) {
            return 'data:{"enrollmentId":"e1","status":"denied"}';
          }
          return null;
        };

        await session.deny('e1');

        expect(wire.commands.where((c) => c.startsWith('enroll:deny')).single,
            contains('e1'));
      });

      test('an id that is not pending is not unsupported', () async {
        wire.answer = (command) => 'data:{${record('e1', 'pending')}}';

        final error = await thrownBy(() => session.deny('gone'));

        expect(atErrorCode(error), 'enrollment_denied');
        expect(wire.commands.any((c) => c.startsWith('enroll:deny')), isFalse);
      });

      test('a session without __manage is unsupported', () async {
        wire.answer = (command) => ownRecord;

        final error = await thrownBy(() => session.deny('e1'));

        expect(atErrorCode(error), 'unsupported');
        expect(wire.commands.any((c) => c.startsWith('enroll:deny')), isFalse);
      });

      test('a refusal on the verb is unsupported', () async {
        wire.answer = (command) => command.startsWith('enroll:list')
            ? 'data:{${record('e1', 'pending')}}'
            : throw UnAuthorizedException('no __manage');

        final error = await thrownBy(() => session.deny('e1'));

        expect(atErrorCode(error), 'unsupported');
      });
    });

    group('approve', () {
      late String wrapped;

      setUp(() async {
        // The approver unwraps the symmetric key an enrollee RSA-wrapped to
        // the atSign's encryption public key, so the client holds a real pair.
        final pair = RsaKeyPair.generate();
        final keys = classicalAtKeys()
          ..fileLegacyMaterial(
              encryptionPublicKey: pair.atPublicKey.publicKey,
              encryptionPrivateKey: pair.atPrivateKey.privateKey);
        wrapped = base64Encode((RsaEncryptionAlgo()
              ..atPublicKey =
                  AtPublicKey.fromString(pair.atPublicKey.publicKey))
            .encrypt(utf8.encode(AESKey.generate(32).key)));
        await session.close();
        for (final c
            in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
          await c.stop();
        }
        AtClientImpl.atClientInstanceMap.clear();
        AtClientManager.getInstance().reset();
        wire = Wire();
        session = AtClientJsSession(
            await portalSession(
                atSign: '@alice',
                app: 'wavi',
                keys: keys,
                transport: (
                  lookUps: wire.lookUps,
                  finder: FixedSecondaryAddressFinder('atserver.test', 1)
                )),
            namespace: 'wavi');
      });

      String pendingList() =>
          'data:{${record('e1', 'pending').replaceFirst('"wrapped"', '"$wrapped"')}}';

      test('approves the request as filed, with no namespaces of its own',
          () async {
        var approved = false;
        wire.answer = (command) {
          if (command.startsWith('enroll:list')) {
            return approved
                ? 'data:{${record('e1', 'approved').replaceFirst('"wrapped"', '"$wrapped"')}}'
                : pendingList();
          }
          if (command.startsWith('enroll:approve')) {
            approved = true;
            return 'data:{"enrollmentId":"e1","status":"approved"}';
          }
          throw KeyNotFoundException('absent');
        };

        await session.approve('e1');

        final sent = wire.commands.where((c) => c.startsWith('enroll:approve'));
        expect(sent, hasLength(1));
        expect(sent.single, contains('"enrollmentId":"e1"'));
        expect(sent.single, isNot(contains('namespace')));
      });

      test('an id that is not pending is not unsupported', () async {
        wire.answer = (command) => pendingList();

        final error = await thrownBy(() => session.approve('gone'));

        expect(atErrorCode(error), 'enrollment_denied');
        expect(
            wire.commands.any((c) => c.startsWith('enroll:approve')), isFalse);
      });

      test('a session without __manage is unsupported', () async {
        wire.answer = (command) => ownRecord;

        final error = await thrownBy(() => session.approve('e1'));

        expect(atErrorCode(error), 'unsupported');
        expect(
            wire.commands.any((c) => c.startsWith('enroll:approve')), isFalse);
      });

      test('a refusal on the verb is unsupported', () async {
        wire.answer = (command) => command.startsWith('enroll:list')
            ? pendingList()
            : throw UnAuthorizedException('no __manage');

        final error = await thrownBy(() => session.approve('e1'));

        expect(atErrorCode(error), 'unsupported');
      });
    });
  });
}
