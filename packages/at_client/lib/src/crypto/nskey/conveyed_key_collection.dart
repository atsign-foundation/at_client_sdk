import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart'
    show NskeyKeyRing;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart'
    show NskeyPrivateFiling;
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart'
    show PqSigningRoot;
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart'
    show PublishedNskeyKeyRing;
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/secret_sharing/key_package_persistence.dart'
    show bindKeyPackageToAtKeys;
import 'package:meta/meta.dart' show experimental;

/// Collects the secrets this enrollment has been sent and files the key
/// material among them into [keysIo]. Returns how many nskey privates were
/// filed.
///
/// The key package is bound to [keysIo] first, so envelopes are read at the
/// address this enrollment advertised rather than at a fresh per-process one,
/// and the sweep runs remote-first, because envelopes reach local storage only
/// via sync and this runs long before a first sync could have completed.
///
/// The sweep consumes the envelopes it finds, so an app subscribing to
/// `receivedSecrets` after the client is built sees no arrival event for
/// anything that was already waiting; the secret itself is in the store, where
/// `waitForSecret` looks first.
@experimental
Future<int> collectConveyedKeyMaterial(AtClient atClient, AtKeysIo keysIo,
    {NskeyKeyRing? ring}) async {
  final atSign = atClient.getCurrentAtSign();
  if (atSign == null) return 0;

  final sharing = AtClientSecretSharing.forClient(atClient);
  bindKeyPackageToAtKeys(sharing,
      keysIo: keysIo, atSign: atSign, enrollmentId: atClient.enrollmentId);
  await sharing.register();
  await sharing.sweepOnce(fromRemote: true);

  final held = sharing.secretStore.listSecrets();
  await PqSigningRoot(atClient, keysIo: keysIo)
      .filePendingPrivate(atSign, held);

  // NOTE: one filing per client, and it must be the ring's — a second filing
  // writes the same keyfile but emits its events where nothing is subscribed.
  final ringFiling = ring is PublishedNskeyKeyRing ? ring.privateFiling : null;
  if (ringFiling != null) return ringFiling.filePending(held);

  return NskeyPrivateFiling(
    keysIo: keysIo,
    atSign: atSign,
    publishedGeneration: (namespace, nskeyKid) async {
      final advertised =
          await (ring ?? PublishedNskeyKeyRing(atClient)).currentPublic(
        atSign,
        namespace,
      );
      // NOTE: matched against every entry, not the advertisement's default kid,
      // which would answer "not published" for the other entry of a two-entry
      // advertisement.
      if (advertised == null || advertised.entryWithKid(nskeyKid) == null) {
        return null;
      }
      return advertised;
    },
  ).filePending(held);
}
