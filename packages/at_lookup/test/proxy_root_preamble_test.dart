import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// features/at_lookup/proxy_root_preamble.feature: a root domain of
/// `proxy:<host>` makes at_lookup send `from:<atSign>` first on every
/// connection, ahead of the caller's own `onConnect`.
void main() {
  late FakeAtServerTransportFactory transportFactory;
  late MockSecondaryAddressFinder addressFinder;

  setUp(() {
    transportFactory = FakeAtServerTransportFactory();
    addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress('127.0.0.1', 12345));
  });

  AtLookupMuxable lookUpAt(String rootDomain,
          {Future<void> Function(AtCommandExecutor connection)? onConnect}) =>
      AtLookUp.withTransport(
        atSign: '@alice',
        rootDomain: AtRootDomain(rootDomain, 443),
        authenticator: null,
        secondaryAddressFinder: addressFinder,
        transport: AtLookupTransport(transportFactory: transportFactory),
        onConnect: onConnect,
      );

  test('A proxy root sends from:<atSign> first on each connection', () async {
    final lookUp = lookUpAt('proxy:proxy.example.com');

    final command = lookUp.executeCommand('noop:0\n');
    await pumpEventQueue();
    final transport = transportFactory.created.single;
    await transport.settle();
    expect(transport.written, ['from:@alice\n'],
        reason: 'the preamble is first; the command waits behind it');

    await transport.serverSends('data:challenge\n@alice@');
    await transport.settle();
    expect(transport.written, ['from:@alice\n', 'noop:0\n']);
    await transport.serverSends('data:ok\n@alice@');
    expect(await command, 'data:ok');

    await lookUp.close();
  });

  test(
      'A replacement connection through a proxy root opens with '
      'from:<atSign> again', () async {
    final lookUp = lookUpAt('proxy:proxy.example.com');
    final first = lookUp.executeCommand('noop:0\n');
    await pumpEventQueue();
    final original = transportFactory.created.single;
    await original.serverSends('data:challenge\n@alice@');
    await original.serverSends('data:ok\n@alice@');
    await first;

    await original.serverCloses();
    final second = lookUp.executeCommand('noop:1\n');
    await pumpEventQueue();
    expect(transportFactory.created, hasLength(2));
    await transportFactory.last.settle();
    expect(transportFactory.last.written, ['from:@alice\n'],
        reason: 'the preamble goes out before the command');
    await transportFactory.last.serverSends('data:challenge\n@alice@');
    await transportFactory.last.settle();
    expect(transportFactory.last.written, ['from:@alice\n', 'noop:1\n']);
    await transportFactory.last.serverSends('data:ok\n@alice@');
    await second;

    await lookUp.close();
  });

  test("A proxy root's preamble runs before the caller's onConnect", () async {
    final order = <String>[];
    final lookUp = lookUpAt('proxy:proxy.example.com', onConnect: (c) async {
      order.add('caller');
      await c.sendSync('noop:own\n');
    });

    final command = lookUp.executeCommand('noop:0\n')..ignore();
    await pumpEventQueue();
    final transport = transportFactory.created.single;
    await transport.settle();
    expect(transport.written, ['from:@alice\n']);
    expect(order, isEmpty, reason: 'the caller waits for the preamble');

    await transport.serverSends('data:challenge\n@alice@');
    await transport.settle();
    expect(order, ['caller']);
    expect(transport.written, ['from:@alice\n', 'noop:own\n'],
        reason: "on the same connection, after the preamble's reply");

    await lookUp.close();
    await command.then((_) {}, onError: (_) {});
  });

  test('A root domain that is not a proxy sends no from:<atSign>', () async {
    final lookUp =
        lookUpAt('root.atsign.org', onConnect: (c) => c.sendSync('noop:own\n'));

    final command = lookUp.executeCommand('noop:0\n')..ignore();
    await pumpEventQueue();
    final transport = transportFactory.created.single;
    await transport.settle();
    expect(transport.written, ['noop:own\n'],
        reason: "only what the caller's onConnect wrote");

    await lookUp.close();
    await command.then((_) {}, onError: (_) {});
  });

  test(
      "A proxy root whose connection drops before the preamble's reply is "
      'retried on a new one', () async {
    final lookUp = lookUpAt('proxy:proxy.example.com');

    final first = expectLater(
        lookUp.executeCommand('noop:0\n'), throwsA(isA<Exception>()));
    await pumpEventQueue();
    final dropped = transportFactory.created.single;
    await dropped.settle();
    await dropped.serverCloses();
    await first;
    expect(dropped.written, ['from:@alice\n'],
        reason: 'the command was not written');
    expect(dropped.destroyed, isTrue);

    final second = lookUp.executeCommand('noop:1\n');
    await pumpEventQueue();
    expect(transportFactory.created, hasLength(2));
    await transportFactory.last.settle();
    expect(transportFactory.last.written, ['from:@alice\n']);
    await transportFactory.last.serverSends('data:challenge\n@alice@');
    await transportFactory.last.settle();
    expect(transportFactory.last.written, ['from:@alice\n', 'noop:1\n']);
    await transportFactory.last.serverSends('data:ok\n@alice@');
    await second;

    await lookUp.close();
  });

  test(
      "A proxy root's preamble that gets an error: reply closes the "
      'connection and fails the command', () async {
    final lookUp = lookUpAt('proxy:proxy.example.com');

    final command = expectLater(
        lookUp.executeCommand('noop:0\n'),
        throwsA(isA<AtLookUpException>()
            .having((e) => e.errorCode, 'errorCode', 'AT0015')));
    await pumpEventQueue();
    final refused = transportFactory.created.single;
    await refused.settle();
    await refused.serverSends('error:AT0015-unknown atSign\n@');
    await command;
    expect(refused.written, ['from:@alice\n'],
        reason: 'nothing is sent on a connection the proxy did not route');
    expect(refused.destroyed, isTrue);

    await lookUp.close();
  });

  test(
      "A proxy root's preamble that gets an error: reply fails executeVerb "
      "with the reply's code", () async {
    final lookUp = lookUpAt('proxy:proxy.example.com');

    final verb = expectLater(
        lookUp.executeVerb(LookupVerbBuilder()
          ..auth = false
          ..atKey = (AtKey()
            ..key = 'phone'
            ..sharedBy = '@bob')),
        throwsA(isA<AtLookUpException>()
            .having((e) => e.errorCode, 'errorCode', 'AT0007')
            .having((e) => e.cause, 'cause',
                isA<AtLookUpException>().having(
                    (e) => e.errorCode, 'errorCode', 'AT0007'))));
    await pumpEventQueue();
    final refused = transportFactory.created.single;
    await refused.settle();
    await refused.serverSends('error:AT0007-no atServer\n@');
    await verb;
    expect(refused.written, ['from:@alice\n'],
        reason: 'the verb is not sent on a connection the proxy refused');

    await lookUp.close();
  });
}
