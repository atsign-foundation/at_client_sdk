import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
// The socket seams are internal, so tests construct the impl directly.
import 'package:at_lookup/src/at_lookup_impl.dart';
import 'package:at_lookup/src/connection/at_lookup_socket_factories.dart';
import 'package:at_lookup/src/connection/at_connection.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_utils/at_logger.dart';

import 'at_lookup_test_utils.dart';

void main() {
  AtSignLogger.root_level = 'finest';
  late OutboundConnection mockOutBoundConnection;
  late SecondaryAddressFinder mockSecondaryAddressFinder;
  late OutboundMessageListener mockOutboundListener;
  late AtLookupSecureSocketFactory mockSocketFactory;
  late AtLookupSecureSocketListenerFactory mockSecureSocketListenerFactory;
  late AtLookupOutboundConnectionFactory mockOutboundConnectionFactory;

  late SecureSocket mockSecureSocket;

  String atServerHost = '127.0.0.1';
  int atServerPort = 12345;

  /// The base64 signature the atServer is told about. [FakeSignatureAlgo] returns
  /// its bytes and at_lookup base64-encodes them back onto the verb, so the
  /// expectations below are byte-exact against the 3.6.0 wire format.
  const pkamSignature =
      'MbNbIwCSxsHxm4CHyakSE2yLqjjtnmzpSLPcGG7h+4M/GQAiJkklQfd/x9z58CSJfuSW8baIms26SrnmuYePZURfp5oCqtwRpvt+l07Gnz8aYpXH0k5qBkSR34SBk4nb+hdAjsXXgfWWC56gROPMwpOEbuDS6esU7oku+a7Rdr10xrFlk1Tf2eRwPOMWyuKwOvLwSgyq/INAFRYav5RmLFiecQhPME6ssc1jW92wztylKBtuZT4rk8787b6Z9StxT4dPZzWjfV1+oYDLaqu2PcQS2ZthH+Wj8NgoogDxSP+R7BE1FOVJKnavpuQWeOqNWeUbKkSVP0B0DN6WopAdsg==';

  /// Stands in for a PKAM private key; the fake algorithm only records it.
  final pkamKey = Uint8List.fromList(utf8.encode('pkam-private-key'));

  /// The algorithm behind the most recent [atLookUp] call, so tests can inspect
  /// what it was asked to sign.
  late FakeSignatureAlgo fakeAlgo;

  /// An [AtLookUp] wired to the mock socket stack. Omit [pkamPrivateKey] for a
  /// CRAM-only instance, which is the state activation starts in.
  AtLookUp atLookUp({
    Uint8List? pkamPrivateKey,
    SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048,
    HashingAlgoType? hashingAlgoType = HashingAlgoType.sha256,
    String? enrollmentId,
  }) {
    fakeAlgo = FakeSignatureAlgo(
      signature: base64Decode(pkamSignature),
      signingAlgoType: signingAlgoType,
      hashingAlgoType: hashingAlgoType,
    );
    return AtLookupImpl(
      '@alice',
      atServerHost,
      64,
      signingAlgo: fakeAlgo,
      pkamPrivateKey: pkamPrivateKey,
      enrollmentId: enrollmentId,
      secondaryAddressFinder: mockSecondaryAddressFinder,
      secureSocketFactory: mockSocketFactory,
      socketListenerFactory: mockSecureSocketListenerFactory,
      outboundConnectionFactory: mockOutboundConnectionFactory,
    );
  }

  setUp(() {
    mockOutBoundConnection = MockOutboundConnectionImpl();
    mockSecondaryAddressFinder = MockSecondaryAddressFinder();
    mockOutboundListener = MockOutboundMessageListener();
    mockSocketFactory = MockSecureSocketFactory();
    mockSecureSocketListenerFactory = MockSecureSocketListenerFactory();
    mockOutboundConnectionFactory = MockOutboundConnectionFactory();
    registerFallbackValue(SecureSocketConfig());
    mockSecureSocket = createMockAtServerSocket(atServerHost, atServerPort);

    when(() => mockSecondaryAddressFinder.findSecondary('@alice'))
        .thenAnswer((_) async {
      return SecondaryAddress(atServerHost, atServerPort);
    });
    when(() => mockSocketFactory.createSocket(atServerHost, '12345', any()))
        .thenAnswer((invocation) {
      return Future<SecureSocket>.value(mockSecureSocket);
    });
    when(() => mockOutboundConnectionFactory
        .createOutboundConnection(mockSecureSocket)).thenAnswer((invocation) {
      print('Creating mock outbound connection');
      return mockOutBoundConnection;
    });
    when(() => mockSecureSocketListenerFactory
        .createListener(mockOutBoundConnection)).thenAnswer((invocation) {
      print('creating mock outbound listener');
      return mockOutboundListener;
    });
    when(() => mockOutBoundConnection.write('from:@alice\n'))
        .thenAnswer((invocation) {
      mockSecureSocket.write('from:@alice\n');
      return Future.value();
    });
  });

  group('A group of tests to verify atlookup pkam authentication', () {
    test('pkam auth without enrollmentId - auth success', () async {
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value('data:success'));

      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      when(() => mockOutBoundConnection.write(
              'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:$pkamSignature\n'))
          .thenAnswer((invocation) {
        mockSecureSocket.write(
            'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:$pkamSignature\n');
        return Future.value();
      });

      final result = await atLookUp(pkamPrivateKey: pkamKey).pkamAuthenticate();
      expect(result, true);
    });

    test('pkam auth without enrollmentId - auth failed', () async {
      when(() => mockOutboundListener.read()).thenAnswer((_) =>
          Future.value('error:AT0401-Exception: pkam authentication failed'));

      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      when(() => mockOutBoundConnection.write(
              'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:$pkamSignature\n'))
          .thenAnswer((invocation) {
        mockSecureSocket.write(
            'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:$pkamSignature\n');
        return Future.value();
      });

      expect(
          () async =>
              await atLookUp(pkamPrivateKey: pkamKey).pkamAuthenticate(),
          throwsA(predicate((e) => e is UnAuthenticatedException)));
    });

    test('pkam auth with enrollmentId - auth success', () async {
      final enrollmentIdFromServer = '5a21feb4-dc04-4603-829c-15f523789170';
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value('data:success'));

      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      when(() => mockOutBoundConnection.write(
              'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:enrollmentId:$enrollmentIdFromServer:$pkamSignature\n'))
          .thenAnswer((invocation) {
        mockSecureSocket.write(
            'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:enrollmentId:$enrollmentIdFromServer:$pkamSignature\n');
        return Future.value();
      });

      final result = await atLookUp(pkamPrivateKey: pkamKey)
          .pkamAuthenticate(enrollmentId: enrollmentIdFromServer);
      expect(result, true);
    });

    test('pkam auth with enrollmentId - auth failed', () async {
      final enrollmentIdFromServer = '5a21feb4-dc04-4603-829c-15f523789170';
      when(() => mockOutboundListener.read()).thenAnswer((_) =>
          Future.value('error:AT0401-Exception: pkam authentication failed'));

      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      when(() => mockOutBoundConnection.write(
              'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:enrollmentId:$enrollmentIdFromServer:$pkamSignature\n'))
          .thenAnswer((invocation) {
        mockSecureSocket.write(
            'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:enrollmentId:$enrollmentIdFromServer:$pkamSignature\n');
        return Future.value();
      });

      expect(
          () async => await atLookUp(pkamPrivateKey: pkamKey)
              .pkamAuthenticate(enrollmentId: enrollmentIdFromServer),
          throwsA(predicate((e) =>
              e is UnAuthenticatedException && e.message.contains('AT0401'))));
    });

    test('the constructor enrollmentId is used when none is passed', () async {
      final enrollmentIdFromCtor = 'ctor-enrollment-id';
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value('data:success'));
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);
      when(() => mockOutBoundConnection.write(
              'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:enrollmentId:$enrollmentIdFromCtor:$pkamSignature\n'))
          .thenAnswer((_) => Future.value());

      final result = await atLookUp(
        pkamPrivateKey: pkamKey,
        enrollmentId: enrollmentIdFromCtor,
      ).pkamAuthenticate();
      expect(result, true);
    });

    test('an algorithm hashing intrinsically omits the hashingAlgo token',
        () async {
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value('data:success'));
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);
      when(() => mockOutBoundConnection
              .write('pkam:signingAlgo:mldsa65:$pkamSignature\n'))
          .thenAnswer((_) => Future.value());

      final result = await atLookUp(
        pkamPrivateKey: pkamKey,
        signingAlgoType: SigningAlgoType.mldsa65,
        hashingAlgoType: null,
      ).pkamAuthenticate();

      expect(result, true);
      verifyNever(() =>
          mockOutBoundConnection.write(any(that: contains('hashingAlgo'))));
    });

    test('the from challenge is what gets signed, with the retained key',
        () async {
      final challenge =
          '_03fe0ff2-ac50-4c80-8f43-88480beba888@alice:c3d345fc-5691-4f90-bc34-17cba31f060f';
      var reads = 0;
      when(() => mockOutboundListener.read()).thenAnswer((_) =>
          Future.value(reads++ == 0 ? 'data:$challenge' : 'data:success'));
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);
      when(() => mockOutBoundConnection.write(
              'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:$pkamSignature\n'))
          .thenAnswer((_) => Future.value());

      await atLookUp(pkamPrivateKey: pkamKey).pkamAuthenticate();

      expect(utf8.decode(fakeAlgo.signedMessage!), challenge);
      expect(fakeAlgo.secretKeyUsed, pkamKey);
    });

    test('pkam auth with no private key throws before sending from', () async {
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      await expectLater(
          atLookUp().pkamAuthenticate(),
          throwsA(predicate((e) =>
              e is UnAuthenticatedException &&
              e.message.contains('pkamPrivateKey'))));
      verifyNever(() => mockOutBoundConnection.write(any()));
    });

    test('cram auth digests the secret and challenge with SHA-512', () async {
      final challenge = '_abc@alice:def';
      var reads = 0;
      when(() => mockOutboundListener.read(
              transientWaitTimeMillis: any(named: 'transientWaitTimeMillis'),
              maxWaitMilliSeconds: any(named: 'maxWaitMilliSeconds')))
          .thenAnswer((_) =>
              Future.value(reads++ == 0 ? 'data:$challenge' : 'data:success'));
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      final expectedDigest =
          SHA512HashingAlgo().hash(utf8.encode('secret$challenge'));
      when(() => mockOutBoundConnection.write('cram:$expectedDigest\n'))
          .thenAnswer((_) => Future.value());

      // CRAM needs no PKAM key — this is the state activation starts in.
      final result = await atLookUp().cramAuthenticate('secret');
      expect(result, true);
      verify(() => mockOutBoundConnection.write('cram:$expectedDigest\n'))
          .called(1);
    });
  });

  group('the shipped algorithm sets produce verifiable signatures', () {
    /// Drives a real handshake against the mock socket and returns the `pkam:`
    /// command that went out, so the signature in it can be verified for real.
    Future<String> pkamCommandFrom(
        AtLookUp Function() build, String challenge) async {
      var reads = 0;
      when(() => mockOutboundListener.read()).thenAnswer((_) =>
          Future.value(reads++ == 0 ? 'data:$challenge' : 'data:success'));
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      String? pkamCommand;
      when(() => mockOutBoundConnection.write(any()))
          .thenAnswer((invocation) async {
        final command = invocation.positionalArguments.first as String;
        if (command.startsWith('pkam:')) pkamCommand = command;
      });

      expect(await build().pkamAuthenticate(), true);
      return pkamCommand!;
    }

    test('the classical set signs with RSA the atServer could verify',
        () async {
      final rsa = RsaSigningAlgo();
      final (:publicKey, :secretKey) = await rsa.generateKeyPair();
      const challenge = '_abc@alice:def';

      final command = await pkamCommandFrom(
        () => AtLookupImpl(
          '@alice',
          atServerHost,
          64,
          signingAlgo: RsaSigningAlgo(),
          pkamPrivateKey: secretKey,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory,
        ),
        challenge,
      );

      const prefix = 'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:';
      expect(command, startsWith(prefix));
      expect(
          await rsa.verifyBytes(Uint8List.fromList(utf8.encode(challenge)),
              signature: base64Decode(command.replaceFirst(prefix, '').trim()),
              publicKey: publicKey),
          true,
          reason: 'the atServer must be able to verify what we sent');
    });

    test('the PQ set signs with ML-DSA-65 and omits the hashingAlgo token',
        () async {
      final mlDsa = MlDsa65PureDartAlgo();
      final (:publicKey, :secretKey) = await mlDsa.generateKeyPair();
      const challenge = '_ghi@alice:jkl';

      final command = await pkamCommandFrom(
        () => AtLookupImpl(
          '@alice',
          atServerHost,
          64,
          signingAlgo: MlDsa65PureDartAlgo(),
          pkamPrivateKey: secretKey,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory,
        ),
        challenge,
      );

      const prefix = 'pkam:signingAlgo:mldsa65:';
      expect(command, startsWith(prefix));
      expect(command, isNot(contains('hashingAlgo')));
      expect(
          await mlDsa.verifyBytes(Uint8List.fromList(utf8.encode(challenge)),
              signature: base64Decode(command.replaceFirst(prefix, '').trim()),
              publicKey: publicKey),
          true,
          reason: 'the atServer must be able to verify what we sent');
    });
  });

  group('A group of tests to verify executeCommand method', () {
    test('executeCommand - from verb - auth false', () async {
      final fromResponse =
          'data:_03fe0ff2-ac50-4c80-8f43-88480beba888@alice:c3d345fc-5691-4f90-bc34-17cba31f060f';
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(fromResponse));
      var result = await atLookUp().executeCommand('from:@alice\n');
      expect(result, fromResponse);
    });

    test('executeCommand - auth true - no PKAM key', () async {
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value('data:1234'));
      expect(
          () async => await atLookUp()
              .executeCommand('llookup:phone@alice\n', auth: true),
          throwsA(predicate((e) =>
              e is UnAuthenticatedException &&
              e.message.contains('no PKAM key'))));
    });

    test('executeCommand - auth true - authenticates before sending the verb',
        () async {
      final llookupCommand = 'llookup:phone@alice\n';
      final llookupResponse = 'data:1234';

      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);
      when(() => mockOutBoundConnection.write(any()))
          .thenAnswer((_) => Future.value());
      // The `from` challenge, the `pkam` result, then the verb's own response.
      final reads = ['data:_abc@alice:def', 'data:success', llookupResponse];
      var read = 0;
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(reads[read++]));

      final result = await atLookUp(pkamPrivateKey: pkamKey)
          .executeCommand(llookupCommand, auth: true);

      expect(result, llookupResponse);
      verify(() => mockOutBoundConnection.write(
              'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:$pkamSignature\n'))
          .called(1);
    });

    test('executeCommand - test non json error handling', () async {
      final llookupCommand = 'llookup:phone@alice\n';
      final llookupResponse = 'error:AT0015-Exception: fubar';
      when(() => mockOutBoundConnection.write(llookupCommand))
          .thenAnswer((invocation) {
        mockSecureSocket.write(llookupCommand);
        return Future.value();
      });
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(llookupResponse));
      await expectLater(
          atLookUp().executeCommand(llookupCommand),
          throwsA(predicate((e) =>
              e is AtLookUpException && e.errorMessage == 'Exception: fubar')));
    });

    test('executeCommand - test json error handling', () async {
      final llookupCommand = 'llookup:phone@alice\n';
      final llookupResponse =
          'error:{"errorCode":"AT0015","errorDescription":"Exception: fubar"}';
      when(() => mockOutBoundConnection.write(llookupCommand))
          .thenAnswer((invocation) {
        mockSecureSocket.write(llookupCommand);
        return Future.value();
      });
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(llookupResponse));
      await expectLater(
          atLookUp().executeCommand(llookupCommand),
          throwsA(predicate((e) =>
              e is AtLookUpException && e.errorMessage == 'Exception: fubar')));
    });
  });

  group('A group of tests to verify re-authentication on connection loss', () {
    test('a dropped connection is rebuilt and re-authenticated', () async {
      final llookupCommand = 'llookup:phone@alice\n';
      final metaData = OutboundConnectionMetadata()..isAuthenticated = false;
      var socketDropped = false;

      when(() => mockOutBoundConnection.getMetaData()).thenReturn(metaData);
      when(() => mockOutBoundConnection.isInValid())
          .thenAnswer((_) => socketDropped);
      when(() => mockOutBoundConnection.close()).thenAnswer((_) async {});
      when(() => mockOutBoundConnection.write(any()))
          .thenAnswer((_) => Future.value());
      // A freshly created connection is a live one.
      when(() => mockOutboundConnectionFactory
          .createOutboundConnection(mockSecureSocket)).thenAnswer((_) {
        socketDropped = false;
        return mockOutBoundConnection;
      });
      // Each round: the `from` challenge, the `pkam` result, the verb response.
      final reads = [
        'data:_abc@alice:def',
        'data:success',
        'data:1234',
        'data:_ghi@alice:jkl',
        'data:success',
        'data:5678',
      ];
      var read = 0;
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(reads[read++]));

      final lookup = atLookUp(pkamPrivateKey: pkamKey);

      expect(
          await lookup.executeCommand(llookupCommand, auth: true), 'data:1234');

      // The atServer, or an idle timeout, drops the socket.
      socketDropped = true;
      metaData.isAuthenticated = false;

      expect(
          await lookup.executeCommand(llookupCommand, auth: true), 'data:5678');
      verify(() => mockOutBoundConnection.write(
              'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:$pkamSignature\n'))
          .called(2);
    });
  });

  group('Validate executeVerb() behaviour', () {
    test('validate EnrollVerbHandler behaviour - request', () async {
      String appName = 'unit_test_1';
      String deviceName = 'test_device';
      String otp = 'ABCDEF';

      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.request
        ..appName = appName
        ..deviceName = deviceName
        ..otp = otp;
      String enrollCommand =
          'enroll:request:{"appName":"$appName","deviceName":"$deviceName","otp":"$otp"}\n';
      final enrollResponse =
          'data:{"enrollmentId":"1234567890","status":"pending"}';

      when(() => mockOutBoundConnection.write(enrollCommand))
          .thenAnswer((invocation) {
        mockSecureSocket.write(enrollCommand);
        return Future.value();
      });
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(enrollResponse));
      AtConnectionMetaData? atConnectionMetaData = OutboundConnectionMetadata()
        ..isAuthenticated = false;
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(atConnectionMetaData);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      // `enroll:request` is the one enroll operation that needs no auth.
      var result = await atLookUp().executeVerb(enrollVerbBuilder);
      expect(result, enrollResponse);
    });

    test('validate behaviour with EnrollVerbHandler - approve', () async {
      String appName = 'unit_test_2';
      String deviceName = 'test_device';
      String enrollmentId = '1357913579';

      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.approve
        ..enrollmentId = '1357913579'
        ..appName = appName
        ..deviceName = deviceName;
      String enrollCommand =
          'enroll:approve:{"enrollmentId":"$enrollmentId","appName":"$appName","deviceName":"$deviceName"}\n';
      final enrollResponse =
          'data:{"enrollmentId":"1357913579","status":"approved"}';

      when(() => mockOutBoundConnection.write(any()))
          .thenAnswer((_) => Future.value());
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(enrollResponse));
      // Already authenticated, so _process only has to create the connection.
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = true);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      expect(
          await atLookUp(pkamPrivateKey: pkamKey)
              .executeVerb(enrollVerbBuilder),
          enrollResponse);
      verify(() => mockOutBoundConnection.write(enrollCommand)).called(1);
    });

    test('validate behaviour with EnrollVerbHandler - revoke', () async {
      String enrollmentId = '89213647826348';

      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.revoke
        ..enrollmentId = enrollmentId;
      String enrollCommand = 'enroll:revoke:{"enrollmentId":"$enrollmentId"}\n';
      String enrollResponse =
          'data:{"enrollmentId":"$enrollmentId","status":"revoked"}';

      when(() => mockOutBoundConnection.write(any()))
          .thenAnswer((_) => Future.value());
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(enrollResponse));
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = true);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      expect(
          await atLookUp(pkamPrivateKey: pkamKey)
              .executeVerb(enrollVerbBuilder),
          enrollResponse);
      verify(() => mockOutBoundConnection.write(enrollCommand)).called(1);
    });

    test('validate behaviour with EnrollVerbHandler - deny', () async {
      String enrollmentId = '5754765754';

      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.deny
        ..enrollmentId = enrollmentId;
      String enrollCommand = 'enroll:deny:{"enrollmentId":"$enrollmentId"}\n';
      String enrollResponse =
          'data:{"enrollmentId":"$enrollmentId","status":"denied"}';

      when(() => mockOutBoundConnection.write(any()))
          .thenAnswer((_) => Future.value());
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(enrollResponse));
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(OutboundConnectionMetadata()..isAuthenticated = true);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      expect(
          await atLookUp(pkamPrivateKey: pkamKey)
              .executeVerb(enrollVerbBuilder),
          enrollResponse);
      verify(() => mockOutBoundConnection.write(enrollCommand)).called(1);
    });
  });
}
