# Keyfile capture

Writes keyfiles with published releases of at_auth, so that
`packages/at_auth/test/released_keyfile_test.dart` reads documents a previous
release wrote, not ones this tree constructs. The fixtures live in
`packages/at_auth/test/data/released/at_auth-<version>/`.

| Arm                  | Resolves                | Writes                                          |
| -------------------- | ----------------------- | ----------------------------------------------- |
| `released/3.3.0/`    | hosted at_auth 3.3.0    | `alice_key.atKeys`, `alice_key_passphrase.atKeys` |
| `released/3.2.0/`    | hosted at_auth 3.2.0    | `alice_key.atKeys`                              |

3.3.0 is the previous release of the package that owns the keyfile format.
3.2.0 is what at_onboarding_cli 1.16.0 and at_client 3.14.0 resolved on the
day they were released.

`capture/` holds the program, written once against the API both releases have,
so the two arms differ only in the at_auth they resolve. It makes the calls the
release's onboarding makes to write a keyfile: `generateKeyPairs()`, an
enrollment id set before the write, then `FileAtKeysIo.write`. No atServer is
involved: the enrollment id an atServer would issue is a random UUID here. The
keys are freshly generated test keys for the test atSign `@alice🛠`, valid on
no atServer.

Beside each keyfile, `<name>.read_back.json` records what that release's
`FileAtKeysIo.read` returned for it, and `provenance.json` records the
release, its archive checksum (from the lockfile, matching pub.dev's), the
lockfile's checksum, the Dart version, the command and the time.

**Neither arm is a workspace member.** Anything inside the workspace resolves
at_auth by path, and an arm has to run what pub.dev ships. Each arm's
`pubspec.lock` is committed, exempted from the repo-wide ignore by name.

## Capturing again

```bash
cd tests/keyfile_capture/released/3.3.0
dart pub get
dart run bin/capture.dart <empty output directory>
```

The program refuses a directory that is not empty. A new capture has new keys
and a new enrollment id, so replacing a fixture replaces its `read_back.json`
and `provenance.json` with it.
