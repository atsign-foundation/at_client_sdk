# Roadmap: at_client adopts the keystore primitives

**Status:** the keystore half is published and the at_client half is not
started. Re-derive both before acting on a row, with the commands in
[where each half stands](#where-each-half-stands).

## The plan

Twenty steps in ten pairs. In each pair the odd step adds a primitive to the
keystore interface in `at_persistence_secondary_server`, and the even step moves
an at_client consumer onto it, retiring the slower workaround that stood in for
the missing primitive. The pairs are listed impact first.

| Steps | Keystore primitive                            | The at_client consumer it serves                                                                                                                               |
|-------|-----------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1–2   | `exists(key)`                                 | `AtCollection._selfKeyExists`, which probes with `atClient.get` and reads the exception as absence                                                             |
| 3–4   | `scanKeys(KeyPattern)`                        | key listing by regex string (`getKeys(regex:)`), which Hive answers by matching every key in the box; a structured pattern maps onto SQL indexes               |
| 5–6   | `getMany(keys)`                               | the per-key `atClient.get` loop in `getItemsAsStream`, so a watch over N items is set up with one scan and one bulk read rather than one scan and N reads      |
| 7–8   | `removeMany(keys)`                            | the per-key deletes in `LocalSecondary.deleteExpiredKeys`, and in the collection's cascade from a parent delete                                                |
| 9–10  | `changes`, a keystore-level change stream     | `AtClient.dataEvents` and its `pendingEmissions`, both served from the client layer, which become a re-broadcast of the keystore's stream                      |
| 11–12 | `transaction(body)`                           | writes that touch several records as separate awaits, the cascade among them                                                                                   |
| 13–14 | `scanKeys` with `orderBy`, `limit` and `skip` | `Query.watch()`, which applies each event as a one-item delta only when the query has no `limit` or `skip`, and otherwise runs the whole query again per event |
| 15–16 | `queryByPath`, gated by `supportsPathQueries` | `Query.wherePath()`, whose predicates carry a field path so that a store can index them, and are evaluated in memory                                           |
| 17–18 | `snapshot()`, gated by `supportsSnapshots`    | a consistent read for `Query.fetch()`                                                                                                                          |
| 19–20 | `stats()`                                     | diagnostics                                                                                                                                                    |

## Why

at_client's collections were built on the keystore surface Hive offered, and
several of their costs come from that surface rather than from the work they
do:

- listing a collection's keys is a regex match over every key in the box;
- reading a collection's items is one `atClient.get` per key after that scan;
- a paginated `Query.watch()` runs the whole query again for every update;
- a `wherePath` predicate carries a field path for a store to index, and
  nothing passes it down.

The odd steps widen the keystore interface around what at_client needs, so that
a SQLite backend can answer from indexes while Hive implements the same
interface without them. A capability a backend may lack has a flag to check
first. Until at_client moves onto the new surface it calls the older one,
whichever backend the app chose
([wasm decisions D-25](../wasm/decisions.md#d-25--client-storage-is-the-apps-choice-at_client-keeps-a-hive-default-until-40-2026-10-07)).

## Order

The order above is for rolling out, but most pairs are independent. The
at_client halves can land in any order, except that steps 14 and 16 pass a
`KeyPattern`, so they build on step 4.

Steps 9–10 are partly in place: `AtClient.dataEvents` and `pendingEmissions`
are the shape consumers already use. Step 10 moves their source down to the
keystore.

## Where each half stands

**The keystore half is published.** `at_persistence_secondary_server` 4.3.4
has none of the ten primitives and 5.3.0 has all of them. Its 5.0.0 changelog
lists them "for at_client adoption", in the release that renamed
`SecondaryKeyStore` to `AtKeyValueStore` and moved the generic surface to
`KeyValueStore`. Read at 5.3.0: Hive reports neither path queries nor
snapshots, and SQLite reports path queries but not snapshots, so steps 17–18
have no backend to serve them yet.

**The at_client half is not started.** at_client calls `exists` in other
places, but not from `_selfKeyExists`, and calls none of the other nine.

```bash
# the version this workspace resolves, whose keystore spec to read
grep -A7 '^  at_persistence_secondary_server:' pubspec.lock | grep version
# which primitives at_client calls
git grep -n -E 'scanKeys\(|getMany\(|removeMany\(|KeyStoreChange|transaction\(|queryByPath\(|supportsPathQueries|snapshot\(|stats\(|\.exists\(' \
  -- packages/at_client/lib
```
