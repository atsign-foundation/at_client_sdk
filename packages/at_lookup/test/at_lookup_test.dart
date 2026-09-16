// Constructs `AtLookupImpl` directly throughout, which is deprecated in
// favor of `AtLookUp.withSecureSocket` — see the constructor's own doc
// comment for why.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/at_connection.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_utils/at_logger.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

void main() {
  AtSignLogger.root_level = 'finest';
  late OutboundConnection mockOutBoundConnection;
  late SecondaryAddressFinder mockSecondaryAddressFinder;
  late OutboundMessageListener mockOutboundListener;
  late AtTransportFactory mockTransportFactory;
  late AtLookupMessageListenerFactory mockSecureSocketListenerFactory;
  late AtLookupOutboundConnectionFactory mockOutboundConnectionFactory;

  late FakeAtServerTransport transport;

  String atServerHost = '127.0.0.1';
  int atServerPort = 12345;

  setUp(() {
    mockOutBoundConnection = MockOutboundConnectionImpl();
    mockSecondaryAddressFinder = MockSecondaryAddressFinder();
    mockOutboundListener = MockOutboundMessageListener();
    mockTransportFactory = MockAtTransportFactory();
    mockSecureSocketListenerFactory = MockMessageListenerFactory();
    mockOutboundConnectionFactory = MockOutboundConnectionFactory();
    transport =
        FakeAtServerTransport(description: '$atServerHost:$atServerPort');

    when(() => mockSecondaryAddressFinder.findSecondary('@alice'))
        .thenAnswer((_) async {
      return SecondaryAddress(atServerHost, atServerPort);
    });
    when(() => mockTransportFactory.connect(atServerHost, '12345'))
        .thenAnswer((invocation) {
      return Future<AtTransport>.value(transport);
    });
    when(() =>
            mockOutboundConnectionFactory.createOutboundConnection(transport))
        .thenAnswer((invocation) {
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
      return Future.value();
    });
  });

  /// The challenge shape an atServer should emit for a client:
  /// `data:_<uuid><atSign>:<uuid>`.
  const fromChallenge = 'data:_03fe0ff2-ac50-4c80-8f43-88480beba888@alice'
      ':c3d345fc-5691-4f90-bc34-17cba31f060f';

  group('A connection records the identity it authenticated as', () {
    /// An authenticator that sends the from: challenge over the wire, then
    /// reports [succeeds] — standing in for whatever real signing at_auth
    /// would do.
    AtAuthenticator authenticatorAnswering(bool succeeds) {
      return (executor) async {
        await executor.sendSync('from:@alice\n');
        return succeeds;
      };
    }

    /// Wires the mocks for one from: exchange and hands back the metadata
    /// object the connection will carry, so a test can read what the
    /// authentication wrote onto it.
    OutboundConnectionMetadata primeConnection() {
      when(() => mockOutboundListener.read())
          .thenAnswer((_) => Future.value(fromChallenge));
      final metaData = OutboundConnectionMetadata()..isAuthenticated = false;
      when(() => mockOutBoundConnection.getMetaData()).thenReturn(metaData);
      when(() => mockOutBoundConnection.isInValid()).thenReturn(false);
      return metaData;
    }

    AtLookupImpl newAtLookup() => AtLookupImpl('@alice', atServerHost, 64,
        secondaryAddressFinder: mockSecondaryAddressFinder,
        transportFactory: mockTransportFactory,
        socketListenerFactory: mockSecureSocketListenerFactory,
        outboundConnectionFactory: mockOutboundConnectionFactory);

    test('pkam auth records the enrollment id it authenticated with', () async {
      const enrollmentIdFromServer = '5a21feb4-dc04-4603-829c-15f523789170';
      final metaData = primeConnection();
      final atLookup = newAtLookup()
        ..authenticator = authenticatorAnswering(true);
      final before = DateTime.now().toUtc();

      expect(
          await atLookup.pkamAuthenticate(
              enrollmentId: enrollmentIdFromServer),
          true);

      expect(metaData.authenticatedAsEnrollmentId, enrollmentIdFromServer,
          reason: 'the connection must carry the enrollment id it sent');
      expect(metaData.authenticatedAt, isNotNull,
          reason: 'an authenticated connection must be stamped with when');
      expect(metaData.authenticatedAt!.isBefore(before), false,
          reason: 'the stamp is this authentication, not an earlier one');
      expect(metaData.authenticatedAt!.isUtc, true);
    });

    test(
        'auth through executeCommand records no enrollment id, unlike '
        'pkamAuthenticate', () async {
      final metaData = primeConnection();
      when(() => mockOutBoundConnection.write(any()))
          .thenAnswer((_) => Future.value());
      var readCount = 0;
      when(() => mockOutboundListener.read()).thenAnswer((_) => Future.value(
          readCount++ == 0 ? fromChallenge : 'data:1234'));
      final atLookup = newAtLookup()
        ..authenticator = authenticatorAnswering(true);

      final result =
          await atLookup.executeCommand('llookup:phone@alice\n', auth: true);

      expect(result, 'data:1234');
      expect(metaData.authenticatedAsEnrollmentId, isNull,
          reason: 'a verb-level authentication runs an opaque authenticator '
              'that does not report which enrollment it signed as — the '
              'recorded identity is what went on the wire, and nothing did');
      expect(metaData.authenticatedAt, isNotNull);
    });

    test('a refused pkam auth records nothing', () async {
      final metaData = primeConnection();
      final atLookup = newAtLookup()
        ..authenticator = authenticatorAnswering(false);

      await expectLater(atLookup.pkamAuthenticate(),
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
          transportFactory: mockTransportFactory,
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
          transportFactory: mockTransportFactory,
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

    test('executeCommand -llookup verb - auth true', () async {
      final atLookup = AtLookupImpl('@alice', atServerHost, 64,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          transportFactory: mockTransportFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      final llookupCommand = 'llookup:phone@alice\n';
      final llookupResponse = 'data:1234';
      when(() => mockOutBoundConnection.write(llookupCommand))
          .thenAnswer((invocation) {
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
          transportFactory: mockTransportFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      final llookupCommand = 'llookup:phone@alice\n';
      final llookupResponse = 'error:AT0015-Exception: fubar';
      when(() => mockOutBoundConnection.write(llookupCommand))
          .thenAnswer((invocation) {
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
          transportFactory: mockTransportFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory);
      final llookupCommand = 'llookup:phone@alice\n';
      final llookupResponse =
          'error:{"errorCode":"AT0015","errorDescription":"Exception: fubar"}';
      when(() => mockOutBoundConnection.write(llookupCommand))
          .thenAnswer((invocation) {
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
          transportFactory: mockTransportFactory,
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
          transportFactory: mockTransportFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory)
        ..authenticator = (executor) async => true;

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
          transportFactory: mockTransportFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory)
        ..authenticator = (executor) async => true;
      String enrollmentId = '89213647826348';

      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.revoke
        ..enrollmentId = enrollmentId;
      String enrollCommand = 'enroll:revoke:{"enrollmentId":"$enrollmentId"}\n';
      String enrollResponse =
          'data:{"enrollmentId":"$enrollmentId","status":"revoked"}';

      when(() => mockOutBoundConnection.write(enrollCommand))
          .thenAnswer((invocation) {
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
          transportFactory: mockTransportFactory,
          socketListenerFactory: mockSecureSocketListenerFactory,
          outboundConnectionFactory: mockOutboundConnectionFactory)
        ..authenticator = (executor) async => true;
      String enrollmentId = '5754765754';

      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.deny
        ..enrollmentId = enrollmentId;
      String enrollCommand = 'enroll:deny:{"enrollmentId":"$enrollmentId"}\n';
      String enrollResponse =
          'data:{"enrollmentId":"$enrollmentId","status":"denied"}';

      when(() => mockOutBoundConnection.write(enrollCommand))
          .thenAnswer((invocation) {
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
