import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

/// The explicit auth→client hand-off artifact.
///
/// The confirmed subset of an [AtAuthRequest] that client creation needs,
/// promoted to its own type so "request" doesn't quietly double as "session".
/// Keys cross the boundary as an [AtKeysIo] *source* — the client derives its
/// own [AtKeys] via `atKeysIo.read(atSign)`, rather than adopting
/// auth's live `AtChops`/`AtLookUp`.
class AtAuthSession {
  final String atSign;
  final AtRootDomain rootDomain;
  final String? namespace;
  final AtKeysIo atKeysIo;
  final String? enrollmentId;

  /// Auth's already-authenticated connection, carried so the client can *opt in*
  /// to reusing it (`fromAuthSession(..., reuse: true)`) and skip a second
  /// PKAM handshake. The default hand-off ignores this and rebuilds a fresh
  /// connection from [atKeysIo]; this is only the perf escape hatch.
  final AtLookUp? atLookUp;

  AtAuthSession({
    required this.atSign,
    required this.rootDomain,
    required this.atKeysIo,
    this.namespace,
    this.enrollmentId,
    this.atLookUp,
  });
}
