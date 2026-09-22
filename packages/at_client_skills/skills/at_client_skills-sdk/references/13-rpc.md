# RPC — Structured Request/Response with AtRpc

`AtRpc` / `AtRpcClient` give you a request/response abstraction between two
atsigns, built on atProtocol notifications: requests travel as
`request.<reqId>.<domain>.__rpcs.<baseNameSpace>` notifications, responses as
`<ack|nack|success|error>.<reqId>....` notifications. Both classes are exported
from `package:at_client/at_client.dart`.

**When to use RPC vs the alternatives:**

| You need…                                     | Use                                  |
| --------------------------------------------- | ------------------------------------ |
| Shared, persistent, typed app data            | `AtCollection<T>` (the default)      |
| Fire-and-forget events / telemetry            | `NotificationService` send/subscribe |
| "Call another atsign and get an answer back"  | **AtRpc / AtRpcClient**              |

RPC is for *actions and queries* ("plan this route", "what is your status?"),
not for *data* — results worth keeping should be written to an `AtCollection`
by the responder, not parked in RPC payloads.

---

## Client side — `AtRpcClient`

The high-level client wraps request/response correlation in a single call:

```dart
import 'package:at_client/at_client.dart';

final client = AtRpcClient(
  serverAtsign: '@routeplanner',
  atClient: atClient,
  baseNameSpace: 'my_app',           // your app's namespace
  domainNameSpace: 'route_planning', // logical group of RPCs within the app
);

// Sends the request, awaits the success response, returns its payload.
final Map<String, dynamic> answer =
    await client.call({'from': 'A', 'to': 'B'});
```

- `call()` generates the request id, sends via the underlying `AtRpc`, and
  completes when a `success` response arrives. A `nack`/`error` response
  completes the future with an error — wrap in try-catch.
- `ack` responses are informational ("received, working on it"); `call()` keeps
  waiting for the final result.
- If the client has already been stopped, `call()` throws `StoppedException`
  rather than sending — see
  [17-error-handling.md](17-error-handling.md).

> **Gotcha: `call()` has no timeout of its own.** If the responder is offline,
> has no handler for the request, or simply never replies, the future waits
> **forever** — bound every call yourself.

Nothing else ever completes it except your own client stopping, which errors it
with `StoppedException`. The retry and expiry settings below are not a safety
net here: they cover *delivering the request*, not getting an answer to it, so a
request that arrives and is then ignored has consumed neither.

```dart
try {
  final answer = await client
      .call({'from': 'A', 'to': 'B'})
      .timeout(const Duration(seconds: 20));
} on TimeoutException {
  // dart:async — no answer in time. Decide: retry, degrade, or give up.
} on StoppedException {
  // at_commons — our own client stopped; the answer is not coming.
}
```

Pick the duration from how long the responder legitimately needs, not from the
request expiry — they measure different things.

> **Gotcha:** `AtRpcClient` is one-way — its `handleRequest` throws
> `UnimplementedError`. One process cannot use the same `AtRpcClient` to serve
> requests; create an `AtRpc.server` (below) for that, on a *different* atsign.

## Server side — `AtRpc.server`

```dart
Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async {
  final result = await planRoute(request.payload);
  return AtRpcResp(
    reqId: request.reqId,
    respType: AtRpcRespType.success,
    payload: result,
  );
}

final rpc = AtRpc.server(
  atClient: atClient,
  baseNameSpace: 'my_app',
  domainNameSpace: 'route_planning',
  requestHandler: handleRequest,
  allowList: {'@commuter1'.toAtsign(), '@commuter2'.toAtsign()},
  allowAll: false,
  enableRequestMutex: false,   // true when running multiple server instances
);
rpc.start();                   // subscribes to request notifications
```

- **`allowList`** — requests from atsigns not on the list are discarded before
  your handler runs. `allowAll: true` bypasses this; then *your handler* is
  responsible for checking `fromAtSign`.
- The framework auto-sends an `ack` before invoking your handler, and converts
  a thrown exception into a `nack` with the error message — so throwing on bad
  input is fine.
- `AtRpcResp` provides `ack`/`nack` static helpers only; build `success` and
  `error` responses with the main constructor (`respType:
  AtRpcRespType.success` / `.error`).
- Sends retry automatically: up to `maxSendAttempts` (default 4) with backoff.
- Requests expire after `AtRpc.defaultNotificationExpiry` (30 s) if not
  delivered.

## Both sides — implementing `AtRpcCallbacks`

`AtRpcClient` and `AtRpc.server` are one-way **by construction**, and each
throws on the half it does not do: `AtRpcClient.handleRequest` throws
`UnimplementedError`, and the adapter behind `AtRpc.server` throws the same
from `handleResponse`. That is fine for a pure caller or a pure responder.

When one atsign needs to do both — a peer that answers requests *and* makes
them — construct `AtRpc` directly with your own `AtRpcCallbacks`. It is a
two-method interface, and `isClient` / `isServer` both default to `true`:

```dart
class RoutePeer implements AtRpcCallbacks {
  late final AtRpc rpc;

  RoutePeer(AtClient atClient) {
    rpc = AtRpc(
      atClient: atClient,
      baseNameSpace: 'my_app',
      domainNameSpace: 'route_planning',
      callbacks: this,                       // both halves land here
      allowList: {'@partner'.toAtsign()},
      // isClient and isServer both default to true
    );
    rpc.start();
  }

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async {
    return AtRpcResp(
      reqId: request.reqId,
      respType: AtRpcRespType.success,
      payload: await planRoute(request.payload),
    );
  }

  @override
  Future<void> handleResponse(AtRpcResp response) async {
    // Every response type arrives here, including ack.
    switch (response.respType) {
      case AtRpcRespType.ack:      // "received, working on it" — progress
      case AtRpcRespType.success:
      case AtRpcRespType.nack:
      case AtRpcRespType.error:
    }
  }
}
```

**What you gain, and what you take on.** `AtRpcClient.call()` hides the
response machinery: it keeps a completer per `reqId`, swallows `ack`, completes
on `success` and raises on anything else. Implementing the interface yourself
means you see `ack` — the only way to drive a progress indicator for a
long-running request — but correlating responses to requests becomes your job,
since nothing is awaiting a future on your behalf.

> **`sendRequest` widens the allow list.** Every send does
> `allowList.add(toAtSign)` so the reply is accepted when it comes back. A
> peer's allow list therefore grows as it calls out, and is not purely the
> inbound boundary you configured. With `allowAll: true` it is not a boundary
> at all — check `fromAtSign` in `handleRequest` yourself.

Production code implements this interface directly: `NPA` in `noports_core`
(`abstract class NPA implements AtRpcCallbacks`) is the authorization service
an `sshnpd` consults, answering auth-check requests over RPC.

## Multiple server instances

Run N instances of the same responder atsign and set `enableRequestMutex:
true`: each incoming request is raced through an immutable mutex key, so
exactly one instance responds. This is the packaged form of the immutable-mutex
pattern — read [14-multi-agent.md](14-multi-agent.md) when building
multi-instance agents, RPC-based or not.

## AtCollection-first boundary

RPC does not replace collections and cannot be expressed through them —
`AtRpc` is its own notification-based machinery, and `AtCollection` has no
request/response semantics. Use RPC strictly for the interaction (the ask and
the answer); persist anything durable through `AtCollection<T>` as usual.
