// These tests exercise the atChops credential ladder itself, so they are
// written in the vocabulary at_chops has deprecated (AtChops, AtSigningInput,
// AtSigningResult). They go when the ladder does.
// TODO(4.0): remove with the credential ladder.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/at_connection.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_utils/at_logger.dart';

import 'at_lookup_test_utils.dart';

class FakeAtSigningInput extends Fake implements AtSigningInput {}

void main() {
  AtSignLogger.root_level = 'finest';
  late OutboundConnection mockOutBoundConnection;
  late SecondaryAddressFinder mockSecondaryAddressFinder;
  late OutboundMessageListener mockOutboundListener;
  late AtLookupSecureSocketFactory mockSocketFactory;
  late AtLookupSecureSocketListenerFactory mockSecureSocketListenerFactory;
  late AtLookupOutboundConnectionFactory mockOutboundConnectionFactory;

  late AtChops mockAtChops;
  late SecureSocket mockSecureSocket;

  String atServerHost = '127.0.0.1';
  int atServerPort = 12345;

  setUp(() {
    mockOutBoundConnection = MockOutboundConnectionImpl();
    mockSecondaryAddressFinder = MockSecondaryAddressFinder();
    mockOutboundListener = MockOutboundMessageListener();
    mockSocketFactory = MockSecureSocketFactory();
    mockSecureSocketListenerFactory = MockSecureSocketListenerFactory();
    mockOutboundConnectionFactory = MockOutboundConnectionFactory();
    mockAtChops = MockAtChops();
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

  /// The challenge shape an atServer should emit for a client:
  /// `data:_<uuid><atSign>:<uuid>`.
  const fromChallenge = 'data:_03fe0ff2-ac50-4c80-8f43-88480beba888@alice'
      ':c3d345fc-5691-4f90-bc34-17cba31f060f';

  group('A group of tests to verify atlookup pkam authentication', () {
    test('pkam auth without enrollmentId - auth success', () async {
      final pkamSignature =
          'MbNbIwCSxsHxm4CHyakSE2yLqjjtnmzpSLPcGG7h+4M/GQAiJkklQfd/x9z58CSJfuSW8baIms26SrnmuYePZURfp5oCqtwRpvt+l07Gnz8aYpXH0k5qBkSR34SBk4nb+hdAjsXXgfWWC56gROPMwpOEbuDS6esU7oku+a7Rdr10xrFlk1Tf2eRwPOMWyuKwOvLwSgyq/INAFRYav5RmLFiecQhPME6ssc1jW92wztylKBtuZT4rk8787b6Z9StxT4dPZzWjfV1+oYDLaqu2PcQS2ZthH+Wj8NgoogDxSP+R7BE1FOVJKnavpuQWeOqNWeUbKkSVP0B0DN6WopAdsg==';

      AtSigningResult mockSigningResult = AtSigningResult()
        ..result = 'mock_signing_result';
      registerFallbackValue(FakeAtSigningInput());
      when(() => mockAtChops.sign(any())).thenAnswer((_) => mockSigningResult);

      when(() => mockAtChops.sign(any()))
          .thenReturn(AtSigningResult()..result = pkamSignature);
      // The from: response first, then the pkam result.
      var readCount = 0;
      when(() => mockOutboundListener.read()).thenAnswer((_) =>
          Future.value(readCount++ == 0 ? fromChallenge : 'data:success'));

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

      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
      var result = await atLookup.pkamAuthenticate();
      expect(result, true);
    });

    test('pkam auth without enrollmentId - auth failed', () async {
      final pkamSignature =
          'MbNbIwCSxsHxm4CHyakSE2yLqjjtnmzpSLPcGG7h+4M/GQAiJkklQfd/x9z58CSJfuSW8baIms26SrnmuYePZURfp5oCqtwRpvt+l07Gnz8aYpXH0k5qBkSR34SBk4nb+hdAjsXXgfWWC56gROPMwpOEbuDS6esU7oku+a7Rdr10xrFlk1Tf2eRwPOMWyuKwOvLwSgyq/INAFRYav5RmLFiecQhPME6ssc1jW92wztylKBtuZT4rk8787b6Z9StxT4dPZzWjfV1+oYDLaqu2PcQS2ZthH+Wj8NgoogDxSP+R7BE1FOVJKnavpuQWeOqNWeUbKkSVP0B0DN6WopAdsg==';

      AtSigningResult mockSigningResult = AtSigningResult()
        ..result = 'mock_signing_result';
      registerFallbackValue(FakeAtSigningInput());
      when(() => mockAtChops.sign(any())).thenAnswer((_) => mockSigningResult);

      when(() => mockAtChops.sign(any()))
          .thenReturn(AtSigningResult()..result = pkamSignature);
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

      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
      expect(() async => await atLookup.pkamAuthenticate(),
          throwsA(predicate((e) => e is UnAuthenticatedException)));
    });

    test('pkam auth with enrollmentId - auth success', () async {
      final pkamSignature =
          'MbNbIwCSxsHxm4CHyakSE2yLqjjtnmzpSLPcGG7h+4M/GQAiJkklQfd/x9z58CSJfuSW8baIms26SrnmuYePZURfp5oCqtwRpvt+l07Gnz8aYpXH0k5qBkSR34SBk4nb+hdAjsXXgfWWC56gROPMwpOEbuDS6esU7oku+a7Rdr10xrFlk1Tf2eRwPOMWyuKwOvLwSgyq/INAFRYav5RmLFiecQhPME6ssc1jW92wztylKBtuZT4rk8787b6Z9StxT4dPZzWjfV1+oYDLaqu2PcQS2ZthH+Wj8NgoogDxSP+R7BE1FOVJKnavpuQWeOqNWeUbKkSVP0B0DN6WopAdsg==';
      final enrollmentIdFromServer = '5a21feb4-dc04-4603-829c-15f523789170';
      AtSigningResult mockSigningResult = AtSigningResult()
        ..result = 'mock_signing_result';
      registerFallbackValue(FakeAtSigningInput());
      when(() => mockAtChops.sign(any())).thenAnswer((_) => mockSigningResult);

      when(() => mockAtChops.sign(any()))
          .thenReturn(AtSigningResult()..result = pkamSignature);
      // The from: response first, then the pkam result.
      var readCount = 0;
      when(() => mockOutboundListener.read()).thenAnswer((_) =>
          Future.value(readCount++ == 0 ? fromChallenge : 'data:success'));

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

      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
      var result =
          await atLookup.pkamAuthenticate(enrollmentId: enrollmentIdFromServer);
      expect(result, true);
    });

    test('pkam auth with enrollmentId - auth failed', () async {
      final pkamSignature =
          'MbNbIwCSxsHxm4CHyakSE2yLqjjtnmzpSLPcGG7h+4M/GQAiJkklQfd/x9z58CSJfuSW8baIms26SrnmuYePZURfp5oCqtwRpvt+l07Gnz8aYpXH0k5qBkSR34SBk4nb+hdAjsXXgfWWC56gROPMwpOEbuDS6esU7oku+a7Rdr10xrFlk1Tf2eRwPOMWyuKwOvLwSgyq/INAFRYav5RmLFiecQhPME6ssc1jW92wztylKBtuZT4rk8787b6Z9StxT4dPZzWjfV1+oYDLaqu2PcQS2ZthH+Wj8NgoogDxSP+R7BE1FOVJKnavpuQWeOqNWeUbKkSVP0B0DN6WopAdsg==';
      final enrollmentIdFromServer = '5a21feb4-dc04-4603-829c-15f523789170';
      AtSigningResult mockSigningResult = AtSigningResult()
        ..result = 'mock_signing_result';
      registerFallbackValue(FakeAtSigningInput());
      when(() => mockAtChops.sign(any())).thenAnswer((_) => mockSigningResult);

      when(() => mockAtChops.sign(any()))
          .thenReturn(AtSigningResult()..result = pkamSignature);
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

      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
      expect(
          () async => await atLookup.pkamAuthenticate(
              enrollmentId: enrollmentIdFromServer),
          throwsA(predicate((e) =>
              e is UnAuthenticatedException && e.message.contains('AT0401'))));
    });
  });

  group('A connection records the identity it authenticated as', () {
    const pkamSignature = 'a-signature';

    /// Wires the mocks for one PKAM exchange and hands back the metadata
    /// object the connection will carry, so a test can read what the
    /// authentication wrote onto it.
    OutboundConnectionMetadata primePkam(
        {String? enrollmentId, bool succeeds = true}) {
      registerFallbackValue(FakeAtSigningInput());
      when(() => mockAtChops.sign(any()))
          .thenReturn(AtSigningResult()..result = pkamSignature);
      var readCount = 0;
      when(() => mockOutboundListener.read()).thenAnswer((_) => Future.value(
          readCount++ == 0
              ? fromChallenge
              : (succeeds
                  ? 'data:success'
                  : 'error:AT0401-Exception: pkam authentication failed')));

      final metaData = OutboundConnectionMetadata()..isAuthenticated = false;
      when(() => mockOutBoundConnection.getMetaData()).thenReturn(metaData);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      final enrollmentClause =
          enrollmentId == null ? '' : 'enrollmentId:$enrollmentId:';
      final command = 'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:'
          '$enrollmentClause$pkamSignature\n';
      when(() => mockOutBoundConnection.write(command))
          .thenAnswer((invocation) {
        mockSecureSocket.write(command);
        return Future.value();
      });
      return metaData;
    }

    AtLookupImpl newAtLookup() {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
      return atLookup;
    }

    test('pkam auth records the enrollment id it authenticated with', () async {
      const enrollmentIdFromServer = '5a21feb4-dc04-4603-829c-15f523789170';
      final metaData = primePkam(enrollmentId: enrollmentIdFromServer);
      final before = DateTime.now().toUtc();

      expect(
          await newAtLookup()
              .pkamAuthenticate(enrollmentId: enrollmentIdFromServer),
          true);

      expect(metaData.authenticatedAsEnrollmentId, enrollmentIdFromServer,
          reason: 'the connection must carry the enrollment id it sent');
      expect(metaData.authenticatedAt, isNotNull,
          reason: 'an authenticated connection must be stamped with when');
      expect(metaData.authenticatedAt!.isBefore(before), false,
          reason: 'the stamp is this authentication, not an earlier one');
      expect(metaData.authenticatedAt!.isUtc, true);
    });

    test('pkam auth with no enrollment id records none, not the field',
        () async {
      final metaData = primePkam();
      final atLookup = newAtLookup()
        // What the NEXT authentication would use. This one is being handed
        // nothing, and sends nothing, so it must record nothing.
        ..enrollmentId = 'f0c5e2b0-0000-4000-8000-000000000001';

      expect(await atLookup.pkamAuthenticate(), true);

      expect(metaData.authenticatedAsEnrollmentId, isNull,
          reason: 'the recorded identity is what went on the wire, '
              'not what AtLookUp.enrollmentId holds');
      expect(metaData.authenticatedAt, isNotNull);
    });

    test('a refused pkam auth records nothing', () async {
      final metaData = primePkam(succeeds: false);

      await expectLater(newAtLookup().pkamAuthenticate(),
          throwsA(isA<UnAuthenticatedException>()));

      expect(metaData.isAuthenticated, false,
          reason: 'nothing may be recorded until the atServer accepts');
      expect(metaData.authenticatedAsEnrollmentId, isNull,
          reason: 'a refusal must leave the connection unidentified');
      expect(metaData.authenticatedAt, isNull);
    });
  });

  group('A group of tests to verify executeCommand method', () {
    test('executeCommand - from verb - auth false', () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      final fromResponse =
          'data:_03fe0ff2-ac50-4c80-8f43-88480beba888@alice:c3d345fc-5691-4f90-bc34-17cba31f060f';
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(fromResponse));
      var result = await atLookup.executeCommand('from:@alice\n');
      expect(result, fromResponse);
    });

    test('executeCommand -llookup verb - auth true - auth key not set',
        () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      final fromResponse = 'data:1234';
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(fromResponse));
      expect(
          () async => await atLookup.executeCommand('llookup:phone@alice\n',
              auth: true),
          throwsA(predicate((e) => e is UnAuthenticatedException)));
    });

    test('executeCommand -llookup verb - auth true - at_chops set', () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
      final llookupCommand = 'llookup:phone@alice\n';
      final llookupResponse = 'data:1234';
      when(() => mockOutBoundConnection.write(llookupCommand))
          .thenAnswer((invocation) {
        mockSecureSocket.write(llookupCommand);
        return Future.value();
      });
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(llookupResponse));
      var result = await atLookup.executeCommand(llookupCommand);
      expect(result, llookupResponse);
    });

    test('executeCommand - test non json error handling', () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
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
          atLookup.executeCommand(llookupCommand),
          throwsA(predicate((e) =>
              e is AtLookUpException && e.errorMessage == 'Exception: fubar')));
    });

    test('executeCommand - test json error handling', () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
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
          atLookup.executeCommand(llookupCommand),
          throwsA(predicate((e) =>
              e is AtLookUpException && e.errorMessage == 'Exception: fubar')));
    });
  });

  group('Validate executeVerb() behaviour', () {
    test('validate EnrollVerbHandler behaviour - request', () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);

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

      var result = await atLookup.executeVerb(enrollVerbBuilder);
      expect(result, enrollResponse);
    });

    test('validate behaviour with EnrollVerbHandler - approve', () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;

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

      when(() => mockOutBoundConnection.write(enrollCommand))
          .thenAnswer((invocation) {
        mockSecureSocket.write(enrollCommand);
        return Future.value();
      });
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(enrollResponse));
      AtConnectionMetaData? atConnectionMetaData = OutboundConnectionMetadata()
        ..isAuthenticated = true;
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(atConnectionMetaData);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      expect(await atLookup.executeVerb(enrollVerbBuilder), enrollResponse);
    });

    test('validate behaviour with EnrollVerbHandler - revoke', () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
      String enrollmentId = '89213647826348';

      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.revoke
        ..enrollmentId = enrollmentId;
      String enrollCommand = 'enroll:revoke:{"enrollmentId":"$enrollmentId"}\n';
      String enrollResponse =
          'data:{"enrollmentId":"$enrollmentId","status":"revoked"}';

      when(() => mockOutBoundConnection.write(enrollCommand))
          .thenAnswer((invocation) {
        mockSecureSocket.write(enrollCommand);
        return Future.value();
      });
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(enrollResponse));
      AtConnectionMetaData? atConnectionMetaData = OutboundConnectionMetadata()
        ..isAuthenticated = true;
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(atConnectionMetaData);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      expect(await atLookup.executeVerb(enrollVerbBuilder), enrollResponse);
    });

    test('validate behaviour with EnrollVerbHandler - deny', () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          secureSocketFactory: mockSocketFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      atLookup.atChops = mockAtChops;
      String enrollmentId = '5754765754';

      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.deny
        ..enrollmentId = enrollmentId;
      String enrollCommand = 'enroll:deny:{"enrollmentId":"$enrollmentId"}\n';
      String enrollResponse =
          'data:{"enrollmentId":"$enrollmentId","status":"denied"}';

      when(() => mockOutBoundConnection.write(enrollCommand))
          .thenAnswer((invocation) {
        mockSecureSocket.write(enrollCommand);
        return Future.value();
      });
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(enrollResponse));
      AtConnectionMetaData? atConnectionMetaData = OutboundConnectionMetadata()
        ..isAuthenticated = true;
      when(() => mockOutBoundConnection.getMetaData())
          .thenReturn(atConnectionMetaData);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);

      expect(await atLookup.executeVerb(enrollVerbBuilder), enrollResponse);
    });
  });
}
