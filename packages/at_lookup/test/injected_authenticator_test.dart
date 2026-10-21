import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';

/// The injected authenticator, which is the only PKAM credential path left:
/// the atChops/privateKey/cramSecret ladder it replaced is gone with
/// at_chops 4.0.0.
void main() {
  late OutboundConnection mockOutBoundConnection;
  late SecondaryAddressFinder mockSecondaryAddressFinder;
  late OutboundMessageListener mockOutboundListener;
  late AtLookupSecureSocketFactory mockSocketFactory;
  late AtLookupSecureSocketListenerFactory mockSecureSocketListenerFactory;
  late AtLookupOutboundConnectionFactory mockOutboundConnectionFactory;
  late SecureSocket mockSecureSocket;

  const host = '127.0.0.1';
  const port = 12345;
  const fromChallenge = 'data:_03fe0ff2-ac50-4c80-8f43-88480beba888@alice'
      ':c3d345fc-5691-4f90-bc34-17cba31f060f';

  /// Responses the fake atServer hands back, in order.
  late List<String> replies;

  setUp(() {
    mockOutBoundConnection = MockOutboundConnectionImpl();
    mockSecondaryAddressFinder = MockSecondaryAddressFinder();
    mockOutboundListener = MockOutboundMessageListener();
    mockSocketFactory = MockSecureSocketFactory();
    mockSecureSocketListenerFactory = MockSecureSocketListenerFactory();
    mockOutboundConnectionFactory = MockOutboundConnectionFactory();
    registerFallbackValue(SecureSocketConfig());
    mockSecureSocket = createMockAtServerSocket(host, port);

    when(() => mockSecondaryAddressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    when(() => mockSocketFactory.createSocket(host, '$port', any()))
        .thenAnswer((_) => Future<SecureSocket>.value(mockSecureSocket));
    when(() => mockOutboundConnectionFactory.createOutboundConnection(
        mockSecureSocket)).thenAnswer((_) => mockOutBoundConnection);
    when(() => mockSecureSocketListenerFactory.createListener(
        mockOutBoundConnection)).thenAnswer((_) => mockOutboundListener);
    when(() => mockOutBoundConnection.getMetaData())
        .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
    when(() => mockOutBoundConnection.isInValid()).thenReturn(false);
    when(() => mockOutBoundConnection.write(any()))
        .thenAnswer((_) => Future.value());

    replies = [];
    when(() => mockOutboundListener.read())
        .thenAnswer((_) => Future.value(replies.removeAt(0)));
  });

  AtLookupImpl build() => AtLookupImpl('@alice', host, 64,
      secondaryAddressFinder: mockSecondaryAddressFinder,
      secureSocketFactory: mockSocketFactory,
      socketListenerFactory: mockSecureSocketListenerFactory,
      outboundConnectionFactory: mockOutboundConnectionFactory);

  test('an injected authenticator runs and is recorded on the connection',
      () async {
    replies = [fromChallenge, 'data:success', 'data:[]'];
    final atLookup = build();

    var authenticatorCalls = 0;
    atLookup.authenticator = (executor) async {
      authenticatorCalls++;
      final challenge = await executor.sendSync('from:@alice\n');
      expect(challenge, fromChallenge,
          reason: 'sendSync must return what the atServer replied');
      await executor.sendSync('pkam:signature\n');
      return true;
    };

    final result = await atLookup.executeCommand('scan\n', auth: true);

    expect(authenticatorCalls, 1, reason: 'the authenticator must have run');
    expect(result, 'data:[]');
    expect(mockOutBoundConnection.getMetaData()!.isAuthenticated, isTrue,
        reason: 'a successful authenticator must be recorded on the '
            'connection');
  });

  test('an authenticator reporting failure raises UnAuthenticatedException',
      () async {
    replies = [fromChallenge];
    final atLookup = build();
    atLookup.authenticator = (executor) async {
      await executor.sendSync('from:@alice\n');
      return false;
    };

    await expectLater(
        () => atLookup.executeCommand('scan\n', auth: true),
        throwsA(predicate((dynamic e) =>
            e is UnAuthenticatedException &&
            e.message.contains('The authenticator reported failure'))));
    expect(mockOutBoundConnection.getMetaData()!.isAuthenticated, isFalse,
        reason: 'a failed authentication must not be recorded');
  });

  test('with no authenticator, no privateKey and no cramSecret, auth throws',
      () async {
    // The credential ladder this once fell back to (atChops, then
    // privateKey, then cramSecret) is gone for atChops: with none of the
    // three credentials set, there is nothing left to authenticate with.
    final atLookup = build();

    await expectLater(
        () => atLookup.executeCommand('scan\n', auth: true),
        throwsA(predicate((dynamic e) =>
            e is UnAuthenticatedException &&
            e.message.contains('No AtAuthenticator'))));
  });
}
