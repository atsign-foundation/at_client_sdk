import 'package:at_demo_data/at_demo_data.dart';

const int atSign1Index = 30; // @gary
const int atSign2Index = 31; // @xavier

final Map<String, String> atSign1Data = {
  'atSign': allAtsigns[atSign1Index],
  'cramKey': cramKeyMap[allAtsigns[atSign1Index]] ?? '',
};

final Map<String, String> atSign2Data = {
  'atSign': allAtsigns[atSign2Index],
  'cramKey': cramKeyMap[allAtsigns[atSign2Index]] ?? '',
};