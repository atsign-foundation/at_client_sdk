// import 'package:at_client/at_collection/model/at_collection_model.dart';
// import 'package:at_client/at_collection/model/data_operation_model.dart';
// import 'package:at_client/at_collection/model/object_lifecycle_options.dart';

// abstract class AtCollectionSpec<T extends AtCollectionModel> {

//   void setObjectLifeCycleOptions();

//   // Saves the object. If it is previously shared with bunch of @sign then it does reshare as well.
//   // However if you want the object to be just saved and want to share later then pass share as false
//   // If true is passed for share but the @signs to share with were never given then no share happens.
//   DataOperationModel save({bool share = true, ObjectLifeCycleOptions? options});

//   /// Shares with these additional atSigns. 
//   DataOperationModel shareWith(List<String> atSigns, { ObjectLifeCycleOptions? options});

//   /// unshares object with the list of atSigns supplied. 
//   /// If no @sign is passed it is unshared with every one with whom it was previously shared with
//   DataOperationModel unshare({List<String>? atSigns});

//   // Returns a list of @sign with whom it is previously shared with
//   List<String> getSharedWith();

//   // Deletes this object completely and unshares with everyone with whom it is previosly shared with
//   DataOperationModel delete();

//   toJSON();

//   fromJSON();

//   getId();

//   // static AtCollectiondataModel loadModelById('phone') {
      
//   // }

//   // static AtCollectiondataModel loadModelByIdAndType('phone', Type type) {
      
//   // }

//   // static List<AtCollectiondataModel> loadModelByType(Phone)    
// }