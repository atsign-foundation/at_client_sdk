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
/// Every verb runs on an atServer, so values are written and read as plaintext
/// (the client is what encrypts a shared value, and it is not in this path);
/// the `bypassCache` flag is not itself exercised, only the atServer path it
/// also reaches once the cached copy is deleted.
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
  /// Switching rebuilds the client with credentials; `setCurrentAtSign` alone
  /// leaves one that cannot authenticate an APKAM enrollment.
  Future<AtClient> as(String atSign) async {
    final atClientManager = await TestSuiteInitializer.getInstance()
        .switchToAtSign(atSign, namespace, posture: PqPosture.legacy);
    return atClientManager.atClient;
  }

  /// Runs [command] on [client]'s atServer and returns the data it answered
  /// with, or null when the atServer refused because the key is absent.
  ///
  /// Absence is the only refusal turned into a value; every other error
  /// propagates rather than being waited out as "not there yet".
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

    // NOTE: the ttl must outlast several atSign switches and two polls; a key
    // that expires on the publisher first surfaces as an empty answer rather
    // than as anything about caching.
    final AtKey sharedKey = AtKey()
      ..key = keyEntity
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace
      ..sharedBy = sharedByAtSign
      ..metadata = (Metadata()
        ..ttr = 1000
        ..ttl = 5 * TestConstants.oneMinuteMillis);

    String write(String value) =>
        (UpdateVerbBuilder()..atKey = sharedKey..value = value).buildCommand();

    final String cachedKey = (AtKey()
          ..key = keyEntity
          ..sharedWith = sharedWithAtSign
          ..sharedBy = sharedByAtSign
          ..namespace = namespace
          ..metadata = (Metadata()..isCached = true))
        .toString();

    // NOTE: the publisher's key, not the receiver's cached copy of it — naming
    // the cached copy here would answer the lookup from the cache and take the
    // decision away from the atServer.
    final String lookupKey = '$keyEntity.$namespace$sharedByAtSign';

    var publisher = await as(sharedByAtSign);
    expect(await run(publisher, 'config:set:autoNotify=true\n'), 'ok',
        reason: 'without auto-notify nothing fills the cache, and the poll '
            'below would time out saying the value never arrived');

    expect(await run(publisher, write(initialValue)), isNotNull,
        reason: 'the update is answered with a commit id');

    var receiver = await as(sharedWithAtSign);
    await pollUntil('the receiver caches the created value',
        () => run(receiver, 'llookup:$cachedKey\n'), initialValue);
    expect(await run(receiver, 'lookup:$lookupKey\n'), initialValue,
        reason: 'with a cached copy present the receiver atServer answers '
            'from it, and it holds what the publisher wrote');

    publisher = await as(sharedByAtSign);
    expect(await run(publisher, write(updatedValue)), isNotNull);

    // NOTE: auto-notify is asynchronous, so the delete below must wait for the
    // update to reach the cache — a notification arriving after the delete
    // recreates the cached copy, and the final lookup is then answered from a
    // cache holding the right value for the wrong reason.
    receiver = await as(sharedWithAtSign);
    await pollUntil('the receiver caches the updated value',
        () => run(receiver, 'llookup:$cachedKey\n'), updatedValue);

    expect(await run(receiver, 'delete:$cachedKey\n'), isNotNull,
        reason: 'the atServer exempts cached data from its delete rules, so a '
            'receiver may always drop another atSign\'s cached copy');

    expect(await run(receiver, 'llookup:$cachedKey\n'), isNull,
        reason: 'the llookup must find nothing. Anything else means the copy '
            'survived its own deletion, and the lookup below would be '
            'answered from a cache rather than by the publisher');

    expect(await run(receiver, 'lookup:$lookupKey\n'), updatedValue,
        reason: 'with no cached copy the receiver atServer performs a fresh '
            'outbound lookup to the publisher, which holds the updated value');
  }, timeout: Timeout(Duration(minutes: 3)));
}
