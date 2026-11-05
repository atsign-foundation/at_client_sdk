import 'dart:async' show FutureOr;

import 'package:at_auth/at_auth.dart' show AtKeys, InMemoryAtKeysIo;

/// What reading a keyfile that exists and cannot be read throws.
class KeyfileUnreadable implements Exception {}

/// A keyfile that exists and that this process cannot read: the first
/// [failing] reads throw [KeyfileUnreadable], and every later one answers what
/// it holds.
class UnreadableKeysIo extends InMemoryAtKeysIo {
  int failing;

  UnreadableKeysIo({this.failing = 1 << 30});

  @override
  FutureOr<AtKeys> read(String atSign) {
    if (failing > 0) {
      failing--;
      throw KeyfileUnreadable();
    }
    return super.read(atSign);
  }
}
