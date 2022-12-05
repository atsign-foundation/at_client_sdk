import 'package:at_client/src/at_collection/model/at_collection_impl.dart';
import 'package:uuid/uuid.dart';

abstract class AtCollectionModel {
  late String keyId;
  late String collectionName;
  final AtCollectionModel Function(String encodedString) convert;

  AtCollectionModel({required this.collectionName, required this.convert}) {
    keyId = Uuid().v4();
  }

  Map<String, dynamic> toJson();
}
