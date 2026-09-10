import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions;
import 'package:at_commons/at_commons.dart' show AtKey;
import 'package:at_client/src/crypto/nskey/nskey_records.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('CurrentCkPointer');

/// Which content key a sender is currently writing under, for one destination.
///
/// Only the `ckKid` and the nskey generation it was cut for, never key
/// material, so this needs no protection at rest.
@experimental
typedef CurrentCk = ({String ckKid, String nskeyKid});

/// Remembers the current CK per `(owner, ckNs)` so a restart resumes it
/// instead of cutting another.
///
/// Stored as an ordinary self key, so it syncs to this atSign's other devices
/// and they converge on one CK per destination rather than one each.
/// Concurrent mints stay benign: both CKs are valid and a reader opens either.
@experimental
class CurrentCkPointer {
  const CurrentCkPointer();

  /// The self key holding the pointer for `(owner, ckNs)`.
  AtKey keyFor(AtClient atClient, String owner, String ckNs) =>
      currentCkPointerKey(
          sharedBy: atClient.getCurrentAtSign(),
          destination: owner,
          ckNs: ckNs);

  /// The CK this sender last recorded for `(owner, ckNs)`, read locally.
  ///
  /// Null when nothing is recorded or the record cannot be read: forgetting the
  /// pointer costs an extra CK, never data.
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
      _logger.finer('No current-CK pointer for $owner:$ckNs ($e)');
      return null;
    }
  }

  /// Records [ckKid] as the CK this sender is writing under for
  /// `(owner, ckNs)`.
  ///
  /// A failure is logged and swallowed; the CK has already been conveyed and
  /// promoted by the time this runs, so a restart just cuts a fresh one.
  Future<void> write(AtClient atClient, String owner, String ckNs, String ckKid,
      String nskeyKid) async {
    try {
      await atClient.put(keyFor(atClient, owner, ckNs),
          jsonEncode({'ckKid': ckKid, 'nskeyKid': nskeyKid}));
    } catch (e) {
      _logger.warning('Could not record the current CK for $owner:$ckNs, so a '
          'restart will cut a fresh one: $e');
    }
  }
}
