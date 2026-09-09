// The nskey surface is @experimental; driving it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/concurrent_clients.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';

/// UC-A4.4's scheme-decision clause: the opted-in legacy fallback governs a
/// `notify` as well as a `put`.
///
/// ⛔ **This is its own file, and it has to be.** `notify` — unlike `put` —
/// folds a key whose namespace is not under the client's app namespace into the
/// key NAME and substitutes the client's (`NotificationRequestTransformer.
/// _resolveNamespace`). `AtClientManager` caches a client by
/// `(atSign, enrollmentId)`, so a second test in one file gets the FIRST test's
/// client and therefore the first test's app namespace — and every notify in it
/// is silently redirected there.
///
/// A separate file is a separate isolate and therefore a fresh singleton, so
/// the client's app namespace is this file's own.
void main() {
  late String writer;
  late String recipient;
  late String authType;

  setUpAll(() {
    writer = ConfigUtil.getYaml()['atSign']['thirdAtSign'];
    recipient = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    authType = ConfigUtil.getYaml()['authType'];
  });

  /// Asserts the recipient has published nothing the resolver could find for
  /// [ns] — at [ns] **and at every ancestor it walks up to**.
  ///
  /// ⛔ Checking only the exact namespace is not the premise this row needs.
  /// `NskeyResolver` walks most-specific-first, so a key the recipient holds at
  /// an ancestor serves a write into any child of it and there is no cold start
  /// to observe.
  Future<void> expectRecipientHasNothingFor(
      PublishedNskeyKeyRing ring, String ns) async {
    for (final level in NskeyResolver.candidates(ns)) {
      expect(await ring.currentPublic(recipient, level), isNull,
          reason: 'the premise is that $recipient can be reached at NO level '
              'of "$ns", and "$level" has a published key');
    }
  }

  test('UC-A4.4: the opted-in fallback governs a NOTIFY as well as a put',
      () async {
    // ⚠️ The run-unique namespace is the CLIENT's own app namespace, not a
    // child of the shared one. Two reasons:
    //  - notify's `_resolveNamespace` folds a key outside the app namespace
    //    into the key name and substitutes the client's, so a key under some
    //    unrelated namespace would make the two arms differ in the namespace
    //    as well as the verb;
    //  - `NskeyResolver` walks UP, so a child of the shared `e2e_test` is
    //    served by whatever the recipient holds at `e2e_test` — and siblings
    //    in this pack mint exactly that. As the app namespace the walk is one
    //    level deep, on a name nothing else can have published.
    final ns = 'nfb${DateTime.now().microsecondsSinceEpoch}';

    final clients = await ConcurrentClients.open(
        writer, recipient, ns, authType,
        posture: legacyPlusPqProviders);
    addTearDown(clients.close);
    final writerClient = clients.first;

    final writerRing = PublishedNskeyKeyRing(writerClient);
    writerClient.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: writerRing);
    writerClient.getPreferences()!.allowLegacyCryptoFallback = true;
    addTearDown(
        () => writerClient.getPreferences()!.allowLegacyCryptoFallback = false);
    await writerRing.mintAndPublish(ns);

    await expectRecipientHasNothingFor(writerRing, ns);

    AtKey toRecipient(String name) => AtKey()
      ..key = name
      ..namespace = ns
      ..sharedWith = recipient
      ..sharedBy = writer;

    // CONTROL — the put path, same client, same preference, same recipient,
    // same namespace, so the comparison is about the VERB and nothing else.
    //
    // ⚠️ It asserts the put SUCCEEDS and deliberately does not read it back: a
    // legacy shared write resolves a `shared_key` scoped to
    // `(sender, recipient)` and NOT to the namespace, so that key is shared
    // with every other client in this file and a read-back races whichever one
    // last synced it. Success alone discriminates, since without the fallback
    // this put throws.
    expect(await writerClient.put(toRecipient('viaPut'), 'v'), isTrue,
        reason: 'control: the fallback reaches a put with this exact fixture — '
            'without it this call throws rather than returning false');

    final notifyKey = toRecipient('viaNotify');
    final result = await writerClient.notificationService
        .notify(NotificationParams.forUpdate(notifyKey, value: 'v'));

    expect(result.atClientException, isNull,
        reason: 'an app that opened the escape hatch meant its DATA, not one '
            'verb. Before this the same preference produced a legacy put and '
            'an undelivered notification for the same recipient, and the '
            'exception told the app to opt into what it had already opted '
            'into');
    expect(notifyKey.metadata.appMetadata?.providerId, legacyCryptoProviderId,
        reason: 'and it went out under legacy explicitly, stamped on the key '
            'the notification carried — never a silent downgrade');

    // The differential: same verb, same recipient, same namespace, only the
    // preference changed. A build that had simply stopped refusing would pass
    // everything above and fail here.
    writerClient.getPreferences()!.allowLegacyCryptoFallback = false;
    final refused = await writerClient.notificationService.notify(
        NotificationParams.forUpdate(toRecipient('viaNotifyShut'), value: 'v'));
    expect(refused.atClientException, isNotNull,
        reason: 'with the hatch shut the notification must fail cold start '
            'rather than downgrade. The fallback is the app opting in, so an '
            'app that said nothing must not get legacy by accident');
  }, timeout: Timeout(Duration(minutes: 5)));
}
