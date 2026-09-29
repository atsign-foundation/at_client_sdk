# Invitations

Alice invites Bob to connect, whether or not Bob has an atSign yet. She sends
him a link and, separately, a short code. Once Bob has the app and an atSign,
he accepts; Alice's app checks the code, and then each of them has the other
as a contact. Alice can attach private content to the invitation, which Bob
can read once she has confirmed him.

The app is built on `AtClientInvitations` from
`package:at_client/at_client_mixins.dart`. Nothing in that API needs Flutter,
so a CLI uses it the same way. It runs only at the `pqActive` posture, so
everything it shares is sealed post-quantum.

It runs against a self-contained Ephemeral Environment (EE), an atDirectory
and an atServer per atSign in one local container, with a small issuer
standing in for a registrar.

## Running it

```sh
ee/up.sh                # a fresh EE, and the issuer on localhost:35100
flutter build macos --debug
open -n build/macos/Build/Products/Debug/invitations.app    # Alice
open -n build/macos/Build/Products/Debug/invitations.app    # Bob
ee/down.sh              # when you have finished
```

Then, as two people:

1. **Alice**: *Get a new atSign*. The app asks the issuer for the next atSign
   it has not handed out, and activates it with that atSign's CRAM secret.
   Then *Invite*: who, your name, a message, and optionally something
   private. The app shows the link and the code.
2. **Bob**: *Paste an invitation*, and paste the link. Then *Get a new
   atSign*. The invitation opens: who it is from, and whether it carries
   private content. Enter the code and *Accept*.
3. **Alice's** app, while it is open, checks the code and confirms Bob. Both
   apps now list the other under *Contacts*, and Bob's *Received* tab shows
   the private content, decrypted.

`ee/up.sh` starts from nothing each time: it destroys the previous EE and
forgets what the issuer handed out, so an atSign from an earlier run no longer
exists.

A debug build is signed ad hoc, so after a rebuild macOS may ask whether the
app can use its keychain items. Choose *Always Allow*.

### Without anyone at the keyboard

```sh
ee/up.sh
flutter test integration_test -d macos --concurrency=1
```

`integration_test/invitation_flow_test.dart` drives the same steps through
the app's screens, playing Alice and Bob in turn on one device. It keeps keys
in files in a temporary directory rather than the keychain, which could stop
to ask for permission.

### Prerequisites

- Docker, Dart and Flutter.
- `127.0.0.1 vip.ve.atsign.zone` in `/etc/hosts`. The EE carries real
  certificates for that name.

`ee/up.sh` runs `atsigncompany/ephemeral:dev_env`, which at_server publishes
from trunk. `atsigncompany/ephemeral:latest` is built from the latest
production release, which cannot verify the ML-DSA keys the `pqActive`
posture authenticates with. To run against an at_server branch that is not on
trunk yet, build an image from it with `ee/build_ee.sh <checkout> <ref>`, then
`INV_EE_IMAGE=at_ephemeral:invitations ee/up.sh`.

## How it works

`at_client`'s `lib/src/mixins/invitations.dart` holds the flow.

**The link and the code.** An invitation has a random 128-bit id and a
six-digit code. The link is `https://<host>/i#@alice/<id>`: the id sits in the
URL fragment, which browsers never send to the host, and the code never
appears in the link.

**The preview.** Alice publishes `public:_<id>.invitations.my_app@alice`,
holding her name, a message, the expiry and, unless it is sent separately, the
encrypted content. Anyone with the id can read it; a `public:_` record is
never listed by a scan. It expires with the invitation and is deleted once
the invitation is decided.

**Accepting.** Bob's app keeps the preview, then shares an acceptance carrying
the code with Alice.

**Deciding, from any of Alice's clients.** Every decision two of her clients
could race on is an immutable create on Alice's atServer, which refuses the
second writer: a claim per acceptance, an attempt slot per wrong code (the
fifth burns the invitation), and one outcome per invitation (accepted, burned
or revoked).

**Confirming.** The client that wins shares a connection with Bob, which
carries the content key, links his atSign to the contact, and deletes the
preview. Bob's app then adds Alice as a contact and decrypts the content.

**Content.** An invitation with content gets a fresh AES-256-GCM key, bound to
the invitation, when it is created, and the content is fixed then. Bob holds
the ciphertext before he accepts, and the key reaches him only in the
connection. The code is never the key: once ciphertext has left in an email,
a short code could be brute-forced offline.

**Declining** forgets the invitation on Bob's device, so Alice never learns
his atSign.

Alice's app handles acceptances only while it is open. A deployment that wants
Bob confirmed promptly runs an always-on client of Alice's, enrolled for the
namespace, that calls `processAcceptances()`.

## Invitation links on phones

`landing/` is a template for the site the links point at:

- `landing/i/index.html` shows who the invitation is from and sends the
  visitor to the app, or to the right store. On iOS it copies the link, for
  the app to take on first run; on Android the Play install referrer carries
  it through the install. The invitation stays in the fragment, so the site's
  server never sees it.
- `landing/.well-known/` holds the two files that let iOS and Android open
  `https://<host>/i` links in the app. Replace the team id, the signing
  certificate fingerprint and `invite.example.com` (also in
  `lib/screens/invite.dart`, the Android manifest and
  `ios/Runner/Runner.entitlements`) with your own.

The macOS build takes invitations by paste only: opening links there needs a
development-signed build.
