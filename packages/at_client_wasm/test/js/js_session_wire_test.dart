import 'dart:convert';

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
          finder: FixedSecondaryAddressFinder('atserver.test', 1),
          root: AtRootDomain.atsignDomain
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

  group('pairing', () {
    const ownId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';

    String record(String id, String status,
            {String app = 'tally',
            String device = 'Phone',
            Map<String, String>? namespaces,
            String wrapped = 'wrapped'}) =>
        '"$id.new.enrollments.__manage@alice":${jsonEncode({
              'appName': app,
              'deviceName': device,
              'namespace': namespaces ?? {app: 'rw'},
              'status': status,
              'encryptedAPKAMSymmetricKey': wrapped,
            })}';

    /// This session's own enrollment record, holding [grants].
    String own(Map<String, String> grants) =>
        record(ownId, 'approved', app: 'wavi', namespaces: grants);

    const managing = {'wavi': 'rw', '__manage': 'rw'};

    /// The atServer's answers: the session's own record for an unfiltered
    /// listing, [pending] for the pending filter, then [verbs] by command.
    void serve(
        {Map<String, String> grants = managing,
        String pending = '',
        String? Function(String command)? verbs}) {
      wire.answer = (command) {
        if (command.startsWith('enroll:list')) {
          return command.contains('pending')
              ? 'data:{$pending}'
              : 'data:{${own(grants)}}';
        }
        return verbs?.call(command);
      };
    }

    Future<Object> thrownBy(Future<Object?> Function() call) async {
      try {
        await call();
      } catch (e) {
        return e;
      }
      fail('did not throw');
    }

    bool sent(String verb) => wire.commands.any((c) => c.startsWith(verb));

    // A session whose grants lack a read-write __manage must be refused
    // before any pairing verb goes out.
    final unmanaged = <String, Map<String, String>>{
      'no __manage grant': {'wavi': 'rw'},
      'a read-only __manage grant': {'wavi': 'rw', '__manage': 'r'},
    };

    group('otp', () {
      test('asks for a passcode and returns it', () async {
        serve(verbs: (c) => c.startsWith('otp:get') ? 'data:Z9Y8X7' : null);

        expect(await session.otp(), 'Z9Y8X7');
        expect(
            wire.commands.where((c) => c.startsWith('otp:get')), hasLength(1));
      });

      for (final MapEntry(key: name, value: grants) in unmanaged.entries) {
        test('$name is unsupported and sends no otp', () async {
          serve(grants: grants);

          final error = await thrownBy(session.otp);

          expect(atErrorCode(error), 'unsupported');
          expect(sent('otp:get'), isFalse);
        });
      }

      test('a refusal on the verb is unsupported', () async {
        serve(
            verbs: (c) => throw UnAuthorizedException(
                'otp:get requires access to the __manage namespace'));

        final error = await thrownBy(session.otp);

        expect(atErrorCode(error), 'unsupported');
      });
    });

    group('pendingEnrollments', () {
      test('lists only the pending requests, as filed', () async {
        serve(
            pending: '${record('e1', 'pending')},'
                '${record('e2', 'pending', app: 'chat', device: 'Tab')}');

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
      });

      test('no pending request is an empty list', () async {
        serve();

        expect(await session.pendingEnrollments(), isEmpty);
      });

      for (final MapEntry(key: name, value: grants) in unmanaged.entries) {
        test('$name is unsupported and lists nothing', () async {
          serve(grants: grants, pending: record('e1', 'pending'));

          final error = await thrownBy(session.pendingEnrollments);

          expect(atErrorCode(error), 'unsupported');
          expect(
              wire.commands.any(
                  (c) => c.startsWith('enroll:list') && c.contains('pending')),
              isFalse);
        });
      }

      test('a refusal is unsupported', () async {
        wire.answer = (command) => command.contains('pending')
            ? throw UnAuthorizedException('not allowed to list')
            : 'data:{${own(managing)}}';

        final error = await thrownBy(session.pendingEnrollments);

        expect(atErrorCode(error), 'unsupported');
      });
    });

    group('deny', () {
      test('denies the pending request', () async {
        serve(
            pending: record('e1', 'pending'),
            verbs: (c) => c.startsWith('enroll:deny')
                ? 'data:{"enrollmentId":"e1","status":"denied"}'
                : null);

        await session.deny('e1');

        expect(wire.commands.where((c) => c.startsWith('enroll:deny')).single,
            contains('e1'));
      });

      test('deny of an id that is not pending is enrollment_denied', () async {
        serve(pending: record('e1', 'pending'));

        final error = await thrownBy(() => session.deny('gone'));

        expect(atErrorCode(error), 'enrollment_denied');
        expect(sent('enroll:deny'), isFalse);
      });

      for (final MapEntry(key: name, value: grants) in unmanaged.entries) {
        test('$name is unsupported and denies nothing', () async {
          serve(grants: grants, pending: record('e1', 'pending'));

          final error = await thrownBy(() => session.deny('e1'));

          expect(atErrorCode(error), 'unsupported');
          expect(sent('enroll:deny'), isFalse);
        });
      }

      test('a refusal on the verb is unsupported', () async {
        serve(
            pending: record('e1', 'pending'),
            verbs: (c) => throw UnAuthorizedException('no __manage'));

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
                  finder: FixedSecondaryAddressFinder('atserver.test', 1),
                  root: AtRootDomain.atsignDomain
                )),
            namespace: 'wavi');
      });

      String pendingRecord() => record('e1', 'pending', wrapped: wrapped);

      test('approves the request as filed, with no namespaces of its own',
          () async {
        var approved = false;
        wire.answer = (command) {
          if (command.startsWith('enroll:list')) {
            final filtered =
                command.contains('pending') || command.contains('approved');
            if (!filtered) return 'data:{${own(managing)}}';
            return approved
                ? 'data:{${record('e1', 'approved', wrapped: wrapped)}}'
                : 'data:{${pendingRecord()}}';
          }
          if (command.startsWith('enroll:approve')) {
            approved = true;
            return 'data:{"enrollmentId":"e1","status":"approved"}';
          }
          throw KeyNotFoundException('absent');
        };

        await session.approve('e1');

        final approvals =
            wire.commands.where((c) => c.startsWith('enroll:approve'));
        expect(approvals, hasLength(1));
        expect(approvals.single, contains('"enrollmentId":"e1"'));
        expect(approvals.single, isNot(contains('namespace')));
      });

      test('approve of an id that is not pending is enrollment_denied',
          () async {
        serve(pending: pendingRecord());

        final error = await thrownBy(() => session.approve('gone'));

        expect(atErrorCode(error), 'enrollment_denied');
        expect(sent('enroll:approve'), isFalse);
      });

      for (final MapEntry(key: name, value: grants) in unmanaged.entries) {
        test('$name is unsupported and approves nothing', () async {
          serve(grants: grants, pending: pendingRecord());

          final error = await thrownBy(() => session.approve('e1'));

          expect(atErrorCode(error), 'unsupported');
          expect(sent('enroll:approve'), isFalse);
        });
      }

      test('a refusal on the verb is unsupported', () async {
        serve(
            pending: pendingRecord(),
            verbs: (c) => throw UnAuthorizedException('no __manage'));

        final error = await thrownBy(() => session.approve('e1'));

        expect(atErrorCode(error), 'unsupported');
      });
    });
  });
}
