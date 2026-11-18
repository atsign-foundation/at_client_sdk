// The keys an enrollee holds before its handshake are set through their flat
// fields, as `submit` leaves them.
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils/fake_cram_at_server.dart';
import 'test_utils/pkam_pin.dart';

/// Hands an authenticator scripted atServer replies, one per command.
class _ScriptedExecutor implements AtCommandExecutor {
  _ScriptedExecutor(this.replies);

  final List<String> replies;
  final List<String> sent = [];

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return replies.removeAt(0);
  }
}

/// The two forms an atServer's global exception handler writes a refusal in:
/// plain on a connection whose `from:` named no version, JSON on one whose
/// `from:` named a version above 3.0.37.
final Map<String, String Function(String code, String description)> forms = {
  'plain': (code, description) => 'error:$code-$description',
  'JSON': (code, description) => 'error:${jsonEncode({
            'errorCode': code,
            'errorDescription': description,
          })}',
};

/// Each reader of an atServer's refusal reads it the same in either form.
///
/// Catalogue: features/enrollment/expired_enrollment_codes.feature
void main() {
  const atSign = pkamPinAtSign;
  const pkamRefused = 'Exception: pkam authentication failed';

  AtKeys pkamKeys() => AtKeys()
    ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap[atSign]!)
    ..apkamPrivateKey = AtBytes.fromString(demo.pkamPrivateKeyMap[atSign]!)
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(demo.encryptionPublicKeyMap[atSign]!)
    ..apkamSymmetricKey =
        AtBytes.fromString(demo.apkamSymmetricKeyMap[atSign]!);

  TypeMatcher<UnAuthenticatedException> refusalNaming(String code) =>
      isA<UnAuthenticatedException>()
          .having((e) => e.message, 'message', contains(code));

  forms.forEach((form, refusal) {
    group('Given an atServer that refuses in the $form form', () {
      final pkamAuthenticators = <String, AtAuthenticator Function()>{
        'authenticatorFor, signing PKAM': () => authenticatorFor(
            InMemoryAtKeysIo.holding(atSign, pkamKeys()), atSign),
        'authenticatorForPrivateKey': () =>
            authenticatorForPrivateKey(atSign, demo.pkamPrivateKeyMap[atSign]!),
      };
      final cramAuthenticators = <String, AtAuthenticator Function()>{
        'authenticatorForCramSecret': () =>
            authenticatorForCramSecret(atSign, 'secret'),
        'authenticatorFor, falling back to CRAM': () =>
            authenticatorFor(InMemoryAtKeysIo(), atSign, cramSecret: 'secret'),
      };

      pkamAuthenticators.forEach((name, build) {
        test(
            'when $name\'s pkam: is refused, then it throws an '
            'UnAuthenticatedException naming the code', () async {
          final executor = _ScriptedExecutor(
              ['data:$pkamPinChallenge', refusal('AT0401', pkamRefused)]);

          await expectLater(
              build()(executor), throwsA(refusalNaming('AT0401')));
          expect(executor.sent.last, startsWith('pkam:'),
              reason: 'the control: the refusal answered the pkam:');
        });

        test(
            'when $name\'s from: is refused, then it throws an '
            'UnAuthenticatedException and signs nothing', () async {
          final executor = _ScriptedExecutor(
              [refusal('AT0013', 'Exception: Unable to connect')]);

          await expectLater(
              build()(executor), throwsA(isA<UnAuthenticatedException>()));
          expect(executor.sent, hasLength(1));
        });
      });

      cramAuthenticators.forEach((name, build) {
        test(
            'when $name\'s cram: is refused, then it throws an '
            'UnAuthenticatedException naming the code', () async {
          final executor = _ScriptedExecutor([
            'data:$pkamPinChallenge',
            refusal('AT0401', 'Exception: Authentication Failed')
          ]);

          await expectLater(
              build()(executor), throwsA(refusalNaming('AT0401')));
          expect(executor.sent.last, startsWith('cram:'));
        });
      });

      test(
          'when CramAuthenticator\'s cram: is refused, then it throws an '
          'UnAuthenticatedException saying CRAM failed and naming the code',
          () async {
        final atServer = FakeCramAtServer(atSign,
            cramReply: refusal('AT0401', 'Exception: Authentication Failed'));
        final lookUp = atServer.lookUp();
        addTearDown(lookUp.close);

        await expectLater(
            CramAuthenticator()
                .authenticate(atSign, 'secret', lookUp, clientConfig: const {}),
            throwsA(refusalNaming('AT0401').having((e) => e.message, 'message',
                startsWith('Cram authentication failed'))));
      });

      test(
          'when PkamAuthenticator\'s pkam: is refused, then it throws an '
          'UnAuthenticatedException naming the code', () async {
        final atServer = FakeCramAtServer(atSign,
            cramReply: 'data:success',
            answer: (command) => command.startsWith('pkam:')
                ? refusal('AT0401', pkamRefused)
                : null);
        final lookUp = atServer.lookUp()
          ..authenticator = authenticatorFor(
              InMemoryAtKeysIo.holding(atSign, pkamKeys()), atSign);
        addTearDown(lookUp.close);

        await expectLater(PkamAuthenticator().authenticate(atSign, lookUp),
            throwsA(refusalNaming('AT0401')));
      });

      group('when an activation is refused at a step', () {
        Future<String> activateOver(FakeCramAtServer atServer,
            {bool awaitProvisioning = false}) {
          final lookUp = atServer.lookUp();
          addTearDown(lookUp.close);
          return activateAtSign(
              atSign: atSign,
              cramSecret: 'the-one-time-secret',
              keys: InMemoryAtKeysIo(),
              signingAlgo: SigningAlgoType.rsa2048,
              atLookUp: lookUp,
              awaitProvisioning: awaitProvisioning);
        }

        FakeCramAtServer refusing(String prefix, String reply) =>
            FakeCramAtServer(atSign,
                cramReply: 'data:success',
                answer: (command) => command.startsWith(prefix) ? reply : null);

        test(
            'then a lookup:publickey refused as AT0015 while it waits to be '
            'provisioned reads as not activated, and it activates', () async {
          final atServer = refusing('lookup:publickey',
              refusal('AT0015', 'Exception: public:publickey does not exist'));

          expect(await activateOver(atServer, awaitProvisioning: true), 'e-1');
          expect(
              atServer.written.where((c) => c.startsWith('lookup:publickey')),
              isNotEmpty,
              reason: 'the control: the provisioning wait asked');
        });

        test(
            'then a refused cram: throws an UnAuthenticatedException naming '
            'the code', () async {
          await expectLater(
              activateOver(FakeCramAtServer(atSign,
                  cramReply:
                      refusal('AT0401', 'Exception: Authentication Failed'))),
              throwsA(refusalNaming('AT0401')));
        });

        test(
            'then a refused enroll:request throws an AtLookUpException with '
            'the atServer\'s code', () async {
          await expectLater(
              activateOver(refusing('enroll:request',
                  refusal('AT0011', 'Exception: Internal server exception'))),
              throwsA(isA<AtLookUpException>()
                  .having((e) => e.errorCode, 'errorCode', 'AT0011')));
        });

        test(
            'then a refused pkam: throws an AtAuthenticationException naming '
            'the code', () async {
          await expectLater(
              activateOver(refusing('pkam:', refusal('AT0401', pkamRefused))),
              throwsA(isA<AtAuthenticationException>()
                  .having((e) => e.message, 'message', contains('AT0401'))));
        });

        for (final verb in ['update:', 'delete:']) {
          test(
              'then a refused $verb throws an AtLookUpException with the '
              'atServer\'s code', () async {
            await expectLater(
                activateOver(refusing(
                    verb, refusal('AT0009', 'Exception: UnAuthorized client'))),
                throwsA(isA<AtLookUpException>()
                    .having((e) => e.errorCode, 'errorCode', 'AT0009')));
          });
        }
      });
    });
  });

  group('the approval handshake', () {
    const enrollmentId = '123';
    const maxRetries = 2;

    /// An atServer whose `pkam:` answers [pkamReplies] in turn and then
    /// accepts, and whose two key fetches answer as an approval leaves them,
    /// or with [keysReply] in their place.
    Future<FakeCramAtServer> atServer(List<String> pkamReplies,
        {String? keysReply}) async {
      final sealer =
          AESEncryptionAlgo(AESKey(demo.apkamSymmetricKeyMap[atSign]!));
      Future<String> sealed(String value) async => base64.encode(
          await sealer.encrypt(Uint8List.fromList(utf8.encode(value)),
              iv: InitialisationVector.legacy()));
      final privateKey = 'data:${jsonEncode({
            'value': await sealed(demo.encryptionPrivateKeyMap[atSign]!)
          })}';
      final selfKey = 'data:${jsonEncode({
            'value': await sealed(demo.aesKeyMap[atSign]!)
          })}';
      final queued = [...pkamReplies];
      return FakeCramAtServer(atSign, cramReply: 'data:success',
          answer: (command) {
        if (command.startsWith('pkam:')) {
          return queued.isEmpty ? 'data:success' : queued.removeAt(0);
        }
        if (command.startsWith('keys:get:')) {
          return keysReply ??
              (command.contains('default_enc_private_key')
                  ? privateKey
                  : selfKey);
        }
        return null;
      });
    }

    Future<void> waitOver(FakeCramAtServer atServer) {
      final lookUp = atServer.lookUp();
      addTearDown(lookUp.close);
      return AtEnrollmentImpl().waitForApproval(
          AtEnrollmentResponse(enrollmentId, EnrollmentStatus.pending,
              atSign: atSign,
              rootDomain: AtRootDomain.atsignDomain,
              atAuthKeys: pkamKeys()),
          atLookup: lookUp,
          maxRetries: maxRetries,
          retryInterval: const Duration(milliseconds: 1),
          logProgress: false);
    }

    int polls(FakeCramAtServer atServer) =>
        atServer.written.where((c) => c.startsWith('pkam:')).length;

    forms.forEach((form, refusal) {
      test(
          'Given AT0401 in the $form form on more consecutive polls than its '
          'retry budget, when it waits, then it keeps waiting and is approved',
          () async {
        final server = await atServer(
            List.filled(maxRetries + 2, refusal('AT0401', pkamRefused)));

        await waitOver(server);

        expect(polls(server), maxRetries + 3,
            reason: 'AT0401 is an answer, not a failure: it spends nothing');
      });

      test(
          'Given a key fetch refused in the $form form, when it collects the '
          'keys, then it throws an AtLookUpException with the atServer\'s code',
          () async {
        final server = await atServer([],
            keysReply: refusal('AT0015', 'Exception: key not found'));

        await expectLater(
            waitOver(server),
            throwsA(isA<AtLookUpException>()
                .having((e) => e.errorCode, 'errorCode', 'AT0015')));
      });
    });

    /// The enrollment-state refusals, which an atServer writes as
    /// `error:<code>:<text>` whatever the `from:` named.
    final enrollmentStates = {
      'AT0026': 'enrollment_id: $enrollmentId is pending',
      'AT0025': 'enrollment_id: $enrollmentId is denied',
      'AT0028': 'enrollment_id: $enrollmentId is expired or invalid',
      'AT0029': 'enrollment_id: $enrollmentId is expired or invalid',
    };
    final writtenForms = <String, String Function(String, String)>{
      'colon': (code, text) => 'error:$code:$text',
      ...forms,
    };
    writtenForms.forEach((form, refusal) {
      group('Given enrollment-state refusals in the $form form', () {
        test('AT0026 on every poll keeps the wait going until approval',
            () async {
          final server = await atServer(List.filled(
              maxRetries + 2, refusal('AT0026', enrollmentStates['AT0026']!)));

          await waitOver(server);

          expect(polls(server), maxRetries + 3);
        });

        test('AT0025 ends the wait on its first poll, as denied', () async {
          final server =
              await atServer([refusal('AT0025', enrollmentStates['AT0025']!)]);

          await expectLater(
              waitOver(server),
              throwsA(isA<AtEnrollmentDeniedException>()
                  .having((e) => e.message, 'message', contains('denied'))));
          expect(polls(server), 1);
        });

        for (final code in ['AT0028', 'AT0029']) {
          test('$code ends the wait on its first poll, as expired',
              () async {
            final server =
                await atServer([refusal(code, enrollmentStates[code]!)]);

            await expectLater(
                waitOver(server),
                throwsA(isA<AtEnrollmentExpiredException>().having(
                    (e) => e.message,
                    'message',
                    contains('has expired or does not exist'))));
            expect(polls(server), 1);
          });
        }
      });
    });

    group('The enrollment wait ends as expired on <code>', () {
      const expired = 'enrollment_id: $enrollmentId is expired or invalid';
      final rows = {
        'AT0028, in the colon form': 'error:AT0028:$expired',
        'AT0029, in the colon form': 'error:AT0029:$expired',
        'AT0029, in the JSON form': 'error:${jsonEncode({
              'errorCode': 'AT0029',
              'errorDescription': expired,
            })}',
      };
      rows.forEach((row, reply) {
        test(row, () async {
          final server = await atServer([reply]);

          Object? caught;
          try {
            await waitOver(server);
          } on AtEnrollmentException catch (e) {
            caught = e;
          }

          expect(
              caught,
              isA<AtEnrollmentExpiredException>()
                  .having((e) => e.message, 'message', contains(reply)));
          expect(caught, isA<AtInvalidEnrollmentException>(),
              reason: 'a catch of either type catches it');
          expect(polls(server), 1, reason: 'an expiry is not polled again');
        });
      });

      test(
          'Given AT0011 on every poll, when it waits, then it ends as a '
          'refusal it cannot resolve, not as expired', () async {
        final server = await atServer(List.filled(
            maxRetries + 2, 'error:AT0011:Internal server exception'));

        Object? caught;
        try {
          await waitOver(server);
        } on AtEnrollmentException catch (e) {
          caught = e;
        }

        expect(caught, isNot(isA<AtEnrollmentExpiredException>()));
        expect(
            caught,
            isA<AtEnrollmentException>().having(
                (e) => e.message, 'message', contains('cannot resolve')));
        expect(polls(server), maxRetries + 1);
      });

      test(
          'Given AT0011 saying "permission denied" on every poll, when it '
          'waits, then it ends as a refusal it cannot resolve, not as denied',
          () async {
        final server = await atServer(List.filled(maxRetries + 2,
            'error:AT0011:Internal server exception: permission denied'));

        Object? caught;
        try {
          await waitOver(server);
        } on AtEnrollmentException catch (e) {
          caught = e;
        }

        expect(caught, isNot(isA<AtEnrollmentDeniedException>()));
        expect(
            caught,
            isA<AtEnrollmentException>().having(
                (e) => e.message, 'message', contains('cannot resolve')));
        expect(polls(server), maxRetries + 1);
      });
    });

    /// Refusals whose code cannot be read where an atServer writes it.
    final unreadable = {
      'a refusal with no error: in it': 'data:refused',
      'a JSON body that does not parse': 'error:{"errorCode":"AT0401"',
      'a JSON body that is not an object': 'error:["AT0401"]',
      'a JSON code that is a number': 'error:{"errorCode":401}',
      'a JSON code that is a list': 'error:{"errorCode":["AT0401"]}',
      'a code that does not lead the reply':
          'error:Exception: AT0401 pkam authentication failed',
      'a description naming a second error:':
          'error:{"errorCode":"AT0027","errorDescription":"was error:AT0401"}',
    };
    unreadable.forEach((what, reply) {
      test(
          'Given $what on every poll, when it waits, then it ends once its '
          'retry budget is spent, as a refusal it cannot resolve', () async {
        final server = await atServer(List.filled(maxRetries + 2, reply));

        await expectLater(
            waitOver(server),
            throwsA(isA<AtEnrollmentException>().having(
                (e) => e.message, 'message', contains('cannot resolve'))));
        expect(polls(server), maxRetries + 1,
            reason: 'a code that cannot be read is no approval to wait for');
      });
    });
  });
}
