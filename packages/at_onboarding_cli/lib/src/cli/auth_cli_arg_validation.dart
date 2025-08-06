const String sppRegex = r'[A-Za-z0-9]{6,16}';
const String sppFormatHelp = 'alphanumeric and 6 to 16 characters long';
const String invalidSppMsg = 'SPP must be $sppFormatHelp';

bool invalidSpp(String test) {
  return RegExp(sppRegex).allMatches(test).first.group(0) != test;
}
