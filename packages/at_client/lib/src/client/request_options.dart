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
  /// would return; an uncached key owned by another atSign is unaffected,
  /// because that read is a lookup and always goes to the atServer.
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
  /// miss a record this call has already reported written.
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
  /// a commit** — an atServer honouring it also purges any commit entry the
  /// key already has, and answers `-1` in place of a commit id.
  ///
  /// ⚠️ Without [useRemoteAtServer] this does nothing, because the default
  /// routing writes locally and sync later pushes with no flag; an atServer
  /// that does not honour the flag ignores it silently, so treat it as an
  /// optimisation that may not happen, never as a guarantee that a record
  /// stayed out of the commit log.
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
  /// a commit** — an atServer honouring it also purges any commit entry the
  /// key already has, and answers `-1` in place of a commit id.
  ///
  /// ⚠️ Without [useRemoteAtServer] this does nothing, because the default
  /// routing writes locally and sync later pushes with no flag; an atServer
  /// that does not honour the flag ignores it silently, so treat it as an
  /// optimisation that may not happen, never as a guarantee that a record
  /// stayed out of the commit log.
  bool noCommit = false;
}
