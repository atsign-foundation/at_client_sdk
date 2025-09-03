import 'dart:async';

import 'at_keys.dart' show AtKeys;

abstract class AtKeysIo {
  FutureOr<AtKeys> read(String atSign);
  FutureOr write(String atSign, AtKeys atKeys);
}
