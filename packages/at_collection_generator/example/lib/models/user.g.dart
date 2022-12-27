// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AtCollectionGenerator
// **************************************************************************

import 'dart:convert';
import 'package:at_client/at_collection/at_collection_model.dart';
import 'package:at_client/at_collection/model/spec/at_collection_model_spec.dart';

class UserCollection extends AtCollectionModel {
  String name;
  String login;
  int number;
  String address;
  UserCollection(
    this.name,
    this.login,
    this.number,
    this.address,
  ) : super(
          collectionName: "User",
        );
  static Future<List<UserCollection>> getAllData() async {
    return (await AtCollectionModel.getAll<UserCollection>());
  }

  static Future<UserCollection> getById(String keyId) async {
    return (await AtCollectionModel.load<UserCollection>(keyId));
  }

  @override
  UserCollection fromJson(String jsonDecodedData) {
    var json = jsonDecode(jsonDecodedData);
    var newModel = UserCollection(
      json['name'],
      json['login'],
      int.parse(json['number']),
      json['address'],
    );
    newModel.id = json['id'];
    return newModel;
  }

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['id'] = id;
    data['collectionName'] = AtCollectionModelSpec.collectionName;
    data['name'] = name;
    data['login'] = login;
    data['number'] = number.toString();
    data['address'] = address;
    return data;
  }
}
