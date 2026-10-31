import 'dart:convert';

import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show AtMetaData;

/// The atServer's inbound buffer, in bytes: a command longer than this
/// closes the connection.
const _atServerInboundBytes = 10240000;

/// The headroom a push batch keeps below [_atServerInboundBytes], the same
/// the default `AtClientPreference.maxDataSize` leaves.
const _batchHeadroomBytes = 10000;

/// Whether sync pushes [atKey] for a write of [op].
bool syncsKey(String atKey, SyncQueueOp op) {
  if (atKey.startsWith('cached:')) {
    // Receiver-initiated delete of a cached key is the one
    // legitimate client→server case for cached:; everything else
    // (puts, meta updates) is server-originated and shouldn't be
    // pushed back.
    return op == SyncQueueOp.delete;
  }
  final type = AtKey.getKeyType(atKey);
  return type == KeyType.selfKey ||
      type == KeyType.sharedKey ||
      type == KeyType.publicKey ||
      type == KeyType.reservedKey;
}

/// The metadata fragment sync pushes for [metadata], through the canonical
/// [Metadata.toAtProtocolFragment] that direct writes also use.
String pushMetadataFragment(AtMetaData? metadata) {
  // NOTE: `toCommonsMetadata` omits the timestamp fields
  // (createdAt/updatedAt/expiresAt/availableAt) and sharedKeyStatus, so the
  // push does not send them and the atServer re-derives them on receipt.
  return metadata?.toCommonsMetadata().toAtProtocolFragment() ?? '';
}

/// The command sync pushes for a record of [atKey] holding [data] with
/// [metadata]: its value and metadata together.
String pushUpdateCommand(String atKey, AtMetaData? metadata, Object? data) =>
    'update${pushMetadataFragment(metadata)}:$atKey $data';

/// The most UTF-8 bytes one `batch:` command may take, for a client whose
/// `AtClientPreference.maxDataSize` is [maxDataSize]. It stays within that
/// too, which `RemoteSecondary` checks in UTF-16 code units, and a string
/// never has more of those than UTF-8 bytes.
int pushBudgetBytes(int maxDataSize) {
  const inbound = _atServerInboundBytes - _batchHeadroomBytes;
  return maxDataSize < inbound ? maxDataSize : inbound;
}

/// The UTF-8 bytes [command] takes in a push batch: once its newlines are
/// replaced, as a JSON string.
int pushedCommandBytes(String command) =>
    utf8.encode(jsonEncode(VerbUtil.replaceNewline(command))).length;

/// The UTF-8 bytes of the `batch:` command sync sends for [count] requests
/// whose JSON takes [requestBytes] in all: `batch:[`, the requests joined by
/// commas, then `]` and the line feed.
int batchCommandBytes(int requestBytes, int count) =>
    'batch:['.length + requestBytes + count - 1 + ']\n'.length;

/// The UTF-8 bytes of a [BatchRequest] with [id] whose command, encoded as a
/// JSON string, takes [commandBytes].
int batchRequestBytes(int id, int commandBytes) =>
    utf8.encode(jsonEncode(BatchRequest(id, ''))).length -
    '""'.length +
    commandBytes;

/// The UTF-8 bytes of a `batch:` command carrying [command] alone.
int pushBytesAlone(String command) =>
    batchCommandBytes(batchRequestBytes(1, pushedCommandBytes(command)), 1);
