# The upgrade check

Whether a client store written by one at_client still works after the app
moves to this tree's at_client. The test is
`tests/at_functional_test/test/upgrade_test.dart`, tagged `upgrade`, so the
functional pack's `runLocal.sh` stays the one entry point:

```bash
cd tests/at_functional_test
./runLocal.sh 30000 test/upgrade_test.dart
```

Every arm writes a Hive store, so the test skips itself when
`AT_FUNCTIONAL_STORAGE` names another backend.

## What one arm does

An arm is one version of at_client that writes a store. For each, the test:

1. **Seeds** a store with that version: one record of each kind (self, shared,
   public, `local:`), a value with a newline and a binary one, a collection
   item shared with a peer, a read receipt for the peer's item, a received
   notification and a completed sync. It reports what that version observes
   of the store and the key it keeps its sync cursor under, which a store with
   no lifecycle marker is judged by, then makes one last write and exits
   without waiting to push it.
2. **Upgrades**: this tree opens the same store, with the same app code, while
   a notification sent in the gap waits on the atServer. Before it does, the
   test asks the atServer directly whether the last write reached it, and it
   must not have. Once open, a `local:` record must still be stored the way
   that version stores one (encrypted before 3.15), or the arm is not testing
   the store it claims to. Then this tree must observe what the seeding
   version observed, deliver that notification, complete two syncs and push
   the write left behind.
3. **Churns** every record: reads it, writes it back through the same `AtKey`,
   then writes a value of another shape (a newline removed, a byte added) and
   the original again, reading each back with a fresh key. A `local:` record is
   written once more without encryption, and must end up stored unflagged.
4. **Restarts** and repeats the observation, with a second notification
   waiting.
5. **Inspects the raw store**: no record may be flagged encrypted without a
   value shaped like ciphertext, flagged base64 without decoding, or fail to
   read.
6. **Checks the log**: no warning or worse while the arm ran.

The arm seeded by this tree is the control. A difference it reports is not
about an upgrade; a difference only a released arm reports is.

## The arms

| Directory                          | Resolves                                  |
| ---------------------------------- | ----------------------------------------- |
| `released/3.14.0/`                 | hosted 3.14.0, locked                     |
| `released/3.14.0-release-day/`     | hosted 3.14.0 over its release-day deps   |
| `released/3.15.0-rc3/`             | hosted 3.15.0-rc3, locked                 |
| (none)                             | this tree, in the test                    |

The release-day arm pins the persistence, crypto and commons packages to the
newest versions on 3.14.0's release day, so a store in the formats an early
3.14.0 install wrote is in the comparison, not only the formats a build of it
resolves today.

**None is a workspace member.** Anything inside the workspace resolves
at_client by path, and an arm has to run what pub.dev ships. Each
`pubspec.lock` is committed and exempted from the repo-wide ignore by name:
an arm that re-resolves its transitive set on every machine could report a
finding or a different at_commons, with no way to tell which.

`scenario/` holds the seed, the snapshot and `bin/seed.dart`, written once
against the API every arm has. An arm runs it as
`dart run upgrade_scenario:seed` under its own resolution, and the test links
the same library against this tree.

## Adding to it

- **A new released version**: copy a `released/<version>/` directory, change
  the pin and the package name, run `dart pub get` there, and add an arm to
  `_arms` in the test.
- **A new kind of persisted state**: add the write to `seed` and what an app
  can observe of it to `snapshot`. Both must compile against the oldest arm;
  `dart run upgrade_scenario:seed` in its directory says whether they do.
- **An intended difference**: add it to the arm's `expected` in the test,
  spelled exactly as the failure printed it, with the reason. Each one must
  still occur, so a listed difference that goes away fails the test until it
  is removed. Anything not listed is a defect or a decision for review.

## What it cannot see

Only what the seed writes and the snapshot reads. Downgrades, the atServer's
own store, and API that one of the arms lacks are outside it.

Nor a queue a seed left outside its store. 3.14.0 opens its sync queue lazily
on Hive's global instance, whose directory is the last one any store, or the
app, gave Hive: switching back to an atSign whose queue had not opened yet,
when atSigns keep separate directories, or an app's own `Hive.init`, leaves
the queue in another directory. This tree takes such a queue in when the
atSign's store opens, from a directory this process has opened a store in or
the one Hive's global instance pointed at
(`packages/at_client/test/storage/stray_sync_queue_test.dart`); one in a
directory neither names stays where it is, and so does one that cannot be
read, with a warning, while the store opens without it. Every arm seeds its store from one
client that writes before anything else touches Hive, so none strands its
queue.

Nor a store older than its oldest arm. at_client 3.11 and earlier kept unsynced
writes in a commit log, which no release since 3.12 reads: this tree opens
such a store's keystore and leaves those writes unpushed, as a 3.11.0 seed at
sshnoports v5.17.0's resolution showed.
