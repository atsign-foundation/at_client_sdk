import 'package:at_commons/src/verb/abstract_verb_builder.dart';

/// Local lookup verb builder generates a command to lookup value of [atKey] stored in the secondary server.
///
/// e.g llookup key shared with alice
///
/// * Lookup phone number available only to alice
///
/// * When sharedWith is populated, throws [InvalidAtKeyException] if isPublic or isLocal is set to true
///```dart
///    var builder = LLookupVerbBuilder()..sharedWith = '@alice'..key=’phone’..atSign=’bob’;
///```
///
/// e.g llookup public key
///
/// * Lookup email value that is available to everyone
///
/// * When isPublic is set to true, throws [InvalidAtKeyException] if isLocal is set to true or sharedWith is populated
///```dart
/// var builder = LLookupVerbBuilder()..key=’email’..atSign=’bob’..isPublic = true;
///```
/// e.g llookup private key
///
/// * Lookup a credit card number that is accessible only by Bob
///```
///    var builder = LLookupVerbBuilder()..sharedWith = '@bob'..key=’credit_card’..atSign=’bob’;
///```
///
/// e.g. llookup a local key
/// * Lookup a local key that is accessible only by bob
///
/// * When isLocal is set to true, throws [InvalidAtKeyException] if isPublic or isCached is set true or sharedWith is populated
///```dart
///    var builder = LLookupVerbBuilder()..key = 'password'..sharedBy = '@bob'..isLocal = true;
///```
///
/// e.g. llookup a cached key
/// * Lookup a cached key that shared by alice to bob
///
/// * When isCached is set to true, throws [InvalidAtKeyException] if isLocal is set to true
///
///```dart
/// var builder = LLookupVerbBuilder()
///               ..isCached = true
///               ..sharedWith = '@bob'
///               ..key = 'phone'
///               ..sharedBy = '@alice'
///```
///
/// e.g. llookup a cached public key
/// * Lookup a cached key that is public key of alice
///```dart
/// var builder = LLookupVerbBuilder()
///               ..isCached = true
///               ..isPublic = true
///               ..key = 'aboutMe'
///               ..sharedBy = '@alice'
///```
class LLookupVerbBuilder extends AbstractVerbBuilder {
  String? operation;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('llookup:');
    if (operation != null) {
      serverCommandBuffer.write('$operation:');
    }
    serverCommandBuffer.write('${buildKey()}\n');
    return serverCommandBuffer.toString();
  }

  @override
  bool checkParams() {
    return atKey.key.isNotEmpty && atKey.sharedBy != null;
  }

  String buildKey() {
    validateKey();
    return atKey.toString();
  }
}
