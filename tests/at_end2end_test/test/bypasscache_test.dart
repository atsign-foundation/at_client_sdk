import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// The receiver's cached copy of another atSign's shared data, and what a read
/// does when that copy is gone.
///
/// **The mechanism.** A key shared with a `ttr` is cached on the RECEIVER's
/// atServer as `cached:@receiver:<key>@publisher`, carried there by the
/// publisher's atServer when auto-notify is on. A `lookup:` is answered from
/// that copy while it exists. Delete the copy and the receiver's atServer has
/// nothing to answer from, so it performs a fresh outbound lookup to the
/// publisher and returns the publisher's current value.
///
/// **Every verb here is executed on an atServer, by both atSigns.** No client
/// `put`, no `get`, no sync: this row is about what two atServers do with a
/// cached copy, and routing it through local storage only adds a second
/// mechanism whose own tests already cover it. Values are therefore written
/// and read as plaintext — the client is what encrypts a shared value, and it
/// is not in this path.
///
/// ⚠️ **THIS TEST'S HISTORY IS RACES, AND EACH REWRITE HAS REMOVED ONE.**
/// It first inferred "the publisher has stored my write" from a sync event,
/// which an earlier put of the same key could satisfy. It then asserted that
/// by polling the publisher's own atServer through a client — and that poll
/// is what failed, in five of the Dart 14 e2e job's last six attempts, always
/// as *waited 0:01:00 for "updated_value-…" and last saw "initial_value-…"*.
/// Writing directly to the publisher's atServer removes the question: the
/// value is there when the verb returns.
///
/// ⚠️ **`autoNotify` is no longer turned off, and that is itself a fix.**
/// Staleness is made by DELETING the cached copy rather than by suppressing
/// the notification that would refresh it. Setting `autoNotify=false`
/// persisted on the shared atSign whenever this test timed out, poisoning
/// every later test that depends on it; `sharing_key_test` and
/// `deletion_key_test` each force it true in their own setUp because of that.
///
/// ⚠️ **What this no longer covers: the `bypassCache` FLAG.** With auto-notify
/// on, cache and origin agree, so a read with the flag and one without return
/// the same value and the flag is unobservable. What is exercised is the
/// atServer path the flag also reaches — an outbound lookup to the publisher —
/// arrived at by emptying the cache.
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

  /// Makes [atSign] the current atSign and returns its client, which is used
  /// only for its authenticated connection to that atSign's atServer.
  ///
  /// Through `switchToAtSign` rather than `setCurrentAtSign`, because a switch
  /// rebuilds the client and a rebuild with no credentials cannot authenticate
  /// an APKAM enrollment.
  Future<AtClient> as(String atSign) async {
    final atClientManager = await TestSuiteInitializer.getInstance()
        .switchToAtSign(atSign, namespace, posture: PqPosture.legacy);
    return atClientManager.atClient;
  }

  /// Runs [command] on [client]'s atServer and returns the data it answered
  /// with, or null when the atServer refused because the key is absent.
  ///
  /// Absence is the one refusal turned into a value: the polls below wait it
  /// out, and the assertions that care distinguish it themselves. Any other
  /// error propagates, because a test that treats every failure as "not there
  /// yet" waits out its own bugs.
  Future<String?> run(AtClient client, String command) async {
    try {
      final response = await client
          .getRemoteSecondary()!
          .executeCommand(command, auth: true);
      return response?.replaceFirst('data:', '').trim();
    } on Object catch (e) {
      final text = '$e';
      if (text.contains('AT0015') ||
          text.toLowerCase().contains('key not found') ||
          text.contains('does not exist')) {
        return null;
      }
      rethrow;
    }
  }

  /// Polls [read] until it returns [expected], then returns. Fails with what
  /// it last saw rather than timing out silently.
  ///
  /// The only wait left, and it is a named condition with a deadline rather
  /// than a delay: the hop that carries a shared value from the publisher's
  /// atServer to the receiver's cache is the one asynchronous step this test
  /// cannot issue a verb for.
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

  test('a read with no cached copy is answered from the publisher', () async {
    int uniqueId = uuid.v4().hashCode;
    String keyEntity = 'test_bypass_cached_key-$uniqueId';
    String initialValue = 'initial_value-$uniqueId';
    String updatedValue = 'updated_value-$uniqueId';

    // A long ttl: this test switches atSigns several times, so a short-lived
    // key can expire on the publisher before the last lookup arrives — which
    // surfaces as the publisher returning nothing rather than as anything
    // about caching.
    final AtKey sharedKey = AtKey()
      ..key = keyEntity
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace
      ..sharedBy = sharedByAtSign
      ..metadata = (Metadata()
        ..ttr = 1000
        ..ttl = 5 * TestConstants.oneMinuteMillis);

    // Built rather than spelled out: the metadata fragment carrying `ttr` is
    // what makes the receiver cache anything, and a hand-written command is a
    // second place for that grammar to be wrong.
    String write(String value) =>
        (UpdateVerbBuilder()..atKey = sharedKey..value = value).buildCommand();

    // The cached copy as it is named ON the receiver's atServer.
    final String cachedKey = (AtKey()
          ..key = keyEntity
          ..sharedWith = sharedWithAtSign
          ..sharedBy = sharedByAtSign
          ..namespace = namespace
          ..metadata = (Metadata()..isCached = true))
        .toString();

    // The key as the RECEIVER looks it up: the publisher's key, not its own
    // cached copy of it, so the atServer decides where to answer from.
    final String lookupKey = '$keyEntity.$namespace$sharedByAtSign';

    // Auto-notify carries each write to the receiver's cache, so it is this
    // test's precondition rather than its subject. Established, not assumed:
    // another test may have left it off.
    var publisher = await as(sharedByAtSign);
    expect(await run(publisher, 'config:set:autoNotify=true\n'), 'ok',
        reason: 'without auto-notify nothing fills the cache, and the poll '
            'below would time out saying the value never arrived');

    // --- 1. the publisher creates the record -----------------------------
    expect(await run(publisher, write(initialValue)), isNotNull,
        reason: 'the update is answered with a commit id');

    // --- 2. the receiver reads what the publisher created ----------------
    var receiver = await as(sharedWithAtSign);
    await pollUntil('the receiver caches the created value',
        () => run(receiver, 'llookup:$cachedKey\n'), initialValue);
    expect(await run(receiver, 'lookup:$lookupKey\n'), initialValue,
        reason: 'with a cached copy present the receiver atServer answers '
            'from it, and it holds what the publisher wrote');

    // --- 3. the publisher updates the record -----------------------------
    publisher = await as(sharedByAtSign);
    expect(await run(publisher, write(updatedValue)), isNotNull);

    // ⛔ THE GATE. Auto-notify is asynchronous, so a delete issued before the
    // update lands would be undone by the notification arriving after it: the
    // cached copy would exist again, the absence assertion below would fail
    // intermittently, and the final lookup would be answered from a cache
    // holding the right value for the wrong reason.
    receiver = await as(sharedWithAtSign);
    await pollUntil('the receiver caches the updated value',
        () => run(receiver, 'llookup:$cachedKey\n'), updatedValue);

    // --- 4. the receiver deletes the cached copy from its atServer --------
    expect(await run(receiver, 'delete:$cachedKey\n'), isNotNull,
        reason: 'the atServer exempts cached data from its delete rules, so a '
            'receiver may always drop another atSign\'s cached copy');

    // --- 5. and the cached copy is gone ----------------------------------
    expect(await run(receiver, 'llookup:$cachedKey\n'), isNull,
        reason: 'the llookup must find nothing. Anything else means the copy '
            'survived its own deletion, and the lookup below would be '
            'answered from a cache rather than by the publisher');

    // --- 6. so the next lookup is answered by the publisher ---------------
    expect(await run(receiver, 'lookup:$lookupKey\n'), updatedValue,
        reason: 'with no cached copy the receiver atServer performs a fresh '
            'outbound lookup to the publisher, which holds the updated value');
  }, timeout: Timeout(Duration(minutes: 3)));
}
