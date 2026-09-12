import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_commons/at_commons.dart';

/// What a client is built from: the atSign, where its atServer is looked up,
/// the key source, and the enrollment the keys authenticate as.
///
/// Keys cross the boundary as an [AtKeysIo] *source* — the client derives its
/// own [AtKeys] via `atKeysIo.read(atSign)` and opens a connection of its
/// own; nothing live is handed across.
class AtAuthSession {
  final String atSign;
  final AtRootDomain rootDomain;
  final String? namespace;
  final AtKeysIo atKeysIo;
  final String? enrollmentId;

  AtAuthSession({
    required this.atSign,
    required this.rootDomain,
    required this.atKeysIo,
    this.namespace,
    this.enrollmentId,
  });
}
