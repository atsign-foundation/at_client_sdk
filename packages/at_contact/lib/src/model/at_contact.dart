// ignore_for_file: constant_identifier_names

import 'package:at_contact/src/service/util_service.dart';

class AtContact {
  String? atSign;

  //ContactType.Individual
  ContactType? type;

  // [ContactCategory.Other];
  List<ContactCategory>? categories;

  //default false
  bool? favourite;

  //default false
  bool? blocked;

  List<String>? personas = [];

  // Additional/Optional context(Keys)
  Map<dynamic, dynamic>? tags;

// Ex:: com.atSign.AtContact
  String? clazz;

// version default '1'
  int? version;

  DateTime? createdOn;

  DateTime? updatedOn;

  AtContact(
      {this.type,
      this.atSign,
      this.categories,
      this.favourite,
      this.blocked,
      this.personas,
      this.tags,
      this.clazz,
      this.version,
      this.createdOn,
      this.updatedOn}) {
    // atSign ??='@atSign';
    type ??= ContactType.Individual;
    categories ??= [ContactCategory.Other];
    favourite ??= false;
    blocked ??= false;
    clazz ??= 'com.atSign.AtContact';
    version ??= 1;
    createdOn ??= DateTime.now();
    updatedOn ??= DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'atSign': atSign,
      'type': type.toString(),
      'categories': categories!.map((e) => e.toString()).toList(),
      'favourite': favourite,
      'blocked': blocked,
      'personas': personas,
      'tags': tags,
      'clazz': clazz,
      'version': version,
      'createdOn': UtilServices.dateToString(createdOn!),
      'updatedOn': UtilServices.dateToString(updatedOn!),
    };
  }

  AtContact.fromJson(Map json) {
    atSign = json['atSign'];
    type = ContactType.values
        .firstWhere((element) => element.toString() == json['type']);
    categories = (json['categories'] as List<dynamic>?)
        ?.cast<String>()
        .map((value) => ContactCategory.values
            .firstWhere((element) => element.toString() == value))
        .toList();
    favourite = json['favourite'];
    blocked = json['blocked'];
    personas = (json['personas'] as List<dynamic>?)?.cast<String>();
    tags = json['tags'];
    clazz = json['clazz'];
    version = json['version'];
    createdOn = UtilServices.stringToDate(json['createdOn']);
    updatedOn = UtilServices.stringToDate(json['updatedOn']);
  }

  @override
  String toString() {
    return 'AtContact{atSign: $atSign, type: $type, categories: $categories, favourite: $favourite, blocked: $blocked, personas: $personas, tags: $tags, clazz: $clazz, version: $version}';
  }
}

enum ContactType { Individual, Institute, Other }

enum ContactCategory { Family, Friend, Coworker, Other }
