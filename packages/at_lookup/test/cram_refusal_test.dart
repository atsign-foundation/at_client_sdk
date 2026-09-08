import 'dart:math';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';
import 'holds_none_of.dart';

/// `cramAuthenticate` over a real connection and listener on a
/// [FakeAtServerTransport] that answers `from:` and refuses the `cram:`.
void main() {
  const atSign = '@alice';
  const host = '127.0.0.1';
  const port = 12345;

  late FakeAtServerTransportFactory transportFactory;
  late AtLookupMuxable atLookup;

  setUp(() {
    transportFactory = FakeAtServerTransportFactory();
    final addressFinder = MockSecondaryAddressFinder();
    when(() => addressFinder.findSecondary(atSign))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    atLookup = AtLookUp.withSecureSocket(
      atSign: atSign,
      rootDomain: const AtRootDomain(host, 64),
      authenticator: null,
      secondaryAddressFinder: addressFinder,
      transport: AtLookupTransport(transportFactory: transportFactory),
    );
  });

  tearDown(() => atLookup.close());

  /// The first command the client wrote that starts with [verb].
  Future<String> sent(String verb) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      for (final command in transportFactory.created.expand((t) => t.written)) {
        if (command.startsWith(verb)) return command;
      }
      if (DateTime.now().isAfter(deadline)) fail('no $verb was sent');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('Given an atSign and its CRAM secret', () {
    test(
        'when the atServer refuses CRAM authentication, then the exception '
        'carries the atServer\'s reason, and its text holds neither the '
        'secret nor the digest', () async {
      final random = Random.secure();
      final secret =
          List.generate(128, (_) => random.nextInt(16).toRadixString(16))
              .join();
      final reason =
          'error:AT0401-Exception: refused ${random.nextInt(1 << 32)}';

      final thrown = atLookup
          .cramAuthenticate(secret)
          .then<Object?>((_) => null, onError: (Object e) => e);
      await sent('from:');
      await transportFactory.created.single.serverSends(
          'data:_${const Uuid().v4()}$atSign:${const Uuid().v4()}\n');
      final digest = (await sent('cram:')).substring('cram:'.length).trim();
      await transportFactory.created.single.serverSends('$reason\n');
      final error = await thrown;

      expect('$error', holdsNoneOf(secret),
          reason: 'the exception holds none of the secret');
      expect('$error', holdsNoneOf(digest),
          reason: 'the exception holds none of the digest');
      expect(error, isA<UnAuthenticatedException>());
      expect('$error', contains(reason));
    });
  });
}
