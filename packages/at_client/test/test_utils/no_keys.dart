import 'package:at_auth/at_auth.dart';

/// A key source holding no key material for [atSign]: a client built on it
/// reads its encryption keys from its keystore and has no key to sign with.
InMemoryAtKeysIo noKeysFor(String atSign) =>
    InMemoryAtKeysIo.holding(atSign, AtKeys());
