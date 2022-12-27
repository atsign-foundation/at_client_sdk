import 'package:at_collection_annotation/at_collection_annotation.dart';

@at_collection_class
class Event {
  final String title;
  final String address;
  final int noOfPeople;
  final bool cancelled;
  final double entryCharge;

  Event(this.title, this.address, this.noOfPeople, this.cancelled, this.entryCharge);
}