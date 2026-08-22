/// Exact-string pins over the enroll/otp verb commands and keyfile tokens
/// at_auth owns, ahead of the PQ refactor that will relocate or consolidate
/// their emitters.
///
/// The enroll:request variants already have exact wire pins
/// (first_enrollment_test.dart, at_self_enrollment_test.dart). What this file
/// pins is the rest of the verb surface — approve/deny/revoke/list/otp —
/// where today's tests match `startsWith('enroll:approve')` and would stay
/// green through any change to the JSON that follows the prefix.
///
/// Everything here is FROZEN wire or at-rest contract.
library;

import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

void main() {
  const atSign = '@alice🛠';

  /// A lookup whose atChops holds the demo keys, recording every command.
  ({MockAtLookUp lookUp, List<String> commands}) lookUp(
      {String response = 'data:{"status":"approved","enrollmentId":"id-1"}'}) {
    final mock = MockAtLookUp();
    final commands = <String>[];
    final atChopsKeys = AtChopsKeys.create(
        AtEncryptionKeyPair.create(
            encryptionPublicKeyMap[atSign]!, encryptionPrivateKeyMap[atSign]!),
        AtPkamKeyPair.create(
            pkamPublicKeyMap[atSign]!, pkamPrivateKeyMap[atSign]!));
    atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKeyMap[atSign]!);
    atChopsKeys.selfEncryptionKey = AESKey(aesKeyMap[atSign]!);
    when(() => mock.atChops).thenReturn(AtChopsImpl(atChopsKeys));
    when(() => mock.executeCommand(any(), auth: true)).thenAnswer((inv) async {
      commands.add(inv.positionalArguments[0] as String);
      return response;
    });
    return (lookUp: mock, commands: commands);
  }

  group('FROZEN: the enroll verb commands past their prefixes', () {
    test('enroll:approve carries exactly these five JSON keys', () async {
      final l = lookUp();
      // approve() RSA-decrypts the conveyed key before it builds the command,
      // so the decision must carry a genuinely encrypted one.
      final encryptedApkamSymmetricKey =
          RSAPublicKey.fromString(encryptionPublicKeyMap[atSign]!)
              .encrypt(apkamSymmetricKeyMap[atSign]!);
      final decision = EnrollmentRequestDecision.approved(
        enrollmentId: 'id-1',
        apkamSymmetricKey: AtBytes.fromString(encryptedApkamSymmetricKey),
        atSign: atSign,
      );

      await AtEnrollmentImpl().approve(decision, l.lookUp);

      final command = l.commands.single;
      expect(command, startsWith('enroll:approve:'));
      expect(command, endsWith('\n'));
      final json = jsonDecode(
              command.substring('enroll:approve:'.length, command.length - 1))
          as Map<String, dynamic>;
      // The long first key is an INLINE literal in the emitter:
      // 'encryptedDefaultEncryptionPrivateKey'. AtConstants has a
      // similarly-named constant whose value is the DIFFERENT string
      // 'encryptedDefaultEncPrivateKey' — a consolidation that "fixes"
      // approve onto the constant changes the wire. This pin is what makes
      // that fail loudly.
      expect(json.keys.toList(), [
        'enrollmentId',
        'encryptedDefaultEncryptionPrivateKey',
        'encPrivateKeyIV',
        'encryptedDefaultSelfEncryptionKey',
        'selfEncKeyIV',
      ]);
      expect(json['enrollmentId'], 'id-1');
    });

    test('enroll:deny is the builder form', () async {
      final l = lookUp(
          response: 'data:{"status":"denied","enrollmentId":"id-1"}');

      await AtEnrollmentImpl()
          .deny(EnrollmentRequestDecision.denied('id-1', atSign), l.lookUp);

      expect(l.commands.single, 'enroll:deny:{"enrollmentId":"id-1"}\n');
    });

    test('enroll:revoke is the builder form', () async {
      final l = lookUp(
          response: 'data:{"status":"revoked","enrollmentId":"id-1"}');

      await AtEnrollmentImpl()
          .revoke(EnrollmentRequestDecision.denied('id-1', atSign), l.lookUp);

      expect(l.commands.single, 'enroll:revoke:{"enrollmentId":"id-1"}\n');
    });

    test('enroll:list without filters is the bare verb', () async {
      final l = lookUp(response: 'data:{}');

      await AtEnrollmentImpl().list(null, l.lookUp);

      expect(l.commands.single, 'enroll:list\n');
    });

    test('enroll:list joins all statuses into ONE array element', () async {
      final l = lookUp(response: 'data:{}');

      await AtEnrollmentImpl().list(
          [EnrollmentStatus.approved, EnrollmentStatus.pending], l.lookUp);

      // Not a JSON list of names — the filter values are comma-joined inside
      // a single array element. The atServer parses this form, so it is the
      // contract, however it looks; EnrollVerbBuilder would generate a proper
      // string list, which is precisely why this hand-built emitter needs its
      // own pin before any consolidation onto the builder.
      expect(l.commands.single,
          'enroll:list:{"enrollmentStatusFilter":["approved,pending"]}\n');
    });
  });

  group('FROZEN: the post-approval handshake key fetches', () {
    test('the two keys:get commands, full string including .__manage suffix',
        () async {
      // The emitters build these from inline segment literals; the existing
      // pins match only the prefix, leaving '.__manage<atSign>\n' unguarded.
      // The CLI carries its own duplicate declaration of the same two wire
      // strings — when the consolidation deletes that copy and delegates
      // here, these emitters become the single source, and this the guard.
      final mock = MockAtLookUp();
      final commands = <String>[];
      final apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;
      final iv = AtChopsUtil.generateRandomIV(16);
      final ivB64 = base64Encode(iv.ivBytes);
      final aes = StringAESEncryptor(AESKey(apkamSymmetricKey));
      when(() => mock.pkamAuthenticate(enrollmentId: '123'))
          .thenAnswer((_) async => true);
      // The fetches ride the just-authenticated connection: executeCommand
      // is called with NO auth argument (unlike every enroll: verb).
      when(() => mock.executeCommand(any())).thenAnswer((inv) async {
        final command = inv.positionalArguments[0] as String;
        commands.add(command);
        return jsonEncode({
          'value': aes.encrypt(
              command.contains('default_enc_private_key')
                  ? encryptionPrivateKeyMap[atSign]!
                  : aesKeyMap[atSign]!,
              iv: iv),
          'iv': ivB64,
        });
      });

      final response = AtEnrollmentResponse('123', EnrollmentStatus.pending)
        // ignore: deprecated_member_use_from_same_package
        ..atSign = atSign
        // ignore: deprecated_member_use_from_same_package
        ..rootDomain = const AtRootDomain('vip.ve.atsign.zone', 64)
        ..atAuthKeys = (AtKeys(atsign: atSign.toAtsign())
          ..apkamPublicKey = AtBytes.fromString(pkamPublicKeyMap[atSign]!)
          ..apkamPrivateKey = AtBytes.fromString(pkamPrivateKeyMap[atSign]!)
          ..defaultEncryptionPublicKey =
              AtBytes.fromString(encryptionPublicKeyMap[atSign]!)
          ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey));

      await AtEnrollmentImpl().waitForApproval(response,
          atLookup: mock, retryInterval: Duration.zero, logProgress: false);

      expect(commands, [
        'keys:get:keyName:123.default_enc_private_key.__manage$atSign\n',
        'keys:get:keyName:123.default_self_enc_key.__manage$atSign\n',
      ]);
    });
  });

  group('FROZEN: the otp verb commands', () {
    test('otp:get with the default 5-minute ttl', () async {
      final l = lookUp(response: 'data:ABC123');

      await AtEnrollmentImpl().generateOtp(l.lookUp);

      expect(l.commands.single, 'otp:get:ttl:300000\n');
    });

    test('otp:put carries the spp and ttl', () async {
      final l = lookUp(response: 'data:ok');

      await AtEnrollmentImpl().setSpp('ABC123', l.lookUp);

      expect(l.commands.single, 'otp:put:ABC123:ttl:300000\n');
    });
  });

  group('FROZEN: the _apsk signing-key advertisement', () {
    // What an enrollment publishes as its signing key, and what every verifier
    // parses. The atServer stores this map verbatim and writes its JSON
    // encoding to public:_apsk.<enrollmentId>.a.__e@<atSign> — it composes
    // nothing — so a change here changes the published record with no server
    // release to review it.
    test('the composed advertisement, as a raw literal', () {
      // The key is valid base64 because the kid's preimage is the DECODED
      // material now; a placeholder that is not base64 no longer has a kid.
      final json = jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.rsa2048, pub: 'AAEC')
      ]));

      expect(
          json,
          '{"v":1,"keys":[{"kid":"ae4b3280e56e2faf","use":"sign",'
          '"alg":"rsa2048","pub":"AAEC"}]}',
          reason: 'field names, field ORDER and the kid derivation are all '
              'wire contract; the kid is the first 16 hex chars of the '
              'SHA-256 of the key BYTES, so a changed prefix length or a '
              'switch back to hashing the base64 text shows up here');
    });

    test('the kid is the SHA-256 prefix of the key BYTES, one function', () {
      // Pinned against a digest computed outside this tree, so the assertion
      // cannot follow the implementation it is checking:
      //   python3 -c "import hashlib,base64;
      //     print(hashlib.sha256(base64.b64decode('AAEC')).hexdigest()[:16])"
      // 'AAEC' decodes to the three bytes 00 01 02.
      expect(publicKeyKidOfBase64('AAEC'), 'ae4b3280e56e2faf');
      expect(publicKeyKid(Uint8List.fromList([0x00, 0x01, 0x02])),
          'ae4b3280e56e2faf',
          reason: 'the base64 form is a convenience over the same preimage, '
              'not a second derivation');
    });

    test('mldsa65 spells its algorithm the same as the pkam verb', () {
      final entry = (apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.mldsa65, pub: 'AAEC')
      ])['keys'] as List)
          .single as Map;

      expect(entry['alg'], 'mldsa65');
      expect(entry['use'], 'sign');
    });

    test('what is composed is what is read back', () {
      final advertisement = apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.mldsa65, pub: 'AAEC')
      ]);

      final read = apskSigningKeys(advertisement).single;
      expect(read.alg, SigningAlgoType.mldsa65);
      expect(read.pub, 'AAEC');
      expect(read.kid, publicKeyKidOfBase64('AAEC'));
    });

    test('a composed entry says nothing about status, and reads as active',
        () {
      final advertisement = apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.mldsa65, pub: 'AAEC')
      ]);
      final entry = (advertisement['keys'] as List).single as Map;

      expect(entry.containsKey('status'), isFalse,
          reason: 'absent already reads as active, so emitting the default '
              'would change the bytes of every advertisement in the protocol '
              'to state what their silence states');
      expect(apskSigningKeys(advertisement).single.status,
          KeyEntryStatus.active);
    });

    test('several keys are several entries, in the order given', () {
      // The shape a signer publishes once it holds more than one algorithm:
      // one entry per key, listed strongest first, each with its own kid.
      // Nothing composed one until the composer took a list.
      final entries = (apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(alg: SigningAlgoType.mldsa65, pub: 'AAEC'),
        ApskSigningKey.forPublicKey(alg: SigningAlgoType.rsa2048, pub: 'CCEC'),
      ])['keys'] as List)
          .cast<Map>();

      expect(entries, hasLength(2));
      expect(entries.map((e) => e['alg']).toList(), ['mldsa65', 'rsa2048']);
      expect(entries.map((e) => e['pub']).toList(), ['AAEC', 'CCEC']);
      expect(entries[0]['kid'], publicKeyKidOfBase64('AAEC'));
      expect(entries[1]['kid'], publicKeyKidOfBase64('CCEC'),
          reason: 'each entry carries its OWN kid — one derivation reused for '
              'every entry would address the wrong key');
      expect(entries[0]['kid'], isNot(entries[1]['kid']));
    });

    test('only a retired key carries a status, and it round-trips', () {
      final advertisement = apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(alg: SigningAlgoType.mldsa65, pub: 'AAEC'),
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.rsa2048,
            pub: 'CCEC',
            status: KeyEntryStatus.retired),
      ]);
      final entries = (advertisement['keys'] as List).cast<Map>();

      expect(entries[0].containsKey('status'), isFalse);
      expect(entries[1]['status'], 'retired',
          reason: 'the field appears exactly when it has something to say, so '
              'an advertisement that has never rotated is byte-identical to '
              'what a build predating the field would have written');

      final read = apskSigningKeys(advertisement);
      expect(read.map((k) => k.status).toList(),
          [KeyEntryStatus.active, KeyEntryStatus.retired]);
      expect(read.map((k) => k.pub).toList(), ['AAEC', 'CCEC'],
          reason: 'a retired key is read back, not dropped: it is what '
              'verifies the envelopes it already signed');
    });

    test('a retired entry is KEPT, because it is what verifies old envelopes',
        () {
      final read = apskSigningKeys({
        'v': 1,
        'keys': [
          {
            'kid': 'k1',
            'use': 'sign',
            'alg': 'rsa2048',
            'pub': 'AAEC',
            'status': 'retired'
          },
          {'kid': 'k2', 'use': 'sign', 'alg': 'mldsa65', 'pub': 'BBEC'},
        ]
      });

      expect(read, hasLength(2),
          reason: 'dropping the retired entry would retroactively unverify '
              'every envelope this enrollment ever signed with it — the '
              'opposite of what retiring a key is for');
      expect(
          read.firstWhere((k) => k.kid == 'k1').status, KeyEntryStatus.retired);
      expect(
          read.firstWhere((k) => k.kid == 'k2').status, KeyEntryStatus.active);
      expect(read.firstWhere((k) => k.kid == 'k1').status, 'retired',
          reason: 'raw-literal: the atServer stores this document verbatim '
              'and every implementation reads these spellings');
    });

    test('an unrecognised status is read verbatim and written back verbatim',
        () {
      // A property of the reader/writer PAIR, and deliberately so: no caller
      // reads an `_apsk` record and republishes its entries today - every
      // `_apsk` writer composes from local key material - so this pins the
      // format rather than covering a live path. It is what stops a future
      // writer being wrong, and the live version of the same loss (rebuilding
      // a key package advertisement from the keyfile) is pinned in at_client's
      // key_package_minting_test.dart. Until 2026-08-22 the read collapsed to
      // `retired` and the write emitted `retired`.
      final read = apskSigningKeys({
        'v': 1,
        'keys': [
          {
            'kid': 'k1',
            'use': 'sign',
            'alg': 'rsa2048',
            'pub': 'AAEC',
            'status': 'revoked'
          },
        ]
      });

      expect(read.single.status, 'revoked');
      expect(read.single.offeredForNewOperations, isFalse,
          reason: 'a token this build does not know is never chosen to sign '
              'something new with');
      expect(read.single.vouchesForPastOperations, isFalse,
          reason: 'nor does it verify what it already signed - `retired` '
              'would have said it does, and a revoked key whose signatures '
              'go on checking out is the one outcome nothing recovers from');

      final rewritten =
          (apskAdvertisement(keys: read)['keys'] as List).cast<Map>();
      expect(rewritten.single['status'], 'revoked');
    });

    test('active and retired are the two statuses that verify the past', () {
      // The pair of decisions the field exists for. Retirement withdraws the
      // future and keeps the past; only `active` offers the future.
      expect(KeyEntryStatus.offersNewOperations(KeyEntryStatus.active), isTrue);
      expect(
          KeyEntryStatus.offersNewOperations(KeyEntryStatus.retired), isFalse);
      expect(KeyEntryStatus.vouchesForPastOperations(KeyEntryStatus.active),
          isTrue);
      expect(KeyEntryStatus.vouchesForPastOperations(KeyEntryStatus.retired),
          isTrue,
          reason: 'a retired signing key still verifies every envelope it '
              'signed, which is the whole reason its entry is kept');
      expect(KeyEntryStatus.known, {'active', 'retired'},
          reason: 'raw literals: these spellings are on records the atServer '
              'stores verbatim, so re-spelling one is a protocol change');
    });

    test('an entry with no kid is skipped, so a writer cannot omit it', () {
      // design.md 9.3's example omitted `kid` until 2026-08-13. A document
      // written from that example reads as empty and is then refused outright
      // — the right outcome, and a poor way to discover the typo.
      expect(
          apskSigningKeys({
            'v': 1,
            'keys': [
              {'use': 'sign', 'alg': 'mldsa65', 'pub': 'AAEC'}
            ]
          }),
          isEmpty);
    });

    test('an entry this build cannot use is skipped, not guessed at', () {
      final future = {
        'v': 1,
        'keys': [
          {'kid': 'k1', 'use': 'sign', 'alg': 'post2030', 'pub': 'AAEC'},
          {'kid': 'k2', 'use': 'kem', 'alg': 'mldsa65', 'pub': 'BBEC'},
          {'kid': 'k3', 'use': 'sign', 'alg': 'rsa2048', 'pub': 'CCEC'},
        ]
      };

      final read = apskSigningKeys(future);
      expect(read, hasLength(1),
          reason: 'an unknown algorithm and a non-signing use are both '
              'skipped, which is what lets an enrollment advertise a new '
              'algorithm beside an old one without breaking readers that '
              'predate it');
      expect(read.single.pub, 'CCEC');
    });

    test('an advertisement of nothing understood comes back empty', () {
      final read = apskSigningKeys({
        'v': 1,
        'keys': [
          {'kid': 'k1', 'use': 'sign', 'alg': 'post2030', 'pub': 'AAEC'}
        ]
      });

      expect(read, isEmpty,
          reason: 'the caller must refuse outright rather than fall back to a '
              'key derived some other way — a signature means something only '
              'if the verifier used the key the signer published');
    });
  });

  group('FROZEN: the enroll:update proof of possession', () {
    // The bytes an enrollment signs to prove it holds the private half of the
    // APKAM key it is asking to install. Every atServer implementation
    // assembles this same string from the request it received and verifies the
    // signature against it, and neither repository compiles against the other
    // — so the separator, the field order and the spellings are contract, and
    // a change here silently stops every rotation verifying anywhere.
    test('the signable, as a raw literal', () {
      expect(
          apkamPossessionSignable(
              enrollmentId: 'e-1',
              apkamPublicKey: 'PUBKEY',
              signingAlgo: 'mldsa65'),
          'e-1|PUBKEY|mldsa65');
    });

    test('an absent algorithm is the four literal characters "null"', () {
      // The atServer computes `request.signingAlgo ?? record.signingAlgo` and
      // string-interpolates the result, so an enrollment whose record names no
      // algorithm signs the word null. EnrollmentUpdateRequest never composes
      // that form — it requires an algorithm — but a second implementation
      // reading this contract has to know the server accepts it, because a
      // client that treats the absent case as an empty segment produces a
      // signature the server computes differently and rejects.
      const String? recordNamesNoAlgorithm = null;
      expect(
          apkamPossessionSignable(
              enrollmentId: 'e-1',
              apkamPublicKey: 'PUBKEY',
              signingAlgo: '$recordNamesNoAlgorithm'),
          'e-1|PUBKEY|null');
    });
  });

  group('FROZEN: keyfile tokens shared with the wire', () {
    test('KeyAlgorithmType tokens, as raw strings', () {
      // rsa2048 / mldsa65 / ecc_secp256r1 double as the pkam and
      // enroll-request signingAlgo wire values; xwing / mlkem1024 are the
      // deliberately-unhyphenated keyfile twins of the wire's 'x-wing' /
      // 'ml-kem-1024'. The field is an open String — unknown tokens must
      // round-trip — so these pins protect writers, never reject readers.
      expect(KeyAlgorithmType.known, {
        'aes256',
        'rsa2048',
        'ecc_secp256r1',
        'ed25519',
        'x25519',
        'mlkem768',
        'mlkem1024',
        'mldsa65',
        'xwing',
      });
    });

    test('the keyfile tokens and enum names are the SAME strings', () {
      // AtKeys.signingAlgorithmForEnrollment resolves keyfile tokens back to
      // SigningAlgoType by `.name` equality, and at_auth files material with
      // `signingAlgo.name` directly — renaming either side breaks every PQ
      // keyfile's ability to authenticate, with no compile error.
      expect(KeyAlgorithmType.mlDsa65, SigningAlgoType.mldsa65.name);
      expect(KeyAlgorithmType.rsa2048, SigningAlgoType.rsa2048.name);
      expect(KeyAlgorithmType.eccSecp256r1, SigningAlgoType.ecc_secp256r1.name);
    });

    test('CryptographicKeyType tokens and KeyPartStatus names', () {
      expect(CryptographicKeyType.known, {
        'symmetricEncryption',
        'symmetricAuthentication',
        'publicEncryption',
        'privateDecryption',
        'publicVerification',
        'privateSigning',
        'publicEncapsulation',
        'privateDecapsulation',
        'publicKeyAgreement',
        'privateKeyAgreement',
        'privateAuthentication',
        'publicAuthentication',
      });
      // The at-rest tokens, pinned individually as well as as a set. Asserting
      // only `known` would follow a renamed constant silently, which is the
      // failure a raw-literal pin exists to stop.
      expect(KeyPartStatus.active, 'active');
      expect(KeyPartStatus.retired, 'retired');
      expect(KeyPartStatus.dead, 'dead');
      expect(KeyPartStatus.known, {'active', 'retired', 'dead'});

      // And the forward order, which stopped being declaration index when
      // status became an open String. It is a stated ranking now, so it is
      // pinned like any other contract.
      expect(KeyPartStatus.rankOf('active'), 0);
      expect(KeyPartStatus.rankOf('retired'), 1);
      expect(KeyPartStatus.rankOf('dead'), 2);
      expect(KeyPartStatus.rankOf('pending'), isNull,
          reason: 'a token this build has never seen has no position in the '
              'forward order, and must not acquire one by accident');
    });

    test('the typed keyfile ids APKAM and signing material file under', () {
      // Pinned against the WRITERS, not against hand-built materials: a pin
      // that constructs the id it then asserts pins nothing, and the shape is
      // only frozen if the code that emits it is what produced the string.
      final atKeys = AtKeys(atsign: '@alice'.toAtsign());

      atKeys.fileApkamMaterial(
          enrollmentId: 'enroll-1',
          algorithm: KeyAlgorithmType.mlDsa65,
          publicKey: 'QUJD',
          privateKey: 'REVG');
      expect(atKeys.keysForKeyId('enroll-1', 'auth:mldsa65:1'), hasLength(2),
          reason: 'auth:<algorithm>:<generation> is the at-rest id for an '
              'enrollment authentication keypair. The enrollment is NOT in '
              'the id — the container states it once, so two enrollments may '
              'each hold this same id');

      atKeys.fileSigningMaterial(
          enrollmentId: 'enroll-1',
          algorithm: KeyAlgorithmType.mlDsa65,
          publicKey: 'R0hJ',
          privateKey: 'SktM');
      expect(atKeys.keysForKeyId('enroll-1', 'sign:mldsa65:1'), hasLength(2),
          reason: 'sign:<algorithm>:<generation> is the at-rest id for an '
              'enrollment signing keypair');

      expect(
          atKeys
              .getKey('enroll-1', 'auth:mldsa65:1',
                  CryptographicKeyType.privateAuthentication)!
              .toJson()['keyAlgorithmType'],
          'mldsa65');

      // The generation is per (role, algorithm): an enrollment moving from one
      // algorithm to another holds both at generation 1, and they must not
      // collide.
      atKeys.fileSigningMaterial(
          enrollmentId: 'enroll-1',
          algorithm: KeyAlgorithmType.rsa2048,
          publicKey: 'TU5P',
          privateKey: 'UFFS');
      expect(atKeys.keysForKeyId('enroll-1', 'sign:rsa2048:1'), hasLength(2),
          reason: 'a second algorithm starts at generation 1 of its own');
    });
  });
}
