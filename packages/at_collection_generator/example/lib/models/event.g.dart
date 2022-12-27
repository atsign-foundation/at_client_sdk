// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AtCollectionGenerator
// **************************************************************************

import 'dart:convert';
import 'package:at_client/at_collection/at_collection_model.dart';
import 'package:at_client/at_collection/model/spec/at_collection_model_spec.dart';

class EventCollection extends AtCollectionModel {
  String title;
  String address;
  int noOfPeople;
  bool cancelled;
  double entryCharge;

  EventCollection(
    this.title,
    this.address,
    this.noOfPeople,
    this.cancelled,
    this.entryCharge,
  ) : super(
          collectionName: "Event",
        );

  static Future<List<EventCollection>> getAllData() async {
    return (await AtCollectionModel.getAll<EventCollection>());
  }

  static Future<EventCollection> getById(String keyId) async {
    return (await AtCollectionModel.load<EventCollection>(keyId));
  }

  @override
  EventCollection fromJson(String jsonDecodedData) {
    var json = jsonDecode(jsonDecodedData);
    var newModel = EventCollection(
      json['title'],
      json['address'],
      int.parse(json['noOfPeople']),
      json['result'] == 'true',
      double.parse(json['entryCharge']),
    );
    newModel.id = json['id'];
    return newModel;
  }

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['id'] = id;
    data['collectionName'] = AtCollectionModelSpec.collectionName;
    data['title'] = title;
    data['address'] = address;
    data['noOfPeople'] = noOfPeople.toString();
    data['cancelled'] = cancelled.toString();
    data['entryCharge'] = entryCharge.toString();
    return data;
  }
}
