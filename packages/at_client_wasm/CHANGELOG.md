## 0.1.0

- Initial pre-release (unpublished): `portalSession` opens an ordinary `at_client` in the browser on in-memory storage and caller-supplied `AtKeys`, returning only once PKAM has succeeded.
- Direct transport by default, chosen with `SessionTransportOptions`; a dev proxy only when `proxyHost` and `proxyPort` are both set, or a `proxy:<host>` root. A host is a bare name or a bracketed IPv6 literal such as `[::1]`; anything else throws an `ArgumentError` naming the field.
- `portalSession` throws an `ArgumentError` for a `prefs` whose root is not the transport's, including a default `AtClientPreference()` passed with a proxy transport.
- `JsItemAddress.owner`, the owner in the JS collections adapter's item address, is an `Atsign`.
