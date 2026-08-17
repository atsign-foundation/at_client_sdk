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
/// Three things have to line up for a conveyed private to reach the keyfile,
/// and the order below is the order they depend on each other in.
///
/// **The key package must be the one this enrollment advertised.** A sender
/// addresses an envelope to the `kpid` it read from the enrollment record;
/// left to itself the registration mixin generates a fresh enc keypair per
/// process, so the client would scan for an address nobody ever writes to.
/// Binding it to `AtKeys` reunites the client with the half
/// `enrollmentKeyPackageBuilder` filed there at enrollment.
///
/// **Something has to sweep.** The `SecretStore` is in memory and its only
/// populator is the sweep, so a client that never sweeps reads an empty store
/// however much has been conveyed to it. Remote rather than local because
/// envelopes reach local storage only via sync, and this runs long before a
/// first sync could have completed.
///
/// **Then the crypto layer files its own material**, moving it out of a
/// transit buffer that does not survive the process and into the keyfile,
/// which does.
///
/// One consequence worth knowing: the sweep consumes and deletes the envelopes
/// it finds, so an app that subscribes to `receivedSecrets` after the client is
/// constructed will not see an arrival event for anything that was waiting at
/// start. The secret itself is in the store, which is where `waitForSecret`
/// looks first, so the pull flow is unaffected.
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

  // ⚠️ **One filing per client, and it must be the ring's.** This used to build
  // its own unconditionally, which made every client hold two: the one the ring
  // exposes and this one, which is the one that actually files. Nothing broke
  // while filing was write-only — both wrote the same keyfile — but the moment
  // a filing gained an observable event, the object emitting it was not the
  // object anything could reach. Measured live: a notification parked correctly
  // for a private that was then filed successfully, and was never re-driven,
  // because the subscription was on the ring's filing and the announcement came
  // from this one.
  final ringFiling = ring is PublishedNskeyKeyRing ? ring.privateFiling : null;
  if (ringFiling != null) return ringFiling.filePending(held);

  return NskeyPrivateFiling(
    keysIo: keysIo,
    atSign: atSign,
    publishedGeneration: (namespace, nskeyKid) async {
      // Only the current generation can be checked this way, and an arriving
      // private is often an older one — that is ordinary, and the filer treats
      // an absent public half as "no opinion" rather than a rejection. What
      // this does catch is the case worth catching: a private claiming to be
      // the generation peers are sealing to right now, which is not it.
      final advertised =
          await (ring ?? PublishedNskeyKeyRing(atClient)).currentPublic(
        atSign,
        namespace,
      );
      if (advertised == null || advertised.nskeyKid != nskeyKid) return null;
      return advertised;
    },
  ).filePending(held);
}
