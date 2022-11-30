import 'package:at_client/src/at_collection/model/at_collection_impl.dart';
import 'package:uuid/uuid.dart';

abstract class AtCollectionModel {
  late String keyId;
  late String collectionName;

  AtCollectionModel({required this.collectionName}) {
    keyId = Uuid().v4();
  }

  Map<String, dynamic> toJson();
}
