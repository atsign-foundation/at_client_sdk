import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:at_client/at_client.dart'
    show AtClient, AtKey, GetRequestOptions, Metadata;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('CurrentCkPointer');

/// Which content key a sender is currently writing under, for one destination.
///
/// Only the `ckKid` and the nskey generation it was cut for — never key
/// material. A `ckKid` is a truncated hash of nothing secret, so this needs no
/// protection at rest and can live in ordinary storage.
@experimental
typedef CurrentCk = ({String ckKid, String nskeyKid});

/// Remembers the current CK per `(owner, ckNs)` so a restart resumes it
/// instead of cutting another.
///
/// Without this, a cold write path finds an empty cache and mints. The CK is
/// still *correct* — readers recover any CK from its conveyance record — but
/// every restart leaves one more permanent `<ckKid>.__ck.<ckNs>@<owner>`
/// record, each protecting only the values written between two restarts.
/// Those records can never be cleaned up, because old data still needs them.
///
/// Stored as an ordinary **self key**, so it syncs to this atSign's other
/// devices and they converge on one CK per destination rather than one each —
/// which is what a CK is scoped to in the first place. Concurrent mints stay
/// benign: both CKs are valid and a reader opens either.
@experimental
class CurrentCkPointer {
  const CurrentCkPointer();

  /// Named so it is hidden from an ordinary scan, and namespaced by the
  /// namespace the nskey resolved to — matching the CK's own scope.
  AtKey keyFor(AtClient atClient, String owner, String ckNs) => AtKey()
    ..key = '__ckcur.${owner.replaceAll('@', '')}'
    ..namespace = ckNs
    ..sharedBy = atClient.getCurrentAtSign()
    ..metadata = Metadata();

  Future<CurrentCk?> read(AtClient atClient, String owner, String ckNs) async {
    try {
      final value = await atClient.get(keyFor(atClient, owner, ckNs),
          getRequestOptions: GetRequestOptions()..useRemoteAtServer = false);
      final decoded = jsonDecode(value.value as String);
      final ckKid = decoded['ckKid'];
      final nskeyKid = decoded['nskeyKid'];
      if (ckKid is! String || nskeyKid is! String) return null;
      return (ckKid: ckKid, nskeyKid: nskeyKid);
    } catch (e) {
      // Absent is the ordinary first-write case. Anything else is equally
      // survivable: forgetting the pointer costs an extra CK, never data.
      _logger.finer('No current-CK pointer for $owner:$ckNs ($e)');
      return null;
    }
  }

  Future<void> write(AtClient atClient, String owner, String ckNs, String ckKid,
      String nskeyKid) async {
    try {
      await atClient.put(keyFor(atClient, owner, ckNs),
          jsonEncode({'ckKid': ckKid, 'nskeyKid': nskeyKid}));
    } catch (e) {
      // The CK has already been conveyed and promoted by the time this runs,
      // so a failure here is a lost optimisation, not a lost key.
      _logger.warning('Could not record the current CK for $owner:$ckNs, so a '
          'restart will cut a fresh one: $e');
    }
  }
}
