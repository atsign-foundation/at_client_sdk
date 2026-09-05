import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'test_utils/mocks.dart';

void main() {
  AtLookupImpl mockAtLookUp = MockAtLookUpImpl();
  SecondaryAddressFinder mockSecondaryAddressFinder =
      MockSecondaryAddressFinder();
  SecondaryAddress fakeSecondaryAddress =
      SecondaryAddress('fake.secondary.address', 8010);
  String atsign = '@remoteSecondaryTest';
  AtClientPreference atClientPreference = AtClientPreference();

  group('tests to verify functionality of remote secondary', () {
    setUp(() {
      reset(mockSecondaryAddressFinder);
      reset(mockAtLookUp);
      when(() => mockSecondaryAddressFinder.findSecondary(atsign.toLowerCase()))
          .thenAnswer((_) async => fakeSecondaryAddress);
      AtClientManager.getInstance().secondaryAddressFinder =
          mockSecondaryAddressFinder;
    });

    test('test findSecondaryUrl', () async {
      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      String? address = await remoteSecondary.findSecondaryUrl();
      expect(address, isNotNull);
      expect(address, fakeSecondaryAddress.toString());
    });

    test('executeVerb using scan', () async {
      String fakeScanData = 'data:["key1:value1","key2:value2"]';
      ScanVerbBuilder scanVerbBuilder = ScanVerbBuilder();
      when(() => mockAtLookUp.executeVerb(scanVerbBuilder))
          .thenAnswer((_) async => fakeScanData);
      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      remoteSecondary.atLookUp = mockAtLookUp;

      String result = await remoteSecondary.executeVerb(scanVerbBuilder);
      expect(result, fakeScanData);
    });

    test('executeVerb throws exception', () async {
      ScanVerbBuilder scanVerbBuilder = ScanVerbBuilder();
      when(() => mockAtLookUp.executeVerb(scanVerbBuilder))
          .thenThrow('exception123');
      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      remoteSecondary.atLookUp = mockAtLookUp;

      expect(() async => await remoteSecondary.executeVerb(scanVerbBuilder),
          throwsA('exception123'));
    });

    test('executeAndParse using llookup', () async {
      String fakeLookupData = 'data:lookup data stub';
      LookupVerbBuilder lookupVerbBuilder = LookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'dummy_key'
          ..sharedBy = '@alice');
      when(() => mockAtLookUp.executeVerb(lookupVerbBuilder))
          .thenAnswer((_) async => fakeLookupData);
      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      remoteSecondary.atLookUp = mockAtLookUp;
      String result = await remoteSecondary.executeAndParse(lookupVerbBuilder);
      expect(result, 'lookup data stub');
    });
  });

  group('transport seam', () {
    setUp(() {
      reset(mockSecondaryAddressFinder);
      when(() => mockSecondaryAddressFinder.findSecondary(atsign.toLowerCase()))
          .thenAnswer((_) async => fakeSecondaryAddress);
      AtClientManager.getInstance().secondaryAddressFinder =
          mockSecondaryAddressFinder;
    });

    test('an injected transport reaches the lookup that is built', () {
      final socketFactory = _StubSecureSocketFactory();
      final listenerFactory = _StubSocketListenerFactory();
      final connectionFactory = _StubOutboundConnectionFactory();

      final remoteSecondary = RemoteSecondary(
        atsign,
        atClientPreference,
        transport: AtLookupTransport(
          secureSocketConfig: SecureSocketConfig(),
          socketFactory: socketFactory,
          listenerFactory: listenerFactory,
          connectionFactory: connectionFactory,
        ),
      );

      final atLookUp = remoteSecondary.atLookUp as AtLookupImpl;
      expect(atLookUp.socketFactory, same(socketFactory));
      expect(atLookUp.socketListenerFactory, same(listenerFactory));
      expect(atLookUp.outboundConnectionFactory, same(connectionFactory));
    });

    test('omitting it leaves the native transport in place', () {
      final remoteSecondary = RemoteSecondary(atsign, atClientPreference);

      final atLookUp = remoteSecondary.atLookUp as AtLookupImpl;
      expect(atLookUp.socketFactory, isNotNull);
      expect(atLookUp.socketListenerFactory, isNotNull);
      expect(atLookUp.outboundConnectionFactory, isNotNull);
      // Not the stubs — the real dart:io-backed factories.
      expect(atLookUp.socketFactory, isNot(isA<_StubSecureSocketFactory>()));
    });
  });

  group('credential ladder', () {
    // Lowercase, because AtUtils.fixAtSign lowercases and the challenge has to
    // name the atSign the authenticator was built with, byte for byte.
    const ladderAtSign = '@ladderatsign';
    const challenge = '_9e8169dc-5618-44ec-ab43-1a5b2144c581$ladderAtSign'
        ':c3d345fc-5691-4f90-bc34-17cba31f060f';

    AtClientPreference preferenceFor(
            {SigningAlgoType? signingAlgo,
            HashingAlgoType? hashingAlgo,
            String? cramSecret}) =>
        AtClientPreference()
          ..signingAlgoType = signingAlgo ?? SigningAlgoType.rsa2048
          ..hashingAlgoType = hashingAlgo ?? HashingAlgoType.sha256
          ..cramSecret = cramSecret;

    /// Runs the authenticator the constructor installed, so the test exercises
    /// the seam at_lookup will actually call rather than a private method.
    Future<bool> authenticate(
            RemoteSecondary rs, _RecordingExecutor executor) =>
        (rs.atLookUp as AtLookupImpl).authenticator!(executor);

    setUp(() {
      reset(mockSecondaryAddressFinder);
      when(() => mockSecondaryAddressFinder
              .findSecondary(ladderAtSign.toLowerCase()))
          .thenAnswer((_) async => fakeSecondaryAddress);
      AtClientManager.getInstance().secondaryAddressFinder =
          mockSecondaryAddressFinder;
    });

    test('atChops is the first rung, and carries the preference algorithms',
        () async {
      final executor = _RecordingExecutor(['data:$challenge', 'data:success']);
      final remoteSecondary = RemoteSecondary(
          ladderAtSign,
          preferenceFor(
              signingAlgo: SigningAlgoType.ecc_secp256r1,
              hashingAlgo: HashingAlgoType.sha512),
          atChops: _StubChops('sig-from-chops'),
          enrollmentId: 'abc123');

      expect(await authenticate(remoteSecondary, executor), isTrue);
      expect(executor.sent.first, startsWith('from:$ladderAtSign'));
      expect(
          executor.sent.last,
          'pkam:signingAlgo:ecc_secp256r1:hashingAlgo:sha512'
          ':enrollmentId:abc123:sig-from-chops\n');
    });

    test('a bare private key is the second rung, always rsa2048', () async {
      final executor = _RecordingExecutor(['data:$challenge', 'data:success']);
      final remoteSecondary = RemoteSecondary(
          ladderAtSign,
          // ecc on the preference, to prove the private-key rung ignores it:
          // a keyless caller has no enrollment record to name an algorithm.
          preferenceFor(signingAlgo: SigningAlgoType.ecc_secp256r1),
          privateKey: demo.pkamPrivateKeyMap['@alice🛠']!);

      expect(await authenticate(remoteSecondary, executor), isTrue);
      expect(executor.sent.last,
          startsWith('pkam:signingAlgo:rsa2048:hashingAlgo:sha256:'));
    });

    test('a CRAM secret is the third rung', () async {
      final executor = _RecordingExecutor(['data:$challenge', 'data:success']);
      final remoteSecondary = RemoteSecondary(
          ladderAtSign, preferenceFor(cramSecret: 'cramsecret123'));

      expect(await authenticate(remoteSecondary, executor), isTrue);
      expect(executor.sent.last, startsWith('cram:'));
    });

    test('no credential at all throws, naming atChops', () {
      final executor = _RecordingExecutor([]);
      final remoteSecondary = RemoteSecondary(ladderAtSign, preferenceFor());

      expect(
          () => authenticate(remoteSecondary, executor),
          throwsA(isA<UnAuthenticatedException>().having((e) => e.message,
              'message', contains('atChops object is not set'))));
    });

    test('a later atChops change reaches the next authentication', () async {
      final remoteSecondary = RemoteSecondary(ladderAtSign, preferenceFor(),
          privateKey: demo.pkamPrivateKeyMap['@alice🛠']!);

      final first = _RecordingExecutor(['data:$challenge', 'data:success']);
      expect(await authenticate(remoteSecondary, first), isTrue);
      expect(first.sent.last, isNot(contains('sig-set-later')));

      // The authenticator re-reads the field on every connect, so this is not
      // frozen at construction the way a captured closure would be.
      remoteSecondary.atChops = _StubChops('sig-set-later');

      final second = _RecordingExecutor(['data:$challenge', 'data:success']);
      expect(await authenticate(remoteSecondary, second), isTrue);
      expect(second.sent.last, endsWith(':sig-set-later\n'));
    });
  });
}

/// Records what the authenticator sent and hands back scripted atServer
/// replies. Same shape as at_auth's own authenticator tests use.
class _RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];
  final List<String> replies;

  _RecordingExecutor(this.replies);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return replies.removeAt(0);
  }
}

/// Signs with a fixed string, so a test can name the signature it expects
/// without depending on RSA output. Only [sign] is reached.
class _StubChops extends Mock implements AtChops {
  final String signature;

  _StubChops(this.signature);

  @override
  AtSigningResult sign(AtSigningInput signingInput) =>
      AtSigningResult()..result = signature;
}

/// The three stubs below exist only to be identity-compared. None of their
/// members are called, because the seam under test is construction-time
/// wiring, not connection behaviour.
class _StubSecureSocketFactory extends AtLookupSecureSocketFactory {}

class _StubSocketListenerFactory extends AtLookupSecureSocketListenerFactory {}

class _StubOutboundConnectionFactory
    extends AtLookupOutboundConnectionFactory {}
