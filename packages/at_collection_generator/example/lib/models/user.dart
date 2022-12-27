import 'package:at_collection_annotation/at_collection_annotation.dart';

@at_collection_class
class User {
  final String name;
  final String login;
  final int number;
  final String address;

  User(this.name, this.login, this.number, this.address);
}