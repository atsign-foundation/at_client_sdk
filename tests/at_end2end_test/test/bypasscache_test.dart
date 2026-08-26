import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// `bypassCache` on a read of another atSign's shared data.
///
/// **The mechanism.** A key shared with a `ttr` is cached on the RECEIVER's
/// atServer. A read with `bypassCache = false` (the default) is answered from
/// that cache; a read with `bypassCache = true` makes the receiver's atServer
/// perform a fresh outbound `lookup:` to the publisher, so it returns the
/// publisher's current value and `isCached == false`. That fresh lookup also
/// refreshes the cache, so the next default read sees the new value too.
///
/// `autoNotify=false` is the lever that makes the cache go deliberately stale:
/// the publisher updates the key, and without auto-notify the receiver's
/// atServer is never told, so its cached copy keeps the old value. Without
/// that, cache and origin agree and the flag would be unobservable.
///
/// ⚠️ **THIS TEST'S HISTORY IS RACES, AND THE LAST ONE WAS IN ITS OWN GATE.**
/// It previously used `E2ESyncService.awaitKeyPushed` to know that a `put` had
/// reached the publisher's atServer. That helper matches sync events by
/// `k.key == atKey.toString()` — and this test puts **the same key twice**, so
/// both pushes emit a `localToRemote` event carrying an identical key string.
/// The gate for the SECOND put could therefore complete on the FIRST put's
/// event, after which the test read a publisher that still held the initial
/// value and blamed `bypassCache`. Measured 2026-08-26: red 2 of 3 full-pack
/// runs, green 8 of 8 alone — the difference being how much else was competing
/// for the machine, which is what decides whether a stale event lands late
/// enough to be seen.
///
/// **So this test no longer infers its preconditions from sync events. It
/// asserts them**, by reading the publisher's own atServer back until it holds
/// the value just written. That is the exact fact the `bypassCache` assertion
/// depends on, and reading it directly cannot be satisfied by a stale event
/// for an earlier write of the same key.
void main() async {
  late String sharedByAtSign;
  late String sharedWithAtSign;
  final namespace = TestConstants.namespace;
  var uuid = Uuid();

  setUpAll(() async {
    sharedByAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance().testInitializer(
        sharedByAtSign, namespace, authType,
        posture: PqPosture.legacy);
    await TestSuiteInitializer.getInstance().testInitializer(
        sharedWithAtSign, namespace, authType,
        posture: PqPosture.legacy);
  });

  /// Makes [atSign] the current atSign and returns its client.
  Future<AtClient> as(String atSign) async {
    await AtClientManager.getInstance().setCurrentAtSign(atSign, namespace,
        TestPreferences.getInstance()
            .getPreference(atSign, posture: PqPosture.legacy));
    return AtClientManager.getInstance().atClient;
  }

  Future<void> setAtSignOneAutoNotify(bool autoNotify) async {
    final client = await as(sharedByAtSign);
    var configResult = await client
        .getRemoteSecondary()!
        .executeCommand('config:set:autoNotify=$autoNotify\n', auth: true);
    if (configResult == null) {
      fail('failed to set auto config to $autoNotify');
    }
    expect(configResult.contains('data:ok'), true);
  }

  /// Polls [read] until it returns [expected], then returns. Fails with what
  /// it last saw rather than timing out silently.
  ///
  /// Every wait in this test is one of these: a named condition with a
  /// deadline, never a bare delay. A fixed sleep either wastes time or is too
  /// short on a loaded machine, and it records nothing when it is wrong.
  Future<void> pollUntil(
    String what,
    Future<String?> Function() read,
    String expected, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);
    String? last;
    while (DateTime.now().isBefore(deadline)) {
      last = await read();
      if (last == expected) return;
      await Future.delayed(Duration(milliseconds: 500));
    }
    fail('$what: waited $timeout for "$expected" and last saw "$last"');
  }

  test('A test to verify bypassCache', () async {
    int uniqueId = uuid.v4().hashCode;
    String keyEntity = 'test_bypass_cached_key-$uniqueId';
    String initialValue = 'initial_value-$uniqueId';
    String updatedValue = 'updated_value-$uniqueId';

    // A long ttl: this test polls two atServers and switches atSigns several
    // times, so a short-lived key can expire on the publisher before the
    // bypassCache lookup arrives — which surfaces as the publisher returning
    // 'null' rather than as anything about caching.
    final AtKey testByPassCacheAtKey = AtKey()
      ..key = keyEntity
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace
      ..sharedBy = sharedByAtSign
      ..metadata = (Metadata()
        ..ttr = 1000
        ..ttl = 5 * TestConstants.oneMinuteMillis);

    // The key as the RECEIVER addresses it: no sharedWith, because from the
    // receiver's side this is "the key @alice shared with me".
    AtKey receiverView() => AtKey()
      ..key = keyEntity
      ..sharedBy = sharedByAtSign;

    /// Reads the key back from the PUBLISHER's own atServer, decrypted.
    ///
    /// This is the assertion that replaces the sync-event gate. The publisher
    /// holds the shared key, so it can read its own record as plaintext, and
    /// `useRemoteAtServer` makes the read skip local storage entirely — so a
    /// value returned here is a value the atServer really holds.
    Future<String?> onPublisher() async {
      final client = await as(sharedByAtSign);
      try {
        final result = await client.get(testByPassCacheAtKey,
            getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
        return result.value as String?;
      } on AtException {
        // Not there YET is the ordinary state this poll exists to wait out —
        // `put` returning true means the client accepted the write, not that
        // the atServer has it. Measured: the first read after `put` throws
        // `key not found ... does not exist in keystore` every time. Returning
        // null keeps the poll going; a genuine failure still fails the test,
        // at the deadline, quoting the last thing seen.
        return null;
      }
    }

    // ⛔ Restore auto-notify through addTearDown, not a `finally`. The test
    // framework cancels the test future on timeout and a `finally` does not
    // reliably run, which would leave `autoNotify=false` PERSISTED on the
    // publisher's atServer — poisoning every later test that depends on
    // auto-notify (deletion_key's CCD, sharing_key's TTR) in a way that looks
    // like their bug.
    addTearDown(() async {
      try {
        await setAtSignOneAutoNotify(true);
      } catch (_) {
        // Best effort; sharing_key_test and deletion_key_test each force it
        // true in their own setUp for exactly this reason.
      }
    });

    await setAtSignOneAutoNotify(true);

    // --- 1. publish the initial value ------------------------------------
    var publisher = await as(sharedByAtSign);
    expect(await publisher.put(testByPassCacheAtKey, initialValue), true);
    await pollUntil('the publisher stores the initial value', onPublisher,
        initialValue);

    // --- 2. the receiver caches it ---------------------------------------
    // Driven by auto-notify, which is a cross-server hop the client's own sync
    // queue knows nothing about — so wait for the OUTCOME (a cached read)
    // rather than for a fixed number of seconds.
    await as(sharedWithAtSign);
    await pollUntil('the receiver caches the shared value', () async {
      final client = AtClientManager.getInstance().atClient;
      await E2ESyncService.getInstance().syncData(client.syncService);
      final r = await client.get(receiverView());
      return r.metadata?.isCached == true ? r.value as String? : null;
    }, initialValue);

    var receiver = AtClientManager.getInstance().atClient;
    var cached = await receiver.get(receiverView());
    expect(cached.value, initialValue);
    expect(cached.metadata!.isCached, true,
        reason: 'the key was shared with a ttr, so the receiver answers from '
            'its cache — without that there is no cache for bypassCache to '
            'bypass and the rest of this test proves nothing');

    // --- 3. update the value with the receiver deliberately not told -------
    await setAtSignOneAutoNotify(false);

    publisher = await as(sharedByAtSign);
    expect(await publisher.put(testByPassCacheAtKey, updatedValue), true);
    // ⛔ THE GATE THAT USED TO BE WRONG. The precondition for everything below
    // is that the PUBLISHER now holds updatedValue; a sync event naming this
    // key cannot establish it, because the first put emitted one too.
    await pollUntil('the publisher stores the updated value', onPublisher,
        updatedValue);

    // --- 4. the cache is now stale, and a default read still sees it -------
    receiver = await as(sharedWithAtSign);
    await E2ESyncService.getInstance().syncData(receiver.syncService);

    var stale = await receiver.get(receiverView(),
        getRequestOptions: GetRequestOptions()..bypassCache = false);
    expect(stale.value, initialValue,
        reason: 'auto-notify is off, so nothing told the receiver the value '
            'changed. A default read must still answer from the cache — if '
            'this returns the new value the cache was refreshed by something '
            'else and the bypassCache assertion below would pass for free');
    expect(stale.metadata!.isCached, true);

    // --- 5. bypassCache reaches past the cache to the publisher -----------
    var fresh = await receiver.get(receiverView(),
        getRequestOptions: GetRequestOptions()..bypassCache = true);
    expect(fresh.value, updatedValue,
        reason: 'bypassCache makes the receiver atServer perform a fresh '
            'outbound lookup to the publisher, which holds updatedValue — '
            'asserted directly above, not assumed');
    expect(fresh.metadata!.isCached, false,
        reason: 'the answer came from the publisher, not from the cache');

    // --- 6. and that lookup refreshed the cache ---------------------------
    await E2ESyncService.getInstance().syncData(receiver.syncService);
    var refreshed = await receiver.get(receiverView(),
        getRequestOptions: GetRequestOptions()..bypassCache = false);
    expect(refreshed.value, updatedValue,
        reason: 'the bypassCache lookup updates the cached copy, so a default '
            'read now agrees with the publisher');
    expect(refreshed.metadata!.isCached, true);
  }, timeout: Timeout(Duration(minutes: 3)));
}
