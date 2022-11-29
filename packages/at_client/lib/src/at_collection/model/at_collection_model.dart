import 'package:uuid/uuid.dart';

abstract class AtCollectionModel {
  late String? keyId = Uuid().v4();
  late String collectionName = runtimeType.toString();

  Map<String, dynamic> toJson();
}
