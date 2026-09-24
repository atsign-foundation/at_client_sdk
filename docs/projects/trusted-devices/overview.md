# Trusted connections — overview

* **Status:** Draft — for review
* **Last Updated:** 2026-09-23
* **Full detail:** [decision record](https://docs.google.com/document/d/1qHwt2lLxzaFEIPpvI3tyu6TD0wf7M4Pc1antpF1B1ZE/edit)

## The idea

Tag a connection with the device it comes from. A connection from a device the
owner has registered is a **trusted connection**, and gets authority an
ordinary connection does not.

The `from:` verb already carries a client config — `clientId`, `appName`,
`platform` — that the atServer stamps on the connection. **Add one field: a
device ID.**

## What it buys

| Action | Ordinary | Trusted |
| --- | --- | --- |
| Re-enroll the same app on the same device | New OTP from the owner | No OTP |
| Read a **public hidden** key marked *device-secrecy* | Served to anyone who knows the name | Allowed |
| Get its re-enrollment approved | Owner approves | Open question |

## The hole it closes

A public hidden key (`public:_…`) is readable today by **any unauthenticated
connection that knows its name**. The `_` prefix affects only `scan:` listings
and the access log, so the protection is the name being unguessable — and the
read is not recorded. A device-secrecy attribute replaces obscurity with a
gate that logs every read.

## What the ID is, per platform

| Client | ID |
| --- | --- |
| Native desktop | MAC address, or the OS machine ID — paired key in the Secure Enclave, released by **Touch ID** |
| iOS / Android | `identifierForVendor` / `ANDROID_ID` |
| Browser | A device-bound passkey |
| Enterprise | A device claim from Entra ID or Okta |

## The rule that makes it safe

**A device ID is a name, not a secret** — anyone who has seen one can send it.
So the device also registers a public key its platform holds (Keychain, TPM,
Keystore, authenticator), and a trusted connection signs a fresh server
challenge with it. The ID says *which* device; the signature says *this* one.

## Why the browser cares

Browser storage is evictable, so a web app loses its atKeys on disk pressure
or a cleared profile. Recovery is a fresh APKAM enrollment, which today means
a human carrying a new OTP, every time.

## Cost

| Piece | Where |
| --- | --- |
| Device ID on `from:` | at_commons, atServer connection metadata |
| Registration in the enrollment record's `metadata` slot | at_commons — no grammar change |
| Signature check over the existing `from:` challenge | atServer |
| Device-secrecy key attribute and `lookup:` gate | at_commons, atServer grammar |
| One client provider interface, OTP fallback intact | at_client |

## For the call

* Does a trusted connection also **auto-approve** its own re-enrollment?
  Without it, the OTP goes but the walk to a second device stays; with it, the
  atServer grants namespaces but cannot re-seal the keys.
* **Refuse synced passkeys?** iCloud and Google passkeys always sync; refusing
  them excludes most Safari and Chrome users.
* **Who reads a device-secrecy key** — a device whose keys were evicted, or one
  registered without enrolling?
* **Who may see the registered devices?** Enrollment discovery hands every
  namespace co-member the record's metadata today.
