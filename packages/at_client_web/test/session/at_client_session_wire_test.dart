import 'dart:async';
import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_web/at_client_web.dart';
import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/js/error_codes.dart';
import 'package:at_client_web/src/session/at_client_session.dart';
import 'package:test/test.dart';

import 'wire_fakes.dart';
import '../test_utils.dart';

void main() {
  late Wire wire;
  late AtClientSession session;

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
    session = AtClientSession(client, namespace: 'wavi');
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

    /// The atServer's `enroll:fetch` answer for this session's own enrollment:
    /// its record with [status], holding [grants].
    String ownRecord(Map<String, String> grants,
            {String status = 'approved'}) =>
        'data:${jsonEncode({
              'appName': 'wavi',
              'deviceName': 'Phone',
              'namespace': grants,
              'status': status,
            })}';

    const managing = {'wavi': 'rw', '__manage': 'rw'};

    /// The atServer's answers: the session's own record for its own
    /// `enroll:fetch`, [pending] for the pending listing, then [verbs] by
    /// command.
    void serve(
        {Map<String, String> grants = managing,
        String pending = '',
        String? Function(String command)? verbs}) {
      wire.answer = (command) {
        if (command.startsWith('enroll:fetch')) return ownRecord(grants);
        if (command.startsWith('enroll:list')) return 'data:{$pending}';
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

    group('manage access', () {
      /// Runs the check through [AtClientSession.pendingEnrollments], which
      /// needs nothing beyond it, and answers whether it was allowed.
      Future<bool> allowed(
          {required String Function(String command) fetch}) async {
        wire.answer = (command) {
          if (command.startsWith('enroll:fetch')) return fetch(command);
          if (command.startsWith('enroll:list')) return 'data:{}';
          return null;
        };
        try {
          await session.pendingEnrollments();
          return true;
        } on ManageAccessRequiredException {
          return false;
        }
      }

      test(
          'A session whose approved enrollment holds __manage read-write is allowed',
          () async {
        wire.commands.clear();
        final result =
            await allowed(fetch: (_) => ownRecord({...managing, '*': 'r'}));

        expect(result, isTrue);
        final fetches =
            wire.commands.where((c) => c.startsWith('enroll:fetch'));
        expect(fetches, hasLength(1));
        expect(fetches.single, contains(ownId));
      });

      test('The primary enrollment is allowed with no server call', () async {
        // A client with no enrollment id and one whose id is the primary
        // enrollment both read no record: the primary enrollment holds
        // `*:rw` and has nothing to fetch or list.
        for (final MapEntry(key: name, value: id) in {
          'no enrollment id': null,
          'the primary id': EnrollmentConstants.primaryEnrollmentId,
        }.entries) {
          await session.close();
          final client = await portalSession(
              atSign: '@alice',
              app: 'wavi',
              keys: classicalAtKeys(enrollmentId: 'primary'),
              transport: (
                lookUps: wire.lookUps,
                finder: FixedSecondaryAddressFinder('atserver.test', 1),
                root: AtRootDomain.atsignDomain
              ));
          client.enrollmentId = id;
          session = AtClientSession(client, namespace: 'wavi');
          wire.answer =
              (command) => command.startsWith('otp:get') ? 'data:Z9Y8X7' : null;
          wire.commands.clear();

          expect(await session.otp(), 'Z9Y8X7', reason: name);
          expect(sent('enroll:fetch'), isFalse, reason: name);
          expect(sent('enroll:list'), isFalse, reason: name);
        }
      });

      test(
          'An enrollment the atServer does not list is refused with ManageAccessRequiredException',
          () async {
        wire.answer = (command) => command.startsWith('enroll:fetch')
            ? throw KeyNotFoundException('no such enrollment')
            : 'data:{}';
        expect(await thrownBy(session.pendingEnrollments),
            isA<ManageAccessRequiredException>());

        wire.answer = (command) =>
            command.startsWith('enroll:fetch') ? 'data:null' : 'data:{}';
        expect(await thrownBy(session.pendingEnrollments),
            isA<ManageAccessRequiredException>());
      });

      for (final status in EnrollmentStatus.values) {
        final isApproved = status == EnrollmentStatus.approved;
        test(
            'status ${status.name} with __manage read-write is '
            '${isApproved ? 'allowed' : 'refused'}', () async {
          final result = await allowed(
              fetch: (_) => ownRecord(managing, status: status.name));

          expect(result, isApproved);
        });
      }

      test('Only an approved enrollment is allowed, whatever it grants',
          () async {
        for (final status in EnrollmentStatus.values) {
          final result = await allowed(
              fetch: (_) => ownRecord(managing, status: status.name));

          expect(result, status == EnrollmentStatus.approved,
              reason: status.name);
        }
      });

      for (final MapEntry(key: name, value: grants) in unmanaged.entries) {
        test('an approved enrollment with $name is refused', () async {
          expect(await allowed(fetch: (_) => ownRecord(grants)), isFalse);
        });
      }

      test(
          'A transport failure reading the record reaches the caller unchanged',
          () async {
        final failure = StateError('connection reset');
        wire.answer = (command) =>
            command.startsWith('enroll:fetch') ? throw failure : 'data:{}';

        final error = await thrownBy(session.pendingEnrollments);

        expect(error, same(failure));
      });
    });

    group('otp', () {
      test('otp requests and returns a passcode', () async {
        serve(verbs: (c) => c.startsWith('otp:get') ? 'data:Z9Y8X7' : null);

        expect(await session.otp(), 'Z9Y8X7');
        expect(
            wire.commands.where((c) => c.startsWith('otp:get')), hasLength(1));
      });

      for (final MapEntry(key: name, value: grants) in unmanaged.entries) {
        test('$name is unsupported and sends no otp', () async {
          serve(grants: grants);

          final error = await thrownBy(session.otp);

          expect(errorCodeOf(error), 'unsupported');
          expect(sent('otp:get'), isFalse);
        });
      }

      test('the primary enrollment is authorised without listing enrollments',
          () async {
        // The primary enrollment holds `*:rw` and has no record to read.
        await session.close();
        final primary = await portalSession(
            atSign: '@alice',
            app: 'wavi',
            keys: classicalAtKeys(enrollmentId: 'primary'),
            transport: (
              lookUps: wire.lookUps,
              finder: FixedSecondaryAddressFinder('atserver.test', 1),
              root: AtRootDomain.atsignDomain
            ));
        session = AtClientSession(primary, namespace: 'wavi');
        wire.commands.clear();
        serve(verbs: (c) => c.startsWith('otp:get') ? 'data:Z9Y8X7' : null);

        expect(await session.otp(), 'Z9Y8X7');
        expect(sent('enroll:fetch'), isFalse);
        expect(sent('otp:get'), isTrue);
      });

      test('a refusal on the verb is unsupported', () async {
        serve(
            verbs: (c) => throw UnAuthorizedException(
                'otp:get requires access to the __manage namespace'));

        final error = await thrownBy(session.otp);

        expect(errorCodeOf(error), 'unsupported');
      });
    });

    group('pendingEnrollments', () {
      test('pendingEnrollments lists pending requests and empty when none',
          () async {
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

        serve();
        expect(await session.pendingEnrollments(), isEmpty);
      });

      for (final MapEntry(key: name, value: grants) in unmanaged.entries) {
        test('$name is unsupported and lists nothing', () async {
          serve(grants: grants, pending: record('e1', 'pending'));

          final error = await thrownBy(session.pendingEnrollments);

          expect(errorCodeOf(error), 'unsupported');
          expect(
              wire.commands.any(
                  (c) => c.startsWith('enroll:list') && c.contains('pending')),
              isFalse);
        });
      }

      test('a refusal is unsupported', () async {
        wire.answer = (command) => command.startsWith('enroll:fetch')
            ? ownRecord(managing)
            : throw UnAuthorizedException('not allowed to list');

        final error = await thrownBy(session.pendingEnrollments);

        expect(errorCodeOf(error), 'unsupported');
      });
    });

    group('deny', () {
      test(
          'deny denies a pending request and rejects unknown id with enrollment_denied',
          () async {
        serve(
            pending: record('e1', 'pending'),
            verbs: (c) => c.startsWith('enroll:deny')
                ? 'data:{"enrollmentId":"e1","status":"denied"}'
                : null);

        await session.deny('e1');

        expect(wire.commands.where((c) => c.startsWith('enroll:deny')).single,
            contains('e1'));

        wire.commands.clear();
        final error = await thrownBy(() => session.deny('gone'));

        expect(errorCodeOf(error), 'enrollment_denied');
        expect(sent('enroll:deny'), isFalse);
      });

      for (final MapEntry(key: name, value: grants) in unmanaged.entries) {
        test('$name is unsupported and denies nothing', () async {
          serve(grants: grants, pending: record('e1', 'pending'));

          final error = await thrownBy(() => session.deny('e1'));

          expect(errorCodeOf(error), 'unsupported');
          expect(sent('enroll:deny'), isFalse);
        });
      }

      test('a refusal on the verb is unsupported', () async {
        serve(
            pending: record('e1', 'pending'),
            verbs: (c) => throw UnAuthorizedException('no __manage'));

        final error = await thrownBy(() => session.deny('e1'));

        expect(errorCodeOf(error), 'unsupported');
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
        session = AtClientSession(
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

      /// Serves each id in [pending] as a pending request (built by
      /// [recordOf] when given); an approve moves its id out, after [hold]
      /// for that id completes. The ids in [failing] have their first
      /// approve refused.
      void serveDecisions(Set<String> pending,
          {Future<void> Function(String id)? hold,
          Set<String>? failing,
          String Function(String id, String status)? recordOf}) {
        final approved = <String>{};
        String build(String id, String status) => recordOf != null
            ? recordOf(id, status)
            : record(id, status, wrapped: wrapped);
        wire.answer = (command) async {
          if (command.startsWith('enroll:fetch')) return ownRecord(managing);
          if (command.startsWith('enroll:list')) {
            return 'data:{${[
              for (final id in pending) build(id, 'pending'),
              if (!command.contains('pending'))
                for (final id in approved) build(id, 'approved'),
            ].join(',')}}';
          }
          if (command.startsWith('enroll:approve')) {
            final id = RegExp(r'"enrollmentId":"(\w+)"')
                .firstMatch(command)!
                .group(1)!;
            await hold?.call(id);
            if (failing?.remove(id) ?? false) {
              throw StateError('refused');
            }
            pending.remove(id);
            approved.add(id);
            return 'data:{"enrollmentId":"$id","status":"approved"}';
          }
          throw KeyNotFoundException('absent');
        };
      }

      String pendingRecord() => record('e1', 'pending', wrapped: wrapped);

      test('approves the request as filed, with no namespaces of its own',
          () async {
        serveDecisions({'e1'});

        await session.approve('e1');

        final approvals =
            wire.commands.where((c) => c.startsWith('enroll:approve'));
        expect(approvals, hasLength(1));
        expect(approvals.single, contains('"enrollmentId":"e1"'));
        expect(approvals.single, isNot(contains('namespace')));
      });

      test("a decision reads the session's own grants once", () async {
        serveDecisions({'e1'});

        await session.approve('e1');

        final grantsReads =
            wire.commands.where((c) => c.startsWith('enroll:fetch'));
        expect(grantsReads, hasLength(1));
        expect(grantsReads.single, contains(ownId));
      });

      test('approve of an id that is not pending is enrollment_denied',
          () async {
        serve(pending: pendingRecord());

        final error = await thrownBy(() => session.approve('gone'));

        expect(errorCodeOf(error), 'enrollment_denied');
        expect(sent('enroll:approve'), isFalse);
      });

      for (final MapEntry(key: name, value: grants) in unmanaged.entries) {
        test('$name is unsupported and approves nothing', () async {
          serve(grants: grants, pending: pendingRecord());

          final error = await thrownBy(() => session.approve('e1'));

          expect(errorCodeOf(error), 'unsupported');
          expect(sent('enroll:approve'), isFalse);
        });
      }

      test('a refusal on the verb is unsupported', () async {
        serve(
            pending: pendingRecord(),
            verbs: (c) => throw UnAuthorizedException('no __manage'));

        final error = await thrownBy(() => session.approve('e1'));

        expect(errorCodeOf(error), 'unsupported');
      });

      test(
          'concurrent approve or deny on the same id rejects without sending a second approval',
          () async {
        serveDecisions({'e1'});

        final first = session.approve('e1');
        final secondError = await thrownBy(() => session.deny('e1'));
        await first;

        expect(errorCodeOf(secondError), 'enrollment_in_flight');
        expect(wire.commands.where((c) => c.startsWith('enroll:approve')),
            hasLength(1));
        expect(
            wire.commands.where((c) => c.startsWith('enroll:deny')), isEmpty);
      });

      int approvals() =>
          wire.commands.where((c) => c.startsWith('enroll:approve')).length;

      test(
          'a decision repeated after the first settled is enrollment_denied, not enrollment_in_flight',
          () async {
        serveDecisions({'e1'});
        await session.approve('e1');
        final before = wire.commands.length;

        for (final decide in [session.approve, session.deny]) {
          final error = await thrownBy(() => decide('e1'));
          expect(errorCodeOf(error), 'enrollment_denied');
        }

        expect(
            wire.commands.skip(before).where((c) =>
                c.startsWith('enroll:approve') || c.startsWith('enroll:deny')),
            isEmpty);
      });

      test('a decision in flight on one id does not hold up another id',
          () async {
        final gate = Completer<void>();
        serveDecisions({'e1', 'e2'},
            hold: (id) => id == 'e1' ? gate.future : Future.value());

        final first = session.approve('e1');
        await session.approve('e2');

        expect(approvals(), 2);
        gate.complete();
        await first;
      });

      test('a failed decision releases the id for another attempt', () async {
        serveDecisions({'e1'}, failing: {'e1'});

        final failure = await thrownBy(() => session.approve('e1'));
        expect(errorCodeOf(failure), isNot('enrollment_in_flight'));
        await session.approve('e1');

        expect(approvals(), 2);
      });

      test(
          'the in-flight failure is still an enrollment failure to a Dart caller',
          () async {
        final gate = Completer<void>();
        final reached = Completer<void>();
        serveDecisions({'e1'}, hold: (_) {
          reached.complete();
          return gate.future;
        });

        final first = session.approve('e1');
        await reached.future;
        final lists =
            wire.commands.where((c) => c.startsWith('enroll:fetch')).length;
        Object? caught;
        try {
          await session.approve('e1');
        } on AtEnrollmentException catch (e) {
          caught = e;
        }
        final listsAfter =
            wire.commands.where((c) => c.startsWith('enroll:fetch')).length;
        gate.complete();
        await first;

        expect(caught, isA<EnrollmentInFlightException>());
        expect(errorCodeOf(caught!), 'enrollment_in_flight');
        expect(listsAfter, lists);
      });

      test('key conveyance failure rejects with enrollment_conveyance_failed',
          () async {
        String withBadKeyPackage(String id, String status) =>
            '"$id.new.enrollments.__manage@alice":${jsonEncode({
                  'appName': 'tally',
                  'deviceName': 'Phone',
                  'namespace': {'tally': 'rw'},
                  'status': status,
                  'encryptedAPKAMSymmetricKey': wrapped,
                  'metadata': {'keyPackage': 'not-a-signed-envelope'},
                })}';
        serveDecisions({'e1'}, recordOf: withBadKeyPackage);

        final error = await thrownBy(() => session.approve('e1'));

        expect(error, isA<EnrollmentConveyanceException>());
        expect(errorCodeOf(error), 'enrollment_conveyance_failed');
      });
    });
  });
}
