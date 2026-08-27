// The nskey surface is @experimental; driving it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/concurrent_clients.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

/// Cold start ends the moment the recipient publishes — UC-B4.1 and UC-B4.4.
///
/// `nskey_recipient_not_ready_test.dart` holds the refusal; this holds the
/// recovery, which is the arm that was silently false.
///
/// **What makes it hard to test by accident.** The refusal itself warms a
/// negative cache: `NskeyResolver` remembers misses, and a client builds one
/// resolver for its whole life, so the sender's own failed write is what made
/// it blind to the recipient afterwards. Measured live 2026-08-27 — the write,
/// the readiness query and the exception text were all wrong together, and
/// nothing short of a new client could clear it. `resolve` no longer answers
/// null on the strength of a remembered miss.
///
/// So the first `put` below is not setup. It is the thing that creates the
/// state under test, and a version of this file without it passes against a
/// build that still has the defect.
///
/// ⛔ **The writer is the THIRD atSign, deliberately, and this file is separate
/// from its sibling for the same reason.** A successful nskey write publishes
/// the writer's signing root, and `retrofit_e2e_test.dart` asserts that
/// `firstAtSign` has **no** published root — that row is about the root being
/// created by the retrofit. Written as a second test inside the sibling file it
/// took two unrelated rows down with it, and the symptom was a failure in
/// `retrofit_e2e_test.dart` naming a virtualenv that had in fact been recycled.
/// `thirdAtSign` is consumed by no other file in this package. The recipient
/// stays `secondAtSign`, whose part here — publishing an nskey for a
/// run-unique namespace — is additive and is what its neighbours already do.
void main() {
  late String writer;
  late String recipient;
  late String authType;

  setUpAll(() {
    writer = ConfigUtil.getYaml()['atSign']['thirdAtSign'];
    recipient = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    authType = ConfigUtil.getYaml()['authType'];
  });

  test(
      'UC-B4.4: the recipient publishing is the whole trigger, even after a '
      'refusal has been cached', () async {
    // Run-unique: the recipient must genuinely never have used or authorised
    // this namespace, or the refusal that warms the cache never happens.
    final ns = 'recover${DateTime.now().microsecondsSinceEpoch}';

    final clients = await ConcurrentClients.open(
        writer, recipient, TestConstants.namespace, authType,
        posture: PqPosture.legacy);
    addTearDown(clients.close);
    final writerClient = clients.first;
    final recipientClient = clients.second;

    final writerRing = PublishedNskeyKeyRing(writerClient);
    writerClient.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: writerRing);
    // The writer's own key, so a refusal below is the recipient's absence and
    // not the writer's — UC-A3.3 is a different row.
    await writerRing.mintAndPublish(ns);

    AtKey toRecipient(String name) => AtKey()
      ..key = name
      ..namespace = ns
      ..sharedWith = recipient
      ..sharedBy = writer;

    expect(await writerRing.currentPublic(recipient, ns), isNull,
        reason: 'the premise: the recipient has published nothing for this '
            'namespace. If they had, the refusal below would not happen and '
            'this row would assert nothing about a remembered miss');

    // The refusal — and the call that warms the negative cache.
    await expectLater(
        writerClient.put(toRecipient('cold'), 'before the recipient is ready'),
        throwsA(isA<NamespaceKeyUnavailableException>()),
        reason: 'a share toward an atSign with no published nskey must refuse '
            'rather than downgrade. This refusal is what makes everything '
            'below about a REMEMBERED miss rather than about a first look');

    // The recipient becomes reachable. Nothing tells the writer.
    final recipientRing = PublishedNskeyKeyRing(recipientClient);
    recipientClient.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: recipientRing);
    await recipientRing.mintAndPublish(ns);
    await E2ESyncService.getInstance()
        .syncData(recipientClient.syncService, atSign: recipient);

    // CONTROL. A key ring that never probed, on the writer's own client and
    // over the same connection. It can stay green while every assertion below
    // goes red, which is what makes it a control rather than a restatement:
    // it separates "the recipient published" from "the writer can see it".
    expect(
        await PublishedNskeyKeyRing(writerClient).currentPublic(recipient, ns),
        isNotNull,
        reason: 'control: the recipient really is reachable, now, over this '
            'connection. Without it a red below could equally mean they never '
            'published and the whole file would be measuring the wrong thing');

    expect(await CryptoRuntime(writerClient).isReadyFor(recipient, ns), isTrue,
        reason: 'an app asking "can I reach them yet" is asking about now, so '
            'the readiness query must not answer from a remembered miss');

    // The clause: the recipient's key appearing is the whole trigger.
    expect(await writerClient.put(toRecipient('warm'), 'after they are ready'),
        isTrue,
        reason: 'the FIRST write after the recipient\'s key appears must go '
            'out, with no flag to flip and nothing for the sender to do. The '
            'writer took no action between the refusal and this call except '
            'to try again, which is what an app does');

    expect(
        (await writerClient.get(toRecipient('warm')))
            .metadata
            ?.appMetadata
            ?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'and it went out on the nskey data path rather than quietly '
            'downgrading — a legacy write would have "succeeded" too, so the '
            'assertion above alone does not distinguish the two');
  }, timeout: Timeout(Duration(minutes: 5)));
}
