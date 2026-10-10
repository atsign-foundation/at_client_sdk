import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions, PutRequestOptions;
import 'package:at_commons/at_commons.dart' show AtKey, StoppedException;
import 'package:at_client/src/crypto/nskey/nskey_records.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('CurrentCkPointer');

/// Which content key a sender is currently writing under, for one destination.
///
/// Only ids, never key material, so this needs no protection at rest: the
/// `ckKid`, the destination's nskey generation it was cut for, and the
/// sender's own generation its sibling copy was sealed to (`ownNskeyKid`,
/// null when it has none). `ownRecorded` is false for a pointer written
/// before the own generation was recorded, which names no generation either
/// way.
@experimental
typedef CurrentCk = ({
  String ckKid,
  String nskeyKid,
  String? ownNskeyKid,
  bool ownRecorded,
});

/// Remembers the current CK per `(owner, ckNs)` so a restart resumes it
/// instead of cutting another.
///
/// Each enrollment keeps its own, in its reserved namespace on the atServer,
/// so a sibling enrollment neither reads nor overwrites it and a rotation
/// replaces only the calling enrollment's key. A client with no enrollment id
/// has no such namespace and keeps no pointer.
@experimental
class CurrentCkPointer {
  const CurrentCkPointer();

  /// The record holding the pointer for `(owner, ckNs)`, or null for a client
  /// with no enrollment id.
  AtKey? keyFor(AtClient atClient, String owner, String ckNs) {
    final enrollmentId = atClient.enrollmentId;
    if (enrollmentId == null) return null;
    return currentCkPointerKey(
        sharedBy: atClient.getCurrentAtSign(),
        enrollmentId: enrollmentId,
        destination: owner,
        ckNs: ckNs);
  }

  /// The CK this enrollment last recorded for `(owner, ckNs)`: from the
  /// atServer, falling back to local storage when that read fails.
  ///
  /// Null when nothing is recorded or the record cannot be read: forgetting the
  /// pointer costs an extra CK, never data.
  Future<CurrentCk?> read(AtClient atClient, String owner, String ckNs) async {
    final key = keyFor(atClient, owner, ckNs);
    if (key == null) return null;
    for (final remote in const [true, false]) {
      try {
        final value = await atClient.get(key,
            getRequestOptions: GetRequestOptions()..useRemoteAtServer = remote);
        final decoded = jsonDecode(value.value as String);
        if (decoded is! Map) return null;
        final ckKid = decoded['ckKid'];
        final nskeyKid = decoded['nskeyKid'];
        final ownNskeyKid = decoded['ownNskeyKid'];
        if (ckKid is! String ||
            nskeyKid is! String ||
            (ownNskeyKid != null && ownNskeyKid is! String)) {
          return null;
        }
        return (
          ckKid: ckKid,
          nskeyKid: nskeyKid,
          ownNskeyKid: ownNskeyKid as String?,
          ownRecorded: decoded.containsKey('ownNskeyKid'),
        );
      } on StoppedException {
        rethrow;
      } catch (e) {
        _logger.finer('No current-CK pointer for $owner:$ckNs '
            '(remote: $remote): $e');
      }
    }
    return null;
  }

  /// Records [ckKid] as the CK this enrollment is writing under for
  /// `(owner, ckNs)`, on the atServer first, with the destination's generation
  /// [nskeyKid] and the sender's own [ownNskeyKid].
  ///
  /// A failure is logged and swallowed; the CK has already been conveyed and
  /// promoted by the time this runs, so a restart just cuts a fresh one.
  Future<void> write(AtClient atClient, String owner, String ckNs, String ckKid,
      String nskeyKid,
      {String? ownNskeyKid}) async {
    final key = keyFor(atClient, owner, ckNs);
    if (key == null) return;
    try {
      await atClient.put(
          key,
          jsonEncode({
            'ckKid': ckKid,
            'nskeyKid': nskeyKid,
            'ownNskeyKid': ownNskeyKid,
          }),
          putRequestOptions: PutRequestOptions()
            ..shouldEncrypt = false
            ..useRemoteAtServer = true);
    } on StoppedException {
      rethrow;
    } catch (e) {
      _logger.warning('Could not record the current CK for $owner:$ckNs, so a '
          'restart will cut a fresh one: $e');
    }
  }
}
