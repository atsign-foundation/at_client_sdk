// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// AtCollectionGenerator
// **************************************************************************

class UserWidget extends AtCollectionModel {
  String name;
  String login;
  int number;
  UserWidget(
    this.name,
    this.login,
    this.number,
  ) : super(
          collectionName: "User",
        );
  static Future<List<UserWidget>> getAllData() async {
    return (await AtCollectionModel.getAll<UserWidget>());
  }

  static Future<UserWidget> getById(String keyId) async {
    return (await AtCollectionModel.load<UserWidget>(keyId));
  }

  @override
  UserWidget fromJson(String jsonDecodedData) {
    var json = jsonDecode(jsonDecodedData);
    var newModel = UserWidget(
      json['name'],
      json['login'],
      int.parse(json['number']),
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
    return data;
  }
}