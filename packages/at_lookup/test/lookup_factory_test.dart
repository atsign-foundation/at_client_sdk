import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

/// `AtLookUpFactory` and its default, and the connect-time preamble a proxy
/// deployment needs: `onConnect` runs once per connection, before anything
/// else goes out on it.
void main() {
  const host = '127.0.0.1';
  const port = 12345;
  late FakeAtServerTransportFactory transportFactory;
  late MockSecondaryAddressFinder addressFinder;

  setUp(() {
    transportFactory = FakeAtServerTransportFactory();
    addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
  });

  test('the default factory builds through withSecureSocket, carrying the '
      'authenticator and the preamble', () {
    Future<bool> authenticator(AtCommandExecutor _) async => true;
    Future<void> preamble(AtCommandExecutor _) async {}
    final lookUps = secureSocketLookUps(onConnect: preamble);

    final lookUp = lookUps(
        atSign: '@alice',
        rootDomain: const AtRootDomain(host, 64),
        authenticator: authenticator);

    expect(lookUp, isA<AtLookupImpl>());
    expect((lookUp as AtLookupImpl).authenticator, same(authenticator));
    expect(lookUp.onConnect, same(preamble));
  });

  test('onConnect runs once per connection, before the first command, and '
      'again on a reconnect', () async {
    final preambleAnswers = <String>[];
    final lookUp = AtLookUp.withSecureSocket(
      atSign: '@alice',
      rootDomain: const AtRootDomain(host, 64),
      authenticator: null,
      secondaryAddressFinder: addressFinder,
      transport: AtLookupTransportFactories(transportFactory: transportFactory),
      onConnect: (connection) async {
        preambleAnswers.add(await connection.sendSync('from:@alice\n'));
      },
    );

    final first = lookUp.executeCommand('noop:0\n');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await transportFactory.created.single.settle();
    expect(transportFactory.created.single.written, ['from:@alice\n'],
        reason: 'the preamble is the first thing on the wire; the command '
            'waits behind it');

    await transportFactory.created.single.serverSends('data:challenge\n@alice@');
    await transportFactory.created.single.settle();
    expect(transportFactory.created.single.written,
        ['from:@alice\n', 'noop:0\n']);
    await transportFactory.created.single.serverSends('data:ok\n@alice@');
    expect(await first, 'data:ok');
    expect(preambleAnswers, ['data:challenge'],
        reason: 'the preamble read its own reply, and the command its own');

    final second = lookUp.executeCommand('noop:1\n');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await transportFactory.created.single.settle();
    expect(transportFactory.created.single.written,
        ['from:@alice\n', 'noop:0\n', 'noop:1\n'],
        reason: 'the connection is up, so no second preamble');
    await transportFactory.created.single.serverSends('data:ok\n@alice@');
    await second;

    await transportFactory.created.single.serverCloses();
    await transportFactory.created.single.settle();
    final third = lookUp.executeCommand('noop:2\n');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(transportFactory.created, hasLength(2),
        reason: 'a fresh connection was opened');
    await transportFactory.last.settle();
    expect(transportFactory.last.written, ['from:@alice\n'],
        reason: 'and the preamble ran on it before the command');
    await transportFactory.last.serverSends('data:challenge2\n@alice@');
    await transportFactory.last.settle();
    await transportFactory.last.serverSends('data:ok\n@alice@');
    expect(await third, 'data:ok');
    expect(preambleAnswers, ['data:challenge', 'data:challenge2']);

    await lookUp.close();
  });

  test('a lookup built with no onConnect sends the command first (control)',
      () async {
    final lookUp = AtLookUp.withSecureSocket(
      atSign: '@alice',
      rootDomain: const AtRootDomain(host, 64),
      authenticator: null,
      secondaryAddressFinder: addressFinder,
      transport: AtLookupTransportFactories(transportFactory: transportFactory),
    );

    final pending = lookUp.executeCommand('noop:0\n');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await transportFactory.created.single.settle();
    expect(transportFactory.created.single.written, ['noop:0\n']);
    await transportFactory.created.single.serverSends('data:ok\n@alice@');
    expect(await pending, 'data:ok');
    await lookUp.close();
  });
}
