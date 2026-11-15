## 0.1.0

- Initial pre-release (unpublished): `portalSession` opens an ordinary `at_client` in the browser on in-memory storage and caller-supplied `AtKeys`, returning only once PKAM has succeeded.
- Direct transport by default, chosen with `SessionTransportOptions`; a dev proxy only when `proxyHost` and `proxyPort` are both set, or a `proxy:<host>` root.
