# @atsign/at_client_web

atPlatform client for browsers. An atSign's keys stay in a passkey; this package opens a session on them from a web page.

## Install

```sh
npm install @atsign/at_client_web
```

The package is ESM and ships its own types. Its dart2js bundle sits at `dist/dart/at_client.js` and is injected as a script the first time a call needs it, so `dist/` must be served from your own origin.

## Quickstart

Open a session with the atSign's passkey, write and read a value, and watch for notifications:

```ts
import { AtClient } from '@atsign/at_client_web';

const client = await AtClient.create({ atSign: '@alice', namespace: 'myapp' });

await client.put({ key: 'note' }, 'hello');
console.log(await client.get({ key: 'note' })); // 'hello'

for await (const event of client.subscribe()) {
  console.log(event.operation, event.key, event.value);
  break; // leaving the loop unsubscribes
}

await client.close();
```

`namespace` is required and scopes every key. `app` defaults to `namespace`, `rpId` to `location.hostname` and `rpName` to `app`. Values are strings or `Uint8Array`; `get` returns `null` for a missing key. Send another atSign a notification with `client.notify({ key: 'greeting', sharedWith: '@bob' }, 'hi')`.

`subscribe(regex?)` registers when called, buffers up to 4096 events (see `overflow`), and ends when you leave the loop or call `close()`. Without `regex` it matches the client's namespace.

### Onboard a new atSign

`onboard` activates an atSign with its CRAM secret, seals its keys under a new passkey, and opens the session:

```ts
const client = await AtClient.onboard(
  { atSign: '@alice', namespace: 'myapp' },
  { cram: cramSecret, deviceName: 'laptop' },
);
```

The CRAM secret is pasted in by the user today; the package has no call that fetches it from the registrar yet. Hold it in memory only and clear the input once you have passed it on.

### Enroll another browser

A browser with no passkey for the atSign enrolls with a one-time code issued on a device that is already signed in:

```ts
// On the approving device (a session that holds the `__manage` access):
const code = await approver.otp();

// On the new browser, with the code the user carries over:
const pending = AtClient.enroll(
  { atSign: '@alice', namespace: 'myapp' },
  'myapp', // appName: the enrollment's app and scope
  'phone', // deviceName
  code,
);

// Back on the approving device:
for (const request of await approver.pendingEnrollments()) {
  await approver.approve(request.id); // or approver.deny(request.id)
}

const client = await pending; // resolves once the approval lands
```

`pendingEnrollments()` returns `{ id, appName, deviceName, namespaces }`, where `namespaces` maps each requested namespace to `r` or `rw`. `otp`, `pendingEnrollments`, `approve` and `deny` reject with `unsupported` on a session without `__manage`. The enrollment `onboard` creates holds it (the atServer grants it to the CRAM-activated first enrollment), also when `create` reopens it later; a browser added with `enroll` asks only for its own namespaces and does not. `approve` and `deny` with an id that is not pending reject with `enrollment_denied`.

## Entry points

| Call | Does |
|---|---|
| `AtClient.create(opts)` | Opens a session with the atSign's passkey |
| `AtClient.onboard(opts, { cram, deviceName? })` | Onboards a new atSign with its CRAM secret |
| `AtClient.enroll(opts, appName, deviceName, otp)` | Enrolls this browser with a code another device issued; resolves once that device approves |
| `AtClient.prfSupported()` | Whether this browser can evaluate passkey PRF |

On an open client: `get`, `put`, `delete`, `keys(filter?)`, `notify`, `subscribe`, `close`, and for pairing `otp`, `pendingEnrollments`, `approve`, `deny`. Every parameter, option and member is documented in the [API reference](#api-reference).

## Errors

Every call rejects with an `AtError`. Branch on `error.code`, never on the message.

| `code` | Meaning | What the caller does |
|---|---|---|
| `no_passkey_here` | This browser holds no passkey for the atSign | Offer `enroll` |
| `passkey_lost` | The passkey ceremony returned no credential, or its record did not authenticate | Offer `enroll` or retry the prompt |
| `prf_unavailable` | The browser or authenticator cannot evaluate passkey PRF | Tell the user to use a PRF-capable browser or authenticator |
| `pkam_refused` | The atServer refused this enrollment's login | Terminal for this device; an approving device must remove the enrollment and approve a new one |
| `public_key_mismatch` | The restored public keys differ from the ones the atServer holds | Stop; do not retry |
| `setup_lock_timeout` | Another tab is holding the atSign's first-setup lock | Retry after the other tab finishes |
| `offline` | The client did not come online | Retry when the network is back |
| `onboarding_incomplete` | Onboarding or enrollment started but did not finish | Run it again, or wait for the approval |
| `enrollment_denied` | The enrollment was denied, or an `approve`/`deny` id was unknown | Show the refusal; start over with a new code |
| `closed` | The client is closed | Open a new client |
| `unsupported` | The page, option or session cannot do this: not a browser, not a secure context, a `rootDomain` other than `root.atsign.org`, or a pairing call without `__manage` | Fix the environment or options |
| `bad_key` | A key is malformed, or `namespace` is missing | Fix the key or options |
| `overflow` | A subscription buffered more than 4096 events the app did not consume | Subscribe again |
| `internal` | Anything else, including a bundle that failed to load or an argument the bridge rejected | Report it |

`subscribe` after `close` throws `AtError('closed')` synchronously rather than rejecting.

## Requirements

- **A secure context.** HTTPS (or `localhost`). `create`, `onboard` and `enroll` outside one reject `unsupported`, as does any non-browser runtime.
- **A CSP that allows WebAssembly.** The bundle compiles WebAssembly, so `script-src` needs `'wasm-unsafe-eval'`. The demo's policy is a worked example:

  ```
  default-src 'none';
  script-src 'self' 'wasm-unsafe-eval';
  style-src 'self';
  connect-src https: wss:;
  img-src 'self';
  base-uri 'none';
  form-action 'none'
  ```

  `script-src 'self'` serves the bundle from your origin. `connect-src` is broad because the atServer's host comes from a root lookup at run time; narrow it if you know the host.
- **One `rpId`.** Passkeys are bound to a relying-party id, a single hostname (default `location.hostname`). A passkey made on one hostname is not offered on another, so an app that moves hostnames starts over with `enroll`.
- **Passkey PRF.** Keys are sealed with the PRF extension's output. Check `await AtClient.prfSupported()` first. Without PRF, `onboard` refuses before any passkey prompt and sessions reject `prf_unavailable`.

## Limits in v1

- No key-file (`.atKeys`) import.
- Only the `root.atsign.org` root; any other `rootDomain` rejects `unsupported`.
- The key codec cannot represent public keys: `public:` and `cached:` prefixes are dropped when a key is parsed, so `keys()` and `subscribe` do not distinguish a public key from a self key.
- Browser only; there is no Node runtime.

## API reference

The reference is generated from the doc comments in `src/index.ts`:

```sh
npm run docs:api   # writes docs/api/
```

`docs/api/` is not committed; run the script to produce it.

## Run the demo

From this directory, with the Dart bundle built (`packages/at_client_wasm/tool/build.sh`):

```sh
npm ci
npm run demo       # builds dist/, then serves demo/ with Vite
```

The demo page onboards, logs in, and puts, gets and lists keys; `talk.html` is a small chat over `notify` and `subscribe`. Both pages carry the CSP above.
