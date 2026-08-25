/// Parameters that application code can optionally provide when calling
/// `AtClient.get`, `AtClient.put` and `AtClient.delete` methods
abstract class RequestOptions {}

/// Parameters that application code can optionally provide when calling
/// `AtClient.get`
class GetRequestOptions extends RequestOptions {
  /// Whether the `get` request should bypass this atSign's cache of data owned
  /// by another atSign
  bool bypassCache = false;

  /// Whether to send this get request directly to the remote atServer
  bool useRemoteAtServer = false;
}

/// Parameters that application code can optionally provide when calling
/// `AtClient.put`
class PutRequestOptions extends RequestOptions {
  /// Whether to set the `sharedKeyEnc` and `pubKeyCS` properties on the
  /// Metadata for this put request
  @Deprecated('Ignored. Always true.')
  bool storeSharedKeyEncryptedMetadata = true;

  /// Whether to send this update request directly to the remote atServer
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
  /// ⚠️ **An atServer that does not honour it fails SILENTLY, and a caller
  /// cannot tell.** The flag travels as `:nc`, which the shared verb syntax
  /// has parsed for far longer than any atServer has acted on it — so an older
  /// atServer accepts the command, ignores the flag, and records the commit
  /// anyway. Nothing is refused and no error comes back. Treat this as an
  /// optimisation that may not happen, never as a guarantee that a record
  /// stayed out of the commit log.
  bool noCommit = false;
}

/// Parameters that application code can optionally provide when calling
/// `AtClient.delete`
class DeleteRequestOptions extends RequestOptions {
  /// Whether to send this delete request directly to the remote atServer
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
  /// ⚠️ **An atServer that does not honour it fails SILENTLY, and a caller
  /// cannot tell.** The flag travels as `:nc`, which the shared verb syntax
  /// has parsed for far longer than any atServer has acted on it — so an older
  /// atServer accepts the command, ignores the flag, and records the commit
  /// anyway. Nothing is refused and no error comes back. Treat this as an
  /// optimisation that may not happen, never as a guarantee that a record
  /// stayed out of the commit log.
  bool noCommit = false;
}
