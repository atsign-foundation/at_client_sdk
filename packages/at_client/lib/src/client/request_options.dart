/// Parameters that application code can optionally provide when calling
/// `AtClient.get`, `AtClient.put` and `AtClient.delete` methods
abstract class RequestOptions {}

/// Parameters that application code can optionally provide when calling
/// `AtClient.get`
class GetRequestOptions extends RequestOptions {
  /// Whether the `get` request should bypass this atSign's cache of data owned
  /// by another atSign
  bool bypassCache = false;
}

/// Parameters that application code can optionally provide when calling
/// `AtClient.put`
class PutRequestOptions extends RequestOptions {
  /// Whether to set the `sharedKeyEnc` and `pubKeyCS` properties on the
  /// Metadata for this put request
  bool storeSharedKeyEncryptedMetadata = true;
  /// Whether to send this update request directly to the remote atServer
  bool useRemoteAtServer = false;
}

/// Parameters that application code can optionally provide when calling
/// `AtClient.delete`
class DeleteRequestOptions extends RequestOptions {
  /// Whether to send this update request directly to the remote atServer
  bool useRemoteAtServer = false;
}