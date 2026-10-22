import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';

/// The example below demonstrate on how to use at_lookup package to interact with secondary server
/// to execute the verbs.
/// NOTE: Running this example would result in an exception. The At_lookup package would require
/// a secondary running.
void main() async {
  var atLookupImpl = AtLookUp.withSecureSocket(
    atSign: '@alice',
    rootDomain: const AtRootDomain('root.atsign.com', 64),
    // A real caller builds this from its credential with at_auth, for example
    // authenticatorForPrivateKey() or authenticatorForChops().
    authenticator: (executor) async =>
        throw UnimplementedError('build an AtAuthenticator with at_auth'),
    transport: secureSocketTransport(SecureSocketConfig()),
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
}
