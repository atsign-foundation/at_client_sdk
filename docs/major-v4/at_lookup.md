# `at_lookup` 4.0.0-rc1

Second package in the v4 publish chain, step 4 of the publish ladder
([`implementation-plan.md`](../projects/wasm/implementation-plan.md) §10), Phase T
(transport). Depends on `at_utils` 4.0.0-rc1 (#2214); this branch stacks on
`st/at_utils-v4` until that lands, because `resolution: workspace` makes the floor
non-optional.

## Status (2026-10-23)

| Task | State | Where it landed |
|---|---|---|
| T1 — audit `AtConnection` / `getSocket()` callers | Done | In-repo callers were `remote_secondary.dart` and `monitor.dart`. External implementors stay OQ-8. |
| T2 — the transport interface | Done | `AtTransport` / `AtTransportFactory`. `AtLookupTransport` keeps its name and takes `transportFactory:`; the TLS config lives in `SecureSocketTransportFactory`. `secureSocketTransport(...)` and `secureSocketLookUps(...)` keep their signatures. |
| T3 — `getSocket()` off `AtConnection` | Done | `AtConnection` exposes `inbound`, `add(List<int>)` and an async `write(String)`. |
| T4 — factories off `SecureSocket` | Done | `AtLookupImpl` takes a required `transportFactory` and `secondaryAddressFinder`. |
| T5 — `at_lookup_io.dart` owns the native code | Done | `SecureSocketUtil` and `CacheableSecondaryAddressFinder` export from `_io` only. |
| T6 — follow the raw socket | Closed | `MonitorClient` is removed. at_client's `stream_notification_handler.dart` was deleted on trunk (#2384). |
| T7 — web `SecondaryAddressFinder` | Closed | `HttpsSecondaryAddressFinder` asks the atDirectory's HTTPS face, and `webSocketLookUps()` connects `wss://` straight to the atServer's `/ws`. Closes OQ-7 in code; see Residual. |
| T8 — publish 4.0.0 | Blocked | On #2214 landing. |

**Credential ladder removed:** the `atChops` / `signingAlgoType` / `hashingAlgoType` /
`enrollmentId` accessors, `AtLookupImpl.findSecondary`, `authenticate_cram`, and
`executeVerb`'s `sync` parameter.

**Web transport hardening:**

- `WebSocketTransport.inbound` is bounded in bytes. On overflow the connection is closed
  and a warning is logged.
- `flush()` waits for `bufferedAmount == 0`, bounded by `flushTimeout`.
- `add()` throws `AtIOException` on a socket that is not open.
- The `AtTransport` and `notifications` docs state the web exception to TCP back-pressure.

**Proxy path is dev-only:** `proxyWebSocketLookUps(host:, port:)` with the
`from:<atSign>` preamble. A proxy ends TLS and sees the session in the clear.

## Residual

- **atDirectory CORS** — the HTTPS face sets no `Access-Control-*` header, so a browser
  `fetch` fails until at_server adds it. Bead `at_client_sdk-8n0`.
- **Prod atDirectory :443** is not live; :64 answers in the raw protocol only.
- **Client-cert prompt** — the atServer's TLS socket requests a client certificate. A
  browser with certs installed may show a picker. Needs a smoke test against a live
  atServer.

## Dependency floors

`at_utils: ^4.0.0-rc1`. Every workspace consumer is floored at `at_lookup: ^4.0.0-rc1`.

## Open items

1. **Resolved — `websocket_uptake` does not bind the transport shape.** That spike
   (`at_libraries.git@websocket_uptake`, last commit 2025-01-15) still wraps
   `dart:io.WebSocket`, so it does not reach browser/WASM. This release proceeds
   independently.
2. **Where `AtTransport` lives long-term** — `at_lookup` or a future `at_transport`
   package. It stays in `at_lookup` for now.
3. **Resolved — `packages/at_lookup` in `at_client_sdk` is canonical.**
4. **`readResponse` / `AtLookupImpl` deprecations** — delete in this major, or reword.
   Bead `at_client_sdk-3en`.

## Exit

- `packages/at_lookup` analyze clean; VM and chrome suites green.
- `wasm_shakedown` green for both at_lookup barrels.
- Workspace consumers (at_auth, at_client, at_onboarding_cli, functional tests) analyze
  clean and pass their unit suites.

## Changelog

See [`packages/at_lookup/CHANGELOG.md`](../../packages/at_lookup/CHANGELOG.md) § 4.0.0-rc1.
