import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// The authenticator injected into a lookup.
void main() {
  late OutboundConnection mockOutBoundConnection;
  late SecondaryAddressFinder mockSecondaryAddressFinder;
  late OutboundMessageListener mockOutboundListener;
  late AtTransportFactory mockTransportFactory;
  late AtLookupMessageListenerFactory mockSecureSocketListenerFactory;
  late AtLookupOutboundConnectionFactory mockOutboundConnectionFactory;
  late FakeAtServerTransport transport;

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
    mockTransportFactory = MockAtTransportFactory();
    mockSecureSocketListenerFactory = MockMessageListenerFactory();
    mockOutboundConnectionFactory = MockOutboundConnectionFactory();
    transport = FakeAtServerTransport(description: '$host:$port');

    when(() => mockSecondaryAddressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    when(() => mockTransportFactory.connect(host, '$port'))
        .thenAnswer((_) => Future<AtTransport>.value(transport));
    when(() =>
            mockOutboundConnectionFactory.createOutboundConnection(transport))
        .thenAnswer((_) => mockOutBoundConnection);
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
      transportFactory: mockTransportFactory,
      socketListenerFactory: mockSecureSocketListenerFactory,
      outboundConnectionFactory: mockOutboundConnectionFactory);

  test('an injected authenticator runs and is recorded', () async {
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

  test(
      'when the connection closes between two of an authenticator\'s '
      'commands, then the second is sent on no other connection and nothing '
      'is recorded', () async {
    final second = MockOutboundConnectionImpl();
    final secondListener = MockOutboundMessageListener();
    final connections = [mockOutBoundConnection, second];
    when(() =>
            mockOutboundConnectionFactory.createOutboundConnection(transport))
        .thenAnswer((_) => connections.removeAt(0));
    when(() => mockSecureSocketListenerFactory.createListener(second))
        .thenAnswer((_) => secondListener);
    when(() => second.getMetaData())
        .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
    when(() => second.isInValid()).thenReturn(false);
    when(() => second.write(any())).thenAnswer((_) => Future.value());
    when(() => secondListener.read()).thenAnswer((_) async => 'data:success');
    var closed = false;
    when(() => mockOutBoundConnection.isInValid()).thenAnswer((_) => closed);
    when(() => mockOutBoundConnection.close()).thenAnswer((_) async {});
    replies = [fromChallenge];
    final atLookup = build();
    atLookup.authenticator = (executor) async {
      await executor.sendSync('from:@alice\n');
      closed = true;
      await executor.sendSync('pkam:signature\n');
      return true;
    };

    await expectLater(
        atLookup.pkamAuthenticate(),
        throwsA(isA<UnAuthenticatedException>().having((e) => e.message,
            'message', contains('closed before it finished'))));
    verifyNever(() => second.write(any()));
    expect(mockOutBoundConnection.getMetaData()!.isAuthenticated, isFalse);
    verify(() => mockOutBoundConnection.write('from:@alice\n')).called(1);
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
}
