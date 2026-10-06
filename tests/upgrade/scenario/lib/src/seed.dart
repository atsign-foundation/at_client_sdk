import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_commons/atsign.dart' show AtsignString;

import 'catalogue.dart';
import 'lifecycle.dart';

/// Writes everything the upgrade check reads back: each record in
/// [catalogue], an item shared with [peer], a read receipt for the item
/// [peer] shared with [me], and a received notification. Leaves the store
/// synced.
///
/// Returns the preconditions this run met, for the caller to check before it
/// trusts anything read from the store afterwards.
Future<Map<String, Object?>> seed(AtClient client,
    {required String me,
    required String peer,
    required String namespace}) async {
  for (final record in catalogue) {
    await client.put(
        record.keyFor(me: me, peer: peer, namespace: namespace), record.value);
  }

  final items = await client.collection<String>(
      collectionNamespace(namespace), itemLifetime);
  await items
      .create(obj: 'my item', id: myItemId, sharedWith: {peer.toAtsign()});

  final facts = <String, Object?>{
    'syncedBeforeReceipt': await syncUntilInSync(client),
  };
  // NOTE: the whole collection, filtered here: at_client 3.14.0's id-scoped
  // scan cannot match a received item's `cached:@me:` key.
  final theirs = (await items.getItems())
      .where((i) => i.id == peerItemId && i.owner == peer.toAtsign())
      .toList();
  facts['peerItemSeen'] = theirs.length == 1;
  if (theirs.length == 1) await theirs.single.markReadByMe();

  facts['notificationReceived'] =
      await notifySelfAndWait(client, me: me, namespace: namespace);
  facts['synced'] = await syncUntilInSync(client);
  return facts;
}

/// Writes [pending] without waiting for it to reach the atServer.
Future<void> writePending(AtClient client,
        {required String me,
        required String peer,
        required String namespace}) =>
    client.put(pending.keyFor(me: me, peer: peer, namespace: namespace),
        pending.value);
