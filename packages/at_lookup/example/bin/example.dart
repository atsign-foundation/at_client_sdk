import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';

/// Runs a few verbs against @alice's atServer through at_lookup.
///
/// It needs a running atServer for @alice and an [AtAuthenticator] that
/// authenticates as @alice: at_auth builds one from a keyfile with
/// `authenticatorFor`, or from a CRAM secret with `authenticatorForCramSecret`.
Future<void> main() async {
  final atLookupImpl = AtLookUp.withSecureSocket(
    atSign: '@alice',
    rootDomain: const AtRootDomain('root.atsign.org', 64),
    authenticator: _authenticator,
    transport: secureSocketTransport(SecureSocketConfig()),
    secondaryAddressFinder:
        CacheableSecondaryAddressFinder('root.atsign.org', 64),
  );

  /// To update a key into secondary server
  //Build update verb builder
  var updateVerbBuilder = UpdateVerbBuilder()
    ..atKey =
        (AtKey.shared('phone', sharedBy: '@alice')..sharedWith('@bob')).build()
    ..value = '+1 889 886 7879';

  // Sends update command to the secondary server
  await atLookupImpl.executeVerb(updateVerbBuilder);

  /// To lookup a value of a key sharedBy a specific atSign
  var lookupVerbBuilder = LookupVerbBuilder()
    ..atKey = AtKey.shared('phone', sharedBy: '@alice').build()
    ..auth = true;
  await atLookupImpl.executeVerb(lookupVerbBuilder);

  /// To lookup a value of a public key
  var pLookupBuilder = PLookupVerbBuilder()
    ..atKey = AtKey.shared('phone', sharedBy: '@alice').build();
  await atLookupImpl.executeVerb(pLookupBuilder);

  /// To retrieve the value of key created by self.
  var lLookupVerbBuilder = LLookupVerbBuilder()
    ..atKey =
        (AtKey.shared('phone', sharedBy: '@alice')..sharedWith('@bob')).build();
  await atLookupImpl.executeVerb(lLookupVerbBuilder);

  ///To remove a key from secondary server
  var deleteVerbBuilder = DeleteVerbBuilder()
    ..atKey =
        (AtKey.shared('phone', sharedBy: '@alice')..sharedWith('@bob')).build();
  await atLookupImpl.executeVerb(deleteVerbBuilder);

  /// To retrieve keys from the secondary server
  var scanVerbBuilder = ScanVerbBuilder();
  await atLookupImpl.executeVerb(scanVerbBuilder);

  ///To notify key to another atSign
  var notifyVerbBuilder = NotifyVerbBuilder()
    ..atKey =
        (AtKey.shared('phone', sharedBy: '@alice')..sharedWith('@bob')).build();
  await atLookupImpl.executeVerb(notifyVerbBuilder);

  ///To retrieve the notifications received
  var notifyListVerbBuilder = NotifyListVerbBuilder();
  await atLookupImpl.executeVerb(notifyListVerbBuilder);

  await atLookupImpl.stop();
}

/// Stands in for the authenticator at_auth builds.
Future<bool> _authenticator(AtCommandExecutor executor) =>
    throw UnimplementedError('use an AtAuthenticator from at_auth');
