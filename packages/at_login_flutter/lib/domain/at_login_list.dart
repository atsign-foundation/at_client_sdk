// // import 'package:at_login_flutter/services/at_login_service.dart';
// import 'at_login_model.dart';

// class AtLoginList {
//   List<AtLoginObj?>? list = [];

//   // AtLoginValue? _atKey;

//   // create(AtLoginValue atValue) {
//   //   _atKey = atValue;
//   //   list =
//   //       atValue.value != null && atValue.value != '' && atValue.value != 'null'
//   //           ? atValue.value.split(',')
//   //           : [];
//   //   list!.toSet().toList();
//   // }

//   add(AtLoginObj? atLoginObj) {
//     if (!list!.contains(atLoginObj)) {
//       list!.add(atLoginObj);
//     }
//   }

//   remove(AtLoginObj? atLoginObj) {
//     if (list!.contains(atLoginObj)) {
//       list!.remove(atLoginObj);
//     }
//   }

//   addAll(List<AtLoginObj> atLoginObjs) {
//     for (AtLoginObj atLoginObj in atLoginObjs) {
//       this.add(atLoginObj);
//     }
//   }

//   removeAll(List<AtLoginObj> atLoginObjs) {
//     for (AtLoginObj atLoginObj in atLoginObjs) {
//       this.remove(atLoginObj);
//     }
//   }

//   contains(String? value) {
//     return list!.contains(value);
//   }

//   toString() {
//     return list!.join(',');
//   }

//   // set setKey(AtLoginValue key) {
//   //   this._atKey = key;
//   // }

//   // AtLoginValue? get getKey => _atKey;
// }
