import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// Implements the interface and nothing about lifetime: no `close`, no
/// `closedByClient`.
class _PlainKeysIo implements WrittenAtKeysIo {
  final inner = InMemoryAtKeysIo();

  @override
  AtKeysPassphraseEnvelopeCodec get passphraseCodec => inner.passphraseCodec;

  @override
  AtKeysAssurance get assurance => inner.assurance;

  @override
  AtKeys read(String atsign) => AtKeys();

  @override
  Future write(String atsign, AtKeys atKeys) async {}

  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {}

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {}
}

class _ClosableKeysIo extends InMemoryAtKeysIo implements ClosableAtKeysIo {
  @override
  bool closedByClient = true;
  int closes = 0;

  @override
  void close() => closes++;
}

void main() {
  group('the lifetime of a key store', () {
    test('a store that implements AtKeysIo needs no close', () {
      final io = _PlainKeysIo();
      expect(io, isA<WrittenAtKeysIo>());
      expect(io, isNot(isA<ClosableAtKeysIo>()));
      expect(io.read('@alice'), isA<AtKeys>());
    });

    test('the stores that ship are not closable', () {
      expect(InMemoryAtKeysIo(), isNot(isA<ClosableAtKeysIo>()));
    });

    test('a store that opts in says whether the client closes it', () {
      final io = _ClosableKeysIo();
      expect(io, isA<AtKeysIo>());
      expect(io.closedByClient, isTrue);
      io.close();
      expect(io.closes, 1);
    });
  });
}
