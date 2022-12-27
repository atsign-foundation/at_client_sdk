import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/at_collection_model.dart';

import 'package:at_collection_annotation/at_collection_annotation.dart';
part 'user.g.dart';

@at_collection_class
class User {
  final String name;
  final String login;
  final int number;

  User(this.name, this.login, this.number);
}