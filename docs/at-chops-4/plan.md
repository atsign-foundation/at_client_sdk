# at_chops 4.0.0

at_chops 4.0.0 ships on its own, ahead of the packages that use it. at_client
4.0 and at_auth 4.0 build on at_chops 3.7.1 and expose no `AtChops`, so moving
each of them to at_chops 4 is a 4.x minor. NoPorts uses `EncryptionKeyType`, so
it moves at the same time.

## What changes before 4.0.0 ships

`4.0.0-rc.1` is the starting point. Four things change before 4.0.0:

1. `RsaSignatureAlgo` and `RsaKeyPair` stay. at_chops 3.7.0's deprecations name
   them as the replacements, so removing them leaves a 3.x user with nowhere to
   go.
2. RSA signing and key generation keep their synchronous forms.
3. `EncryptionKeyType` stays. Its names are wire vocabulary that other clients
   read.
4. Verifying an RSA signature against a malformed public key throws the
   verification exception, not `TypeError` or `RangeError`.

Each starts as Given/When/Then scenarios, agreed before the code changes,
alongside the format-compatibility scenarios: what 3.x encrypted or signed
still opens and verifies under 4.0.0.

## How it reaches trunk

The work happens on `at_chops-4.x`. When it merges to trunk, `packages/at_chops`
becomes 4.0.0 outside the root workspace, as rc.1 was, and 4.0.0 publishes from
there; trunk's other packages keep resolving at_chops 3.7.1 from pub.dev. The
at_client and at_auth minors that move to at_chops 4 bring it back into the
workspace.

## The earlier plan

The earlier migration ledger, on `xl/feat/at-chops-4`
(`docs/at-chops-4/decisions.md` and `implementation-plan.md`), planned the
dependents' moves in slices. Its D1, at_lookup dropping the `AtChops`
credential ladder, shipped in at_lookup 4.0.0. Its D2, at_client keeping an
inert `AtChops` while staying on at_chops 3.x, is superseded: at_client 4.0
exposes no `AtChops`.
