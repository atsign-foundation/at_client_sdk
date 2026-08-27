// The nskey surface is @experimental; driving it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/concurrent_clients.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
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

  /// Asserts the recipient has published nothing the resolver could find for
  /// [ns] — at [ns] **and at every ancestor it walks up to**.
  ///
  /// ⛔ Checking only the exact namespace is not the premise these rows need,
  /// and getting that wrong cost a CI red on 2026-08-27. `NskeyResolver` walks
  /// most-specific-first — `a.b.c` then `b.c` then `c` — so a key the recipient
  /// holds at the *app* namespace satisfies a write into any child of it. The
  /// pq pack's siblings do mint the app namespace for this recipient, so a row
  /// whose premise looks only at the leaf is asserting something the pack
  /// falsifies, and it fails at its conclusion rather than at its premise.
  ///
  /// ⚠️ It became reachable only once `resolve` stopped answering from a
  /// remembered miss: before that a second write reused the first one's miss
  /// and never re-walked to the ancestor.
  Future<void> expectRecipientHasNothingFor(
      PublishedNskeyKeyRing ring, String ns) async {
    for (final level in NskeyResolver.candidates(ns)) {
      expect(await ring.currentPublic(recipient, level), isNull,
          reason: 'the premise is that $recipient can be reached at NO level '
              'of "$ns", and "$level" has a published key. The resolver walks '
              'up, so that key serves a write into $ns and there is no cold '
              'start to observe');
    }
  }

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
        writer, recipient, ns, authType,
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

    await expectRecipientHasNothingFor(writerRing, ns);

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

    final written = await writerClient.get(toRecipient('warm'));
    expect(written.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'and it went out on the nskey data path rather than quietly '
            'downgrading — a legacy write would have "succeeded" too, so the '
            'assertion above alone does not distinguish the two');

    // The row's shape arms. The CK is conveyed ONCE as its own record rather
    // than riding inline on the value, which is the whole difference from the
    // monolithic legacy model.
    final ckKid = written.metadata?.appMetadata?.additional?['ckKid'];
    expect(ckKid, isNotNull,
        reason: 'the value cites a content key it does not carry');
    expect(written.metadata?.appMetadata?.additional?.containsKey('sealedKey'),
        isFalse,
        reason: 'and does not carry it inline: at/symmetric/AES/GCM encrypts '
            'the data, at/nskey conveys the key, and those are two records');

    // Sync first: `put` is local-first, so the conveyance record exists on the
    // device before it exists on the atServer, and the lookup below asks the
    // atServer. Without this the row fails as "does not exist in keystore",
    // which reads like the conveyance was never written.
    await E2ESyncService.getInstance()
        .syncData(writerClient.syncService, atSign: writer);

    // Read off the wire rather than through get(), which decrypts — the writer
    // cannot open a conveyance sealed to the recipient, correctly. The
    // metadata is atServer-visible plaintext by design.
    final metaResponse = await writerClient
        .getRemoteSecondary()!
        .executeCommand('llookup:meta:$recipient:$ckKid.__ck.$ns$writer\n',
            auth: true);
    expect(metaResponse, isNotNull);
    final appMetadataRaw = jsonDecode(
        metaResponse!.replaceFirst('data:', '').trim())['appMetadata'];
    expect(appMetadataRaw, isNotNull,
        reason: 'the conveyance must carry its routing metadata on the '
            'atServer, or no reader can tell what it was sealed to');
    final envelope = (appMetadataRaw is String
        ? jsonDecode(utf8.decode(base64Decode(appMetadataRaw)))
        : appMetadataRaw) as Map<String, dynamic>;
    expect(envelope['recipientKind'], 'nskey',
        reason: 'sealed to the NAMESPACE, not to a device — which is what '
            'lets an enrollment approved later read what came before it');
    final advertised =
        await PublishedNskeyKeyRing(writerClient).currentPublic(recipient, ns);
    expect(envelope['nskeyKid'], advertised!.nskeyKid,
        reason: 'and to the generation the recipient actually advertised, '
            'which is the half that says the re-plookup found the current one '
            'rather than any key at all');
  }, timeout: Timeout(Duration(minutes: 5)));

  test(
      'UC-B4.1: with the fallback opted in, the cold write goes legacy and the '
      'first write after the key appears is PQ', () async {
    // The clause's parenthetical, and the arm that made both rows read as
    // specification defects rather than gaps. "Cold start OR THE FALLBACK, IF
    // OPTED-IN, ends for bob without any action from alice" — an app that
    // opened the escape hatch never sees a refusal, so nothing tells it the
    // recipient has arrived. The write simply has to start going out PQ.
    final ns = 'fallback${DateTime.now().microsecondsSinceEpoch}';

    final clients = await ConcurrentClients.open(
        writer, recipient, ns, authType,
        posture: PqPosture.legacy);
    addTearDown(clients.close);
    final writerClient = clients.first;
    final recipientClient = clients.second;

    final writerRing = PublishedNskeyKeyRing(writerClient);
    writerClient.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: writerRing);
    writerClient.getPreferences()!.allowLegacyCryptoFallback = true;
    addTearDown(
        () => writerClient.getPreferences()!.allowLegacyCryptoFallback = false);
    await writerRing.mintAndPublish(ns);

    AtKey toRecipient(String name) => AtKey()
      ..key = name
      ..namespace = ns
      ..sharedWith = recipient
      ..sharedBy = writer;

    await expectRecipientHasNothingFor(writerRing, ns);

    // No refusal — the app opted out of being told. This is also the write
    // that warms the remembered miss.
    expect(await writerClient.put(toRecipient('cold'), 'before'), isTrue);
    final cold = await writerClient.get(toRecipient('cold'));
    expect(cold.metadata?.appMetadata?.providerId, legacyCryptoProviderId,
        reason: 'the fallback is legacy and says so on the record — a '
            'downgrade nobody can see afterwards is the thing being guarded '
            'against');
    expect(cold.metadata?.appMetadata?.additional?['ckKid'], isNull,
        reason: 'and it is the monolithic model: the per-value key rides with '
            'the value rather than being conveyed as its own record');

    // CONTROL. A second write, still before the recipient publishes, is still
    // legacy — so the flip below is the key appearing, not the second write.
    expect(
        await writerClient.put(toRecipient('control'), 'also before'), isTrue);
    expect(
        (await writerClient.get(toRecipient('control')))
            .metadata
            ?.appMetadata
            ?.providerId,
        legacyCryptoProviderId,
        reason: 'control: writing again changes nothing on its own');

    final recipientRing = PublishedNskeyKeyRing(recipientClient);
    recipientClient.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: recipientRing);
    await recipientRing.mintAndPublish(ns);
    await E2ESyncService.getInstance()
        .syncData(recipientClient.syncService, atSign: recipient);

    expect(await writerClient.put(toRecipient('warm'), 'after'), isTrue);
    expect(
        (await writerClient.get(toRecipient('warm')))
            .metadata
            ?.appMetadata
            ?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'the first write after the recipient\'s key appears is PQ '
            'with no flag to flip. The app never touched '
            'allowLegacyCryptoFallback again and saw no refusal to react to, '
            'so if this stayed legacy it would stay legacy forever without '
            'anything saying so');

    // And what the fallback already wrote is untouched.
    expect(
        (await writerClient.get(toRecipient('cold')))
            .metadata
            ?.appMetadata
            ?.providerId,
        legacyCryptoProviderId,
        reason: 'records written under the fallback stay legacy; the flip is '
            'forward-only and re-encrypting is an explicit migration');
  }, timeout: Timeout(Duration(minutes: 5)));
}
