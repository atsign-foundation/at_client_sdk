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
   private content. Enter the code and your name, and *Accept*. Bob's
   *Received* tab shows the private content sealed until Alice confirms him.
3. **Alice's** app, while it is open, checks the code, confirms Bob and says
   so, and her *Sent* tab shows the name he gave, which her contact for him
   takes. Bob's app gets the key and opens the private content in place.
   Both apps now list the other under *Contacts*.

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

### Two windows, for a demo

```sh
demo/demo.sh                          # watch it
demo/demo.sh --record invitations.mp4 # and record it
```

`demo/demo.sh` plays the flow at a pace a viewer can follow, in two windows
side by side: Alice on the left, Bob on the right. Alice invites Bob and goes
offline; Bob accepts and sees the private content sealed; Alice comes back,
her app confirms Bob and sends him the key, and his content opens. It starts
a fresh EE and builds the app with `integration_test/two_window_demo.dart` as
its entry point, so rebuild with `flutter build macos --debug` before running
the app by hand afterwards.

Keep both windows in view until it finishes: runs have been seen to stall
while they were hidden. `--record` needs `ffmpeg` and Screen Recording
permission for the terminal, and captures only the rectangle the two windows
fill. The paste dialog pre-fills from the clipboard, so the script saves the
clipboard's text and restores it at the end.

### Prerequisites

- Docker, Dart and Flutter.
- `127.0.0.1 vip.ve.atsign.zone` in `/etc/hosts`. The EE carries real
  certificates for that name.

`ee/up.sh` runs `atsigncompany/ephemeral:latest`, which at_server builds from
its latest production release. The example needs p3.16.5 or later, the first
production release that verifies the ML-DSA keys the `pqActive` posture
authenticates with. `INV_EE_IMAGE=atsigncompany/ephemeral:dev_env ee/up.sh`
runs at_server trunk instead. To run against an at_server branch that is not
on trunk yet, build an image from it with `ee/build_ee.sh <checkout> <ref>`,
then `INV_EE_IMAGE=at_ephemeral:invitations ee/up.sh`.

## How it works

`at_client`'s `lib/src/mixins/invitations.dart` holds the flow.

**The link and the code.** An invitation has a random 128-bit id and a
six-digit code. The link is `https://<host>/i#@alice/<id>`: the id sits in the
URL fragment, which browsers never send to the host, and the code never
appears in the link.

**The preview.** Alice publishes `public:_<id>.invitations.my_app@alice`,
holding the invitation's public details (in this app, her name and a
message), the expiry and, unless it is sent separately, the encrypted
content. Anyone with the id can read it; a `public:_` record is never listed
by a scan. It expires with the invitation and is deleted once the invitation
is decided.

**Accepting.** Bob's app keeps the preview, then shares an acceptance with
Alice, carrying the code and the name Bob gives.

**Deciding, from any of Alice's clients.** Every decision two of her clients
could race on is an immutable create on Alice's atServer, which refuses the
second writer: a claim per acceptance, an attempt slot per wrong code (the
fifth burns the invitation), and one outcome per invitation (accepted, burned
or revoked).

**Confirming.** The client that wins shares a connection with Bob, which
carries the content key, records his atSign and the name he gave on the sent
invitation, and deletes the preview. Bob's app then decrypts the content.

**Content.** An invitation with content gets a fresh AES-256-GCM key, bound to
the invitation, when it is created, and the content is fixed then. Bob holds
the ciphertext before he accepts, and the key reaches him only in the
connection. The code is never the key: once ciphertext has left in an email,
a short code could be brute-forced offline.

**Declining** forgets the invitation on Bob's device, so Alice never learns
his atSign.

**The app's own data.** `AtClientInvitations` carries the app's data as JSON
and keeps nothing else of the app's. `lib/models.dart` defines this app's:
`InviteDetails` for the preview, `AcceptanceDetails` for the acceptance and
`PrivateContent` for the content. Contacts belong to the app too. A contact
takes its invitation's id, and `Session.linkContacts` fills in both sides
from the invitation records on every pass.

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
