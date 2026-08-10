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
