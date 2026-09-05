/// Parameters that application code can optionally provide when calling
/// `AtClient.get`, `AtClient.put` and `AtClient.delete` methods
abstract class RequestOptions {}

/// Parameters that application code can optionally provide when calling
/// `AtClient.get`
class GetRequestOptions extends RequestOptions {
  /// Whether the `get` request should bypass this atSign's cache of data owned
  /// by another atSign
  bool bypassCache = false;

  /// Whether to send this get request directly to the remote atServer.
  ///
  /// A record this client wrote with the default routing sits in local storage
  /// until sync pushes it, so a remote read can fail to find what a local read
  /// would return. An uncached key owned by another atSign ignores this: that
  /// read is a lookup, which always goes to the atServer.
  bool useRemoteAtServer = false;
}

/// Parameters that application code can optionally provide when calling
/// `AtClient.put`
class PutRequestOptions extends RequestOptions {
  /// Whether to set the `sharedKeyEnc` and `pubKeyCS` properties on the
  /// Metadata for this put request
  @Deprecated('Ignored. Always true.')
  bool storeSharedKeyEncryptedMetadata = true;

  /// Whether to send this update request directly to the remote atServer.
  ///
  /// The default writes to local storage and the record reaches the atServer
  /// only when sync next pushes it, so a reader that is not this client's own
  /// store — another client of this atSign, or a peer looking the key up — can
  /// miss a record this call has already reported written. Set this when
  /// something else must be able to read the record as soon as the call
  /// returns, or await `waitUntilCaughtUp` before telling it to look.
  bool useRemoteAtServer = false;

  /// Except public keys, shared keys and self keys are encrypted by default.
  /// If client prefers not to encrypt a shared key or self key, set this flag
  /// to false.
  bool shouldEncrypt = true;

  /// Overrides the configured crypto provider for this put request.
  ///
  /// Leave null to use [AtClientPreference.crypto]'s default provider.
  String? cryptoProviderId;

  /// Whether the atServer should carry out this operation **without recording
  /// a commit**.
  ///
  /// A record written normally gets an entry in the atServer's commit log, and
  /// that entry is what every other client of this atSign syncs. For a record
  /// that exists only for a few seconds — an interlock taken and abandoned to
  /// its time-to-live — that is pure cost: the record is replicated to every
  /// device, expires there, and has to be reclaimed locally afterwards.
  ///
  /// It does more than skip: an atServer honouring it also purges any commit
  /// entry the key already has, and answers `-1` where it would otherwise
  /// return a commit id.
  ///
  /// ⚠️ **Set [useRemoteAtServer] alongside it, or this does nothing.** The
  /// flag is part of a command sent to the atServer, and the default routing
  /// writes to local storage instead — where the record gets a local commit
  /// entry, and sync later pushes it with a command that carries no flag. The
  /// commit then happens anyway.
  ///
  /// ⚠️ **An atServer that does not honour it fails SILENTLY too, and a caller
  /// cannot tell.** The flag travels as `:nc`, which the shared verb syntax
  /// has parsed for far longer than any atServer has acted on it — so an older
  /// atServer accepts the command, ignores the flag, and records the commit
  /// anyway. Nothing is refused and no error comes back.
  ///
  /// Between those two, treat this as an optimisation that may not happen,
  /// never as a guarantee that a record stayed out of the commit log.
  bool noCommit = false;
}

/// Parameters that application code can optionally provide when calling
/// `AtClient.delete`
class DeleteRequestOptions extends RequestOptions {
  /// Whether to send this delete request directly to the remote atServer.
  ///
  /// The default deletes from local storage and the removal reaches the
  /// atServer only when sync next pushes it, so another client or a peer can
  /// still read the record after this call returns.
  bool useRemoteAtServer = false;

  /// Whether the atServer should carry out this operation **without recording
  /// a commit**.
  ///
  /// A record written normally gets an entry in the atServer's commit log, and
  /// that entry is what every other client of this atSign syncs. For a record
  /// that exists only for a few seconds — an interlock taken and abandoned to
  /// its time-to-live — that is pure cost: the record is replicated to every
  /// device, expires there, and has to be reclaimed locally afterwards.
  ///
  /// It does more than skip: an atServer honouring it also purges any commit
  /// entry the key already has, and answers `-1` where it would otherwise
  /// return a commit id.
  ///
  /// ⚠️ **Set [useRemoteAtServer] alongside it, or this does nothing.** The
  /// flag is part of a command sent to the atServer, and the default routing
  /// writes to local storage instead — where the record gets a local commit
  /// entry, and sync later pushes it with a command that carries no flag. The
  /// commit then happens anyway.
  ///
  /// ⚠️ **An atServer that does not honour it fails SILENTLY too, and a caller
  /// cannot tell.** The flag travels as `:nc`, which the shared verb syntax
  /// has parsed for far longer than any atServer has acted on it — so an older
  /// atServer accepts the command, ignores the flag, and records the commit
  /// anyway. Nothing is refused and no error comes back.
  ///
  /// Between those two, treat this as an optimisation that may not happen,
  /// never as a guarantee that a record stayed out of the commit log.
  bool noCommit = false;
}
