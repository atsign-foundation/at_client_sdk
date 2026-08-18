/// Everything the public API *requires* must be nameable from the barrel.
///
/// This file imports `package:at_client/at_client.dart` and nothing else — no
/// `src/` paths, no `implementation_imports` ignore. That constraint is the
/// test: `CryptoConfig.nskey` is an exported factory with a **required**
/// `NskeyKeyRing`, and the CHANGELOG tells callers to catch
/// `ContentKeyUnavailableException` and to name provider ids. If any of those
/// stops being exported, this file stops compiling.
library;

import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

void main() {
  group('the nskey surface is reachable through the barrel', () {
    test('CryptoConfig.nskey can be constructed by an outside caller', () {
      // An app can only do this if NskeyKeyRing and a concrete ring are both
      // exported — the required parameter type is what made this impossible.
      final NskeyKeyRing ring = InMemoryNskeyKeyRing();
      final config = CryptoConfig.nskey(keyRing: ring);

      expect(config.defaultProviderId, symmetricAesGcmCryptoProviderId);
      expect(config.lookup(nskeyCryptoProviderId), isNotNull);
      expect(config.lookup(symmetricAesGcmCryptoProviderId), isNotNull);
    });

    test('the retryable-read exception is nameable', () {
      final e = ContentKeyUnavailableException('kid', 'not here yet');
      expect(e, isA<AtDecryptionException>());
      expect(e.ckKid, 'kid');
    });

    test('the provider ids and family prefix are nameable', () {
      expect(nskeyCryptoProviderId, startsWith(nskeyProviderFamily));
      expect(legacyCryptoProviderId, isNotEmpty);
      expect(NskeyRecipientKind.nskey, isNotEmpty);
    });

    test('the published key ring and its verifier seam are nameable', () {
      expect(nskeyAdvertisementKey('@alice', 'wavi').key, '__nskey');
      // Named as types rather than constructed: the concrete verifier needs a
      // live AtClient, and importing a mock would cost this file the
      // barrel-only import that is the whole point of it.
      expect(ApkamSignedAdvertisedKeys, isA<Type>());
      expect(AdvertisedKeyVerifier, isA<Type>());
    });

    test('the cold-start surface is nameable', () {
      // An app is told to catch this by name and to ask before composing, so
      // both have to be reachable without an src/ import.
      final e = NamespaceKeyUnavailableException('@bob', 'app_1.my_apps');
      expect(e, isA<AtEncryptionException>());
      expect(e.atSign, '@bob');
      expect(e.namespace, 'app_1.my_apps');
      expect(CryptoRuntime, isA<Type>());
      expect(ReportsReadiness, isA<Type>());
    });

    test('the rollout posture and its key-exchange axis are nameable', () {
      // Both the posture and EnrollmentKeyExchangeMode (an at_auth type,
      // show-narrowed onto this barrel) must be reachable, or the posture's
      // key-exchange value cannot be read or compared by an app that only
      // imports at_client. Composing an enrollment request from it still
      // goes through package:at_auth.
      final preference = AtClientPreference(posture: PqPosture.pqActive);
      expect(preference.posture.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
      expect(preference.disallowLegacyEncryption, true);
    });

    test('the data signing set can be built by an outside caller', () {
      // SigningAlgoType is an at_chops type, show-narrowed onto this barrel
      // for the same reason as EnrollmentKeyExchangeMode: the preference asks
      // for a Set of them and `AtClientImpl.signingAlgoType` hands one back,
      // so without it a caller is asked for a set it cannot build and given a
      // value it cannot name. This file imports at_client and nothing else, so
      // if the export goes, the file stops compiling.
      final preference = AtClientPreference(
          dataSigningKeyAlgorithms: const {SigningAlgoType.mldsa65});

      expect(preference.dataSigningKeyAlgorithms, {SigningAlgoType.mldsa65});
      // Named against a posture whose default is a DIFFERENT algorithm, so
      // the assertion cannot pass on the default it would have taken anyway.
      final pqReady = AtClientPreference(posture: PqPosture.pqReady);
      expect(pqReady.dataSigningKeyAlgorithms, {SigningAlgoType.rsa2048});
    });
  });

  // The group above proves the REQUIRED symbols are reachable — it catches a
  // surface REMOVAL. This one catches the opposite, which is the likelier
  // mistake while the PQ surface is still unpublished and moving: an `src/`
  // file exported by accident. Every change to what a barrel exports is a
  // deliberate, reviewable diff against a checked-in set — on an intended
  // change, update the golden set in the SAME commit; that edit is the review.
  group('the exported file surface is a reviewed golden', () {
    Set<String> exportsOf(String barrel) {
      final file = File('lib/$barrel');
      if (!file.existsSync()) {
        fail('cannot read lib/$barrel — run this from the at_client package '
            'root (dart test does so by default)');
      }
      final re = RegExp("export\\s+'([^']+)'");
      return file
          .readAsLinesSync()
          .map((line) => re.firstMatch(line)?.group(1))
          .whereType<String>()
          .toSet();
    }

    test('at_client.dart exports exactly the reviewed set', () {
      expect(exportsOf('at_client.dart'), _atClientBarrelExports,
          reason: 'The public export surface of at_client.dart changed. If '
              'intentional, update _atClientBarrelExports in the same commit.');
    });

    test('at_client_mixins.dart exports exactly the reviewed set', () {
      expect(exportsOf('at_client_mixins.dart'), _atClientMixinsBarrelExports,
          reason: 'The public export surface of at_client_mixins.dart changed. '
              'If intentional, update _atClientMixinsBarrelExports in the same '
              'commit.');
    });
  });
}

/// The exports of `lib/at_client.dart`, as reviewed. A refactor that narrows or
/// widens this surface updates the set here in the same commit.
const Set<String> _atClientBarrelExports = {
  'package:at_client/src/client/at_client_impl.dart',
  'package:at_client/src/client/at_client_spec.dart',
  'package:at_client/src/client/data_event.dart',
  'package:at_client/src/client/local_secondary.dart',
  'package:at_client/src/client/remote_secondary.dart',
  'package:at_client/src/client/request_options.dart',
  'package:at_client/src/crypto/crypto.dart',
  'package:at_client/src/crypto/crypto_runtime.dart',
  'package:at_client/src/key_stream/key_stream.dart',
  'package:at_client/src/listener/connectivity_listener.dart',
  'package:at_client/src/manager/at_client_manager.dart',
  'package:at_client/src/preference/at_client_preference.dart',
  'package:at_client/src/preference/pq_posture.dart',
  // show-narrowed to EnrollmentKeyExchangeMode: PqPosture.keyExchangeMode
  // holds one, and its per-axis override must be nameable without importing
  // at_auth directly.
  'package:at_auth/at_auth.dart',
  // show-narrowed to SigningAlgoType: AtClientPreference.dataSigningKeyAlgorithms
  // takes a set of them and AtClientImpl.signingAlgoType returns one.
  'package:at_chops/at_chops.dart',
  'package:at_client/src/response/at_notification.dart',
  'package:at_client/src/response/enrollment.dart',
  // show-narrowed to EnrollmentConveyanceException: approve() throws it after
  // a server-side approval whose conveyance refused the advertised package.
  'package:at_client/src/enroll/enrollment_conveyance.dart',
  'package:at_client/src/secret_sharing/algo_ids.dart',
  'package:at_client/src/rpc/at_rpc.dart',
  'package:at_client/src/rpc/at_rpc_types.dart',
  'package:at_client/src/service/enrollment_service.dart',
  'package:at_client/src/service/notification_service.dart',
  'package:at_client/src/service/sync_service.dart',
  'package:at_client/src/telemetry/at_client_telemetry.dart',
  'package:at_client/src/util/at_client_util.dart',
  'package:at_client/src/util/encryption_util.dart',
  'package:at_client/src/util/enroll_list_request_param.dart',
  'package:at_commons/at_commons.dart',
  'package:at_client/src/collections/collections.dart',
  'package:at_client/src/at_collection/collections.dart',
  'package:at_client/src/at_collection/at_collection_model.dart',
  'package:at_client/src/at_collection/at_json_collection_model.dart',
  'package:at_client/src/at_collection/at_collection_model_factory.dart',
};

/// The exports of `lib/at_client_mixins.dart`, as reviewed. The PQ work will
/// narrow this (the `enroll/` activation flows and the signing files are on
/// this surface today); each such move updates the set here in the same commit.
const Set<String> _atClientMixinsBarrelExports = {
  'package:at_client/src/mixins/at_client_bindings.dart',
  'package:at_client/src/mixins/apkam_signing.dart',
  'package:at_client/src/mixins/at_client_envelope_signer.dart',
  'package:at_client/src/mixins/envelope_signing.dart',
  'package:at_client/src/enroll/pq_native_onboard.dart',
  'package:at_client/src/enroll/self_retrofit.dart',
  'package:at_client/src/secret_sharing/secret_sharing.dart',
};
