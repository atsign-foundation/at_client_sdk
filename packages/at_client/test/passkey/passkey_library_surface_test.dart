import 'package:at_auth/at_auth.dart' show AtKeys, WrittenAtKeysIo;
import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client/passkey.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart' show Fake;
import 'package:test/test.dart';

class _Gateway extends Fake implements EnrollmentGateway {
  @override
  String get device => 'browser';
}

class _Session extends Fake implements EnrollmentSession {
  @override
  String get enrollmentId => 'eid1';
}

class _Finder extends Fake implements SecondaryAddressFinder {}

class _Documents extends Fake implements EnrollmentDocumentStore {}

class _PointerReader extends Fake implements EnrollmentPointerReader {}

class _Pointers extends Fake implements EnrollmentPointerStore {}

class _Persistence implements StoragePersistence {
  @override
  Future<bool> requestPersist() async => true;
}

/// Every symbol `package:at_client/passkey.dart` exports, each used through
/// that library alone, so a symbol dropped from it fails to compile here.
void main() {
  group('typedefs', () {
    test('ApkamKeyPair is the record the activator is handed', () async {
      const pair = (publicKey: 'cHVi', privateKey: 'cHJpdg==');
      ApkamKeyPair? seen;
      Future<AtKeys> activate(
          {required String atSign,
          required String cram,
          required ApkamKeyPair apkamKeyPair}) async {
        seen = apkamKeyPair;
        throw StateError('stop');
      }

      final Activator activator = activate;
      await expectLater(
          activator(atSign: '@alice', cram: 'c', apkamKeyPair: pair),
          throwsStateError);
      expect(seen, pair);
    });

    test('ClientOpener is what the gateway runs to open a client', () {
      Future<AtClient> open(
              {required AtLookupMuxable lookUp,
              required String atSign,
              required String enrollmentId,
              required WrittenAtKeysIo keysIo}) async =>
          throw StateError('no client');

      final ClientOpener opener = open;
      expect(opener, same(open));
    });
  });

  group('classes', () {
    test('the stores and gateway are implementable', () {
      expect(_Gateway().device, 'browser');
      expect(_Session().enrollmentId, 'eid1');
      expect(_Documents(), isA<EnrollmentDocumentStore>());
      expect(_PointerReader(), isA<EnrollmentPointerReader>());
      expect(_Pointers(), isA<EnrollmentPointerReader>());
      expect(_Pointers(), isA<EnrollmentPointerStore>());
    });

    test('StoragePersistence answers a persistence request', () async {
      expect(await _Persistence().requestPersist(), isTrue);
    });

    test('the lookup pointer reader and the gateway take their seams', () {
      final reader = LookupEnrollmentPointerReader(
          lookUps: ({
            required atSign,
            required rootDomain,
            required authenticator,
            secondaryAddressFinder,
          }) =>
              throw StateError('no lookUp'),
          rootDomain: AtRootDomain.atsignDomain);
      expect(reader, isA<EnrollmentPointerReader>());

      final gateway = AtAuthEnrollmentGateway(
          lookUps: ({
            required atSign,
            required rootDomain,
            required authenticator,
            secondaryAddressFinder,
          }) =>
              throw StateError('no lookUp'),
          finder: _Finder(),
          root: AtRootDomain.atsignDomain,
          app: 'wavi',
          device: 'browser',
          clientOpener: (
                  {required lookUp,
                  required atSign,
                  required enrollmentId,
                  required keysIo}) async =>
              throw StateError('no client'));
      expect(gateway, isA<EnrollmentGateway>());
      expect(gateway.device, 'browser');
    });

    test('PasskeyCustody and AtServerAtKeysIo are named', () {
      final constructors = [PasskeyCustody.new, AtServerAtKeysIo.new];
      expect(constructors, hasLength(2));
    });
  });

  group('enums', () {
    test('CompletionDue names what a completion-due record says', () {
      expect(CompletionDue.values,
          [CompletionDue.activated, CompletionDue.cramSecretDeleted]);
    });
  });

  group('exceptions', () {
    test('each is an AtException carrying what it names', () {
      final exceptions = <AtException>[
        AtServerAtKeysWriteException('refused'),
        PkamRefusedException('eid1'),
        PasskeyLostException('@alice', 'no passkey'),
        MissingAtKeysDocumentException('eid1'),
        PublicKeyMismatchException(),
        AtServerAtKeysLockedException('locked'),
        PasskeyOnboardingIncompleteException('@alice'.toAtsign(),
            cause: AtException('refused')),
      ];
      for (final e in exceptions) {
        expect(e.message, isNotEmpty, reason: '${e.runtimeType}');
      }
      final incomplete = exceptions[6] as PasskeyOnboardingIncompleteException;
      expect(incomplete.atSign, '@alice');
      expect(incomplete.cause, isA<AtException>());
      expect((exceptions[1] as PkamRefusedException).enrollmentId, 'eid1');
      expect((exceptions[3] as MissingAtKeysDocumentException).enrollmentId,
          'eid1');
      expect((exceptions[2] as PasskeyLostException).atSign, '@alice');
      expect(exceptions[5], isA<AtServerAtKeysWriteException>());
    });
  });
}
