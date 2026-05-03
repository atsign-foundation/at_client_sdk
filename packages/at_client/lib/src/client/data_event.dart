import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// Event emitted on [AtClient.dataEvents] whenever a keystore
/// mutation passes through [LocalSecondary]'s chokepoint methods
/// (`_update` / `_delete`). Subscribers see every change driven by
/// this client — local app writes AND sync-applied remote changes —
/// in a single uniform stream.
///
/// Sealed so listeners can pattern-match against the two concrete
/// subtypes ([DataUpdated] / [DataDeleted]) exhaustively.
///
/// Note: [LocalSecondary.putValue] (used internally for SDK
/// bookkeeping like enrollment / cryptographic key material) does NOT
/// emit on this stream by design. App-data writes go through `_update`
/// and DO emit.
sealed class DataEvent {
  /// The full atKey of the affected record.
  final AtKey key;

  const DataEvent(this.key);
}

/// A keystore record was created or updated. Carries the metadata
/// constructed from the [UpdateVerbBuilder] that drove the write so
/// listeners (e.g. an event-driven expiry timer) can read `expiresAt`
/// without re-fetching the record.
final class DataUpdated extends DataEvent {
  /// The metadata persisted with the record. May be null when the
  /// underlying write didn't carry metadata (rare; defensive).
  final AtMetaData? metadata;

  const DataUpdated(super.key, {this.metadata});
}

/// A keystore record was removed.
final class DataDeleted extends DataEvent {
  const DataDeleted(super.key);
}
