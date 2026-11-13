# @atsign/at_client_web

atPlatform client for browsers. An atSign's keys stay in a passkey; this package opens a session on them from a web page.

```sh
npm install @atsign/at_client_web
```

```ts
import { AtClient } from '@atsign/at_client_web';

const client = await AtClient.create({ atSign: '@alice', namespace: 'myapp' });
await client.put({ key: 'note' }, 'hello');
console.log(await client.get({ key: 'note' }));

for await (const event of client.subscribe()) {
  console.log(event.operation, event.key, event.value);
}
```

## Entry points

| Call | Does |
|---|---|
| `AtClient.create(opts)` | Opens a session with the atSign's passkey |
| `AtClient.onboard(opts, { cram, deviceName? })` | Onboards a new atSign with its CRAM secret |
| `AtClient.enroll(opts, appName, deviceName, otp)` | Enrolls this browser with a code another device issued |
| `AtClient.prfSupported()` | Whether this browser can evaluate passkey PRF |

`namespace` is required. `app` defaults to `namespace`, `rpId` to `location.hostname` and `rpName` to `app`. Only `root.atsign.org` is supported as `rootDomain`.

## Requirements

- A browser page in a secure context (HTTPS or localhost); other environments reject with `AtError` code `unsupported`.
- A Content-Security-Policy that allows `wasm-unsafe-eval`.
- Passkeys are bound to one `rpId`, a single hostname.

Errors are `AtError`s; branch on `error.code`, never on the message.
