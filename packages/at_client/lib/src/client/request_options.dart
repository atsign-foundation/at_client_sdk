/// Holder for any parameters that has to be passed to at client methods from the app
class RequestOptions {}

/// Request params for at client get method
class GetRequestOptions extends RequestOptions {
  bool bypassCache = false;
}

class PutRequestOptions extends RequestOptions {
  bool storeSharedKeyEncryptedWithData = true;
}
