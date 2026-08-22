import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// Records what the authenticator sent, and with which budgets, and hands back
/// scripted atServer replies.
class RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];
  final List<int?> maxWaits = [];
  final List<int?> transientWaits = [];
  final List<String> replies;

  RecordingExecutor(this.replies);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    maxWaits.add(maxWaitMilliSeconds);
    transientWaits.add(transientWaitTimeMillis);
    return replies.removeAt(0);
  }
}

void main() {
  // The demo key maps are keyed on the emoji atSigns, so PKAM can sign for
  // real here rather than with placeholder material.
  const atSign = '@alice🛠';
  const challenge = '_9e8169dc-5618-44ec-ab43-1a5b2144c581@alice🛠'
      ':c3d345fc-5691-4f90-bc34-17cba31f060f';
  const cramSecret = 'cramsecret123';

  /// Captured with `shasum -a 512` over `cramsecret123` + the challenge, so
  /// the expectation does not come from the same code it is checking.
  const expectedCramDigest =
      'a6c61879f2bd17254e233a74578c9be0304e556d0517e5c0fdb1d6444047a041'
      '99fdba06b01c3765cfc2ca6a1d57124f5da58f05fea1f777a705814e2d54e766';

  /// Demo material, so the PKAM leg performs a real RSA signature rather than
  /// stopping short of the thing it exists to do.
  AtKeys signingKeys() => AtKeys()
    ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap[atSign]!)
    ..apkamPrivateKey = AtBytes.fromString(demo.pkamPrivateKeyMap[atSign]!)
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(demo.encryptionPublicKeyMap[atSign]!)
    ..defaultEncryptionPrivateKey =
        AtBytes.fromString(demo.encryptionPrivateKeyMap[atSign]!)
    ..defaultSelfEncryptionKey = AtBytes.fromString(demo.aesKeyMap[atSign]!);

  group('which credential applies', () {
    test('no keys yet means CRAM, and the digest is over secret+challenge',
        () async {
      final io = InMemoryAtKeysIo();
      final executor = RecordingExecutor(['data:$challenge', 'data:success']);

      final ok =
          await authenticatorFor(io, atSign, cramSecret: cramSecret)(executor);

      expect(ok, isTrue);
      expect(executor.sent.first, startsWith('from:$atSign'));
      expect(executor.sent.last, 'cram:$expectedCramDigest\n');
    });

    test('CRAM keeps at_lookup\'s tighter budgets', () async {
      final io = InMemoryAtKeysIo();
      final executor = RecordingExecutor(['data:$challenge', 'data:success']);

      await authenticatorFor(io, atSign, cramSecret: cramSecret)(executor);

      expect(executor.maxWaits, [10000, 10000],
          reason: 'a secret is accepted promptly or not at all, and this leg '
              'runs during onboarding where a slow failure is the worse one');
      expect(executor.transientWaits, [4000, 4000]);
    });

    test('keys present means PKAM, signed and sent', () async {
      final io = InMemoryAtKeysIo();
      await io.write(atSign, signingKeys());
      final executor = RecordingExecutor(['data:$challenge', 'data:success']);

      final ok = await authenticatorFor(io, atSign)(executor);

      expect(ok, isTrue);
      expect(executor.sent.first, startsWith('from:$atSign'));
      expect(executor.sent.last, startsWith('pkam:'));
      expect(executor.sent.last, contains('signingAlgo:rsa2048'),
          reason: 'a null algorithm resolves to the flat fields\' RSA keypair, '
              'which is what at_lookup signed with by default');
      expect(executor.maxWaits, [null, null],
          reason: 'PKAM takes the process-wide defaults, unlike CRAM');
    });

    test('ONE closure answers CRAM then PKAM as the keystore changes',
        () async {
      // The reason the closure re-reads the keystore instead of closing over
      // it. An instance that CRAM-onboards and then PKAM-authenticates is one
      // instance and two answers, and nothing tells it the phase changed.
      final io = InMemoryAtKeysIo();
      final authenticate = authenticatorFor(io, atSign, cramSecret: cramSecret);

      final first = RecordingExecutor(['data:$challenge', 'data:success']);
      expect(await authenticate(first), isTrue);
      expect(first.sent.last, startsWith('cram:'));

      // onboarding completes and the keys land
      await io.write(atSign, signingKeys());

      final second = RecordingExecutor(['data:$challenge', 'data:success']);
      expect(await authenticate(second), isTrue);
      expect(second.sent.last, startsWith('pkam:'),
          reason: 'the same closure must now choose PKAM, having re-read the '
              'keystore rather than remembered its first answer');
    });
  });

  group('an injected signer', () {
    test('is used, and the keyfile is asked only for the algorithm', () async {
      // Keys carrying NO apkam material at all. authenticationFor would throw
      // building a signer from them, so this passing is the proof that the
      // injected chops was used and the keyfile's own signer never built.
      final io = InMemoryAtKeysIo();
      await io.write(
          atSign,
          AtKeys()
            ..defaultEncryptionPublicKey =
                AtBytes.fromString(demo.encryptionPublicKeyMap[atSign]!));
      final executor = RecordingExecutor(['data:$challenge', 'data:success']);

      final injected = AtChopsImpl(AtChopsKeys.create(
          null,
          AtPkamKeyPair.create(demo.pkamPublicKeyMap[atSign]!,
              demo.pkamPrivateKeyMap[atSign]!)));

      final ok = await authenticatorFor(io, atSign, chops: injected)(executor);

      expect(ok, isTrue);
      expect(executor.sent.last, startsWith('pkam:'));
      expect(executor.sent.last, contains('signingAlgo:rsa2048'));
    });

    test('without one, the same keyfile cannot sign at all', () async {
      // The control for the test above: same keys, no injected signer. If this
      // also passed, the test above would prove nothing about which signer ran.
      final io = InMemoryAtKeysIo();
      await io.write(
          atSign,
          AtKeys()
            ..defaultEncryptionPublicKey =
                AtBytes.fromString(demo.encryptionPublicKeyMap[atSign]!));
      final executor = RecordingExecutor(['data:$challenge', 'data:success']);

      await expectLater(
          () => authenticatorFor(io, atSign)(executor), throwsA(anything));
    });
  });

  group('the legacy credential', () {
    // A caller holding nothing but a PKAM private key on a preference - which
    // is what at_lookup's ladder supported, and why deleting the ladder would
    // otherwise require every such caller to gain a keystore.
    test('authenticates with no keystore at all', () async {
      final executor = RecordingExecutor(['data:$challenge', 'data:success']);

      final ok = await authenticatorForPrivateKey(
          atSign, demo.pkamPrivateKeyMap[atSign]!)(executor);

      expect(ok, isTrue);
      expect(executor.sent.first, startsWith('from:$atSign'));
      expect(executor.sent.last, startsWith('pkam:'));
      expect(executor.sent.last, contains('signingAlgo:rsa2048'),
          reason: 'a keyless caller has no enrollment record to name an '
              'algorithm, and rsa2048 is what at_lookup signed with');
    });

    test('still refuses a challenge naming another atSign', () async {
      final executor = RecordingExecutor([
        'data:_9e8169dc-5618-44ec-ab43-1a5b2144c581@bob\u{1F6E0}'
            ':c3d345fc-5691-4f90-bc34-17cba31f060f'
      ]);

      await expectLater(
          () => authenticatorForPrivateKey(
              atSign, demo.pkamPrivateKeyMap[atSign]!)(executor),
          throwsA(predicate((dynamic e) =>
              e is UnAuthenticatedException &&
              e.message.contains('Refusing to sign a malformed from:'))));
      expect(executor.sent, hasLength(1),
          reason: 'it must refuse before sending any signature');
    });
  });

  group('a signer and nothing else', () {
    // The third shape the ladder supported, and the one every client in
    // tests/at_functional_test has: an AtChops, no keyfile, no private key.
    test('authenticates from an injected signer with no keystore', () async {
      final executor = RecordingExecutor(['data:$challenge', 'data:success']);
      final chops = AtChopsImpl(AtChopsKeys.create(
          null,
          AtPkamKeyPair.create(demo.pkamPublicKeyMap[atSign]!,
              demo.pkamPrivateKeyMap[atSign]!)));

      final ok = await authenticatorForChops(atSign, chops)(executor);

      expect(ok, isTrue);
      expect(executor.sent.last, startsWith('pkam:'));
      expect(executor.sent.last, contains('signingAlgo:rsa2048'));
    });

    test('and refuses a challenge naming another atSign', () async {
      final executor = RecordingExecutor([
        'data:_9e8169dc-5618-44ec-ab43-1a5b2144c581@bob\u{1F6E0}'
            ':c3d345fc-5691-4f90-bc34-17cba31f060f'
      ]);
      final chops = AtChopsImpl(AtChopsKeys.create(
          null,
          AtPkamKeyPair.create(demo.pkamPublicKeyMap[atSign]!,
              demo.pkamPrivateKeyMap[atSign]!)));

      await expectLater(() => authenticatorForChops(atSign, chops)(executor),
          throwsA(isA<UnAuthenticatedException>()));
      expect(executor.sent, hasLength(1));
    });
  });

  group('refusals', () {
    test('a challenge that does not name this atSign is refused', () async {
      final io = InMemoryAtKeysIo();
      await io.write(atSign, signingKeys());
      final executor = RecordingExecutor([
        'data:_9e8169dc-5618-44ec-ab43-1a5b2144c581@bob🛠'
            ':c3d345fc-5691-4f90-bc34-17cba31f060f'
      ]);

      await expectLater(
          () => authenticatorFor(io, atSign)(executor),
          throwsA(predicate((dynamic e) =>
              e is UnAuthenticatedException &&
              e.message.contains('Refusing to sign a malformed from:'))));
      expect(executor.sent, hasLength(1),
          reason: 'it must refuse before sending any signature');
    });

    test('no keys and no CRAM secret leaves nothing to authenticate with',
        () async {
      final io = InMemoryAtKeysIo();
      final executor = RecordingExecutor([]);

      await expectLater(
          () => authenticatorFor(io, atSign)(executor),
          throwsA(predicate((dynamic e) =>
              e is UnAuthenticatedException &&
              e.message.contains('no CRAM secret'))));
      expect(executor.sent, isEmpty);
    });

    test('a PKAM refusal from the atServer is raised, not returned', () async {
      final io = InMemoryAtKeysIo();
      await io.write(atSign, signingKeys());
      final executor = RecordingExecutor(
          ['data:$challenge', 'error:AT0401-Exception: auth failed']);

      await expectLater(() => authenticatorFor(io, atSign)(executor),
          throwsA(isA<UnAuthenticatedException>()));
    });
  });
}
