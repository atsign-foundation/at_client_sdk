import 'package:at_demo_data/at_demo_data.dart';

const int atSignIndex = 30; // @gary

final Map<String, String> atSignData = {
  'atSign': allAtsigns[atSignIndex],
  'cramKey': cramKeyMap[allAtsigns[atSignIndex]] ?? '',
};