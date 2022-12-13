import 'package:at_client/src/at_collection/model/intent_model.dart';

/// This will help us to get rid of partial success/failure scenarios
abstract class AtIntent {

  /// Will create an update intent
  /// for the key [dataKeyIdentifier]
  /// 
  /// For eg. When we want to update a value w.r.t a key = "myemail"
  /// We will create an update intent with [dataKeyIdentifier] = "myemail"
  Future<IntentUpdateModel?> createUpdateIntent(
    String dataKeyIdentifier, 
    String value,
  );

  /// Will create an share intent
  /// for the key [dataKeyIdentifier] and [atsigns]
  /// 
  /// For eg. When we want to share data of a key = "myemail"
  /// We will create a share intent with [dataKeyIdentifier] = "myemail" 
  /// and [atsigns] = ['atsign1', 'atsign2', 'etc'...]
  Future<IntentShareModel?> createShareIntent(
    String dataKeyIdentifier, 
    List<String> atsigns,
  );

  /// Will create a delete intent for the key [dataKeyIdentifier]
  /// 
  /// For eg. When we want to delete data of a key = "myemail"
  /// We will create a delete intent with [dataKeyIdentifier] = "myemail" 
  Future<IntentDeleteModel?> createDeleteIntent(
    String dataKeyIdentifier, 
  );

  /// Will remove the intent with id [intentId]
  /// Called after all of the intent's operation are complete
  /// 
  /// For eg. When we want to update a value w.r.t a key = "myemail"
  /// We will create an intent with [dataKeyIdentifier] = "myemail"
  /// and [operationType] = [IntentOperation.UPDATE]
  /// and [intentId] = "123.intent"
  /// 
  /// After the update operation is successful for all keys w.r.t "myemail"
  /// we call the removeIntent with [intentId] = "123.intent"
  Future<void> removeIntent(String intentId);

  /// This will look for any intent data in our storage
  /// For each intent we find we check the values of all values of the [dataKeyIdentifier]
  /// i.e check if the self key and the shared key for the [dataKeyIdentifier] are same
  /// if not, we make all shared keys same as the self key
  /// and delete the intent
  Future<void> checkForPendingIntents();

  /// This will check if the [_intentUpdateModel.value] is present in 
  /// all self key and the shared key values for [dataKeyIdentifier]
  /// if not, it will make all keys value same as the [_intentUpdateModel.value]
  /// and return true/false if all [keys.value] == [_intentUpdateModel.value]
  Future<bool> resumeUpdateIntent(IntentUpdateModel _intentUpdateModel);

  /// This will check if the [_intentShareModel.id]' shared keys copies
  /// are present for all [_intentShareModel.atsigns] 
  /// if not, it will create all shared keys for the missing [_intentShareModel.atsigns]
  /// and return true/false if all [_intentShareModel.atsigns] exists
  Future<bool> resumeShareIntent(IntentShareModel _intentShareModel);

  /// This will check if the [_intentDeleteModel.id] keys are present 
  /// all self key and the shared keys
  /// if it exists, then it will delete all [_intentDeleteModel.id] shared and self keys
  Future<bool> resumedeleteIntent(IntentDeleteModel _intentDeleteModel);
}


