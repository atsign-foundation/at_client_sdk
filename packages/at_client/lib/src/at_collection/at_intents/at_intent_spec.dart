/// This will help us to get rid of partial success/failure scenarios
abstract class AtIntent {

  /// Will create an intent for the operationType [operationType]
  /// for the key [dataKeyIdentifier]
  /// 
  /// For eg. When we want to update a value w.r.t a key = "myemail"
  /// We will create an intent with [dataKeyIdentifier] = "myemail"
  /// and [operationType] = [IntentOperation.UPDATE]
  Future<IntentModel?> createIntent(
    String dataKeyIdentifier, 
    IntentOperation operationType
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

  /// This will check if the self key and the shared key values are same for [dataKeyIdentifier]
  /// if not, will make all shared keys value same as self key
  /// and return true/false if all shared keys == self key
  Future<bool> checkForDataMismatch(IntentModel _intent);
}

class IntentModel {
  late String uid;
  late String dataKeyIdentifier;
  // late List<IntentItem> items;
  // late Map<AtKey, IntentState> items;
  late IntentOperation intentOperation;
  late DateTime timestamp;

  IntentModel(this.uid, this.dataKeyIdentifier, 
  // this.items, 
  this.intentOperation, this.timestamp);

  IntentModel.fromJson(Map json) {
    uid = json['uid'];
    dataKeyIdentifier = json['dataKeyIdentifier'];
    intentOperation = IntentOperation.values.byName(json['intentOperation']);
    timestamp = DateTime.parse(json['timestamp'].toString());
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['uid'] = uid;
    data['dataKeyIdentifier'] = dataKeyIdentifier;
    data['intentOperation'] = intentOperation.name;
    data['timestamp'] = timestamp.toString();
    return data;
  }
}

enum IntentOperation { UPDATE, 
  // NOTIFY, 
  DELETE 
}
