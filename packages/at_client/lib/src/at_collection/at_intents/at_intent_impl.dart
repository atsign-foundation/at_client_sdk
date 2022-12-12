import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/at_collection/at_intents/at_intent_spec.dart';
import 'package:uuid/uuid.dart';

class AtIntentImpl implements AtIntent {
  static final AtIntentImpl _singleton = AtIntentImpl._internal();
  AtIntentImpl._internal();

  factory AtIntentImpl() {
    return _singleton;
  }

  @override
  Future<IntentModel?> createIntent(String dataKeyIdentifier, IntentOperation operationType) async {
    try {
      var _newIntent = IntentModel(Uuid().v4(), dataKeyIdentifier, operationType, DateTime.now());
      var _atKey = getAtKey('${_newIntent.uid}.intent');
          //  AtKey.local('${_newIntent.uid}.intent', AtClientManager.getInstance().atClient.getCurrentAtSign()!).build();
      var _res =  await AtClientManager.getInstance()
          .atClient
          .put(
            _atKey,
            jsonEncode(_newIntent.toJson())
          );

      print('_res $_newIntent');
      return _res ? _newIntent : null;
    } catch(e) {
      print("Error in createIntent $createIntent");
      return null;
    }
  }

  @override
  Future<void> removeIntent(String intentId) async {
    var records = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: intentId);

    for (var key in records) {
      var res = await AtClientManager.getInstance().atClient.delete(key);
      print('delte: $res');
    }
  }

  @override
  Future<void> checkForPendingIntents() async {
    var records = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: '.intent');

    for (var key in records) {
      try{
        var atValue = await AtClientManager.getInstance().atClient.get(key);
        var _intentModel = IntentModel.fromJson(jsonDecode(atValue.value));
        var _intentOperation = await checkForDataMismatch(_intentModel);
        if(_intentOperation){
          var _removeIntent = await AtClientManager.getInstance().atClient.delete(key);
          print("_removeIntent opeartion $_removeIntent");
        }
        print("tempModel $_intentModel");
      }
      catch(e){
        print("error in checkForUpdateIntent loop $e");
      }
    }
  }

  /// compare all keys with self key to check if they are same or not, 
  /// else make them same
  @override
  Future<bool> checkForDataMismatch(IntentModel _intent) async {
    try {
      String dataKeyIdentifier = _intent.dataKeyIdentifier;
      IntentOperation operationType = _intent.intentOperation;

      var rectifyDataMismatch = true;

      var records = await AtClientManager.getInstance()
          .atClient
          .getAtKeys(regex: '$dataKeyIdentifier');

      if(operationType == IntentOperation.DELETE){
        for (var key in records) {
          var _delete = await AtClientManager.getInstance().atClient.delete(key);
          if(!_delete){
            rectifyDataMismatch = false;
          }
        }

        return rectifyDataMismatch;
      }

      var selfKeyAtValue = await AtClientManager.getInstance().atClient.get(
        records.where((element) => element.sharedWith == null).first
      );

      /// remove the self key from [records]
      records.removeWhere((element) => element.sharedWith == null);

      String selfKeyValue = selfKeyAtValue.value;

      for (var key in records) {
        var sharedKeyAtValue = await AtClientManager.getInstance().atClient.get(key);
        print('sharedKeyAtValue $sharedKeyAtValue');
        if(selfKeyValue != sharedKeyAtValue.value) {
          if(operationType == IntentOperation.UPDATE){
            var _putOperation = await AtClientManager.getInstance()
              .atClient
              .put(
                key,
                selfKeyValue /// no need to jsonEncode this value
              );
            print('_putOperation $_putOperation');
            if(!_putOperation){
              rectifyDataMismatch = false;
            }
          }
        }
      }

      return rectifyDataMismatch;
    } catch(e){
      print("Error in checkForDataMismatch $e");
      return false;
    }
    
  }

  deleteAllIntents() async {
    var records = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: '.intent');

    for (var key in records) {
      var res = await AtClientManager.getInstance().atClient.delete(key);
      print("delete res $res");
    }
  }
}



/// key : value : complete/incomplete
class IntentItem {
  late AtKey key;
  // late dynamic value;
  late IntentState state;

  IntentItem(this.key,
  //  this.value, 
   this.state);
}

enum IntentState { DONE, NOTSTARTED }

getAtKey(String key, {String? sharedWith}) {
    return AtKey()
      ..key = key
      // ..namespace = nameSpace
      ..metadata = Metadata()
      ..metadata!.ttr = -1
      ..sharedWith = sharedWith
      // file transfer key will be deleted after 15 days
      ..metadata!.ttl = 1296000000 // 1000 * 60 * 60 * 24 * 15
      ..sharedBy = AtClientManager.getInstance().atClient.getCurrentAtSign();
  }