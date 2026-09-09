import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning;
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

/// The signing and verifying half of the secret-sharing substrate, on its own:
/// [ApkamSigning] and [EnvelopeSigning] sign a payload with this client's APKAM
/// keypair and verify another client's signature against the `_apsk` its
/// enrollment published, without pulling in a whole secret-sharing instance.
///
/// Use `AtClientSecretSharing.forClient` instead when the caller also sends or
/// receives secrets; it mixes these in too.
@experimental
class AtClientEnvelopeSigner with ApkamSigning, EnvelopeSigning {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('AtClientEnvelopeSigner');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings;

  AtClientEnvelopeSigner(
    this.atClient, {
    this.publicKeyCacheSettings = const (
      cacheExpiry: Duration(minutes: 5),
      resetOnLookup: true,
    ),
  });
}
