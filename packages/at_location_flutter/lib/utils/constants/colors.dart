import 'package:flutter/material.dart';

class AllColors {
  AllColors._();
  static final AllColors _instance = AllColors._();
  factory AllColors() => _instance;
  // ignore: non_constant_identifier_names
  Color WHITE = const Color(0xFFFFFFFF);
  // ignore: non_constant_identifier_names
  Color INPUT_GREY_BACKGROUND = const Color(0xFFF7F7FF);
  // ignore: non_constant_identifier_names
  Color LIGHT_GREY = const Color(0xFFBEC0C8);
  // ignore: non_constant_identifier_names
  Color DARK_GREY = const Color(0xFF6D6D79);
  // ignore: non_constant_identifier_names
  Color ORANGE = const Color(0xFFFC7A30);
  // ignore: non_constant_identifier_names
  Color PURPLE = const Color(0xFFD9D9FF);
  // ignore: non_constant_identifier_names
  Color LIGHT_BLUE = const Color(0xFFCFFFFF);
  // ignore: non_constant_identifier_names
  Color BLUE = const Color(0xFFC1D9E9);
  // ignore: non_constant_identifier_names
  Color DARK_BLUE = const Color(0xFF036ffc);
  // ignore: non_constant_identifier_names
  Color LIGHT_PINK = const Color(0xFFFED2CF);
  // ignore: non_constant_identifier_names
  Color GREY = const Color(0xFF868A92); // Change it to Hex Later
  // ignore: non_constant_identifier_names
  Color Black = const Color(0xFF000000);
  // ignore: non_constant_identifier_names
  Color GREY_LABEL = const Color(0xFF747481);
  // ignore: non_constant_identifier_names
  Color LIGHT_GREY_LABEL = const Color(0xFFB3B6BE);
  // ignore: non_constant_identifier_names
  Color RED = const Color(0xFFe34040);
  // ignore: non_constant_identifier_names
  Color GREEN = Colors.green;
}

class ContactInitialsColors {
  static Color getColor(String atsign) {
    if (atsign.length == 1) {
      atsign = '$atsign ';
    }
    switch (atsign[1].toUpperCase()) {
      case 'A':
        return const Color(0xFFAA0DFE);
      case 'B':
        return const Color(0xFF3283FE);
      case 'C':
        return const Color(0xFF85660D);
      case 'D':
        return const Color(0xFF782AB6);
      case 'E':
        return const Color(0xFF565656);
      case 'F':
        return const Color(0xFF1C8356);
      case 'G':
        return const Color(0xFF16FF32);
      case 'H':
        return const Color(0xFFF7E1A0);
      case 'I':
        return const Color(0xFFE2E2E2);
      case 'J':
        return const Color(0xFF1CBE4F);
      case 'K':
        return const Color(0xFFC4451C);
      case 'L':
        return const Color(0xFFDEA0FD);
      case 'M':
        return const Color(0xFFFE00FA);
      case 'N':
        return const Color(0xFF325A9B);
      case 'O':
        return const Color(0xFFFEAF16);
      case 'P':
        return const Color(0xFFF8A19F);
      case 'Q':
        return const Color(0xFF90AD1C);
      case 'R':
        return const Color(0xFFF6222E);
      case 'S':
        return const Color(0xFF1CFFCE);
      case 'T':
        return const Color(0xFF2ED9FF);
      case 'U':
        return const Color(0xFFB10DA1);
      case 'V':
        return const Color(0xFFC075A6);
      case 'W':
        return const Color(0xFFFC1CBF);
      case 'X':
        return const Color(0xFFB00068);
      case 'Y':
        return const Color(0xFFFBE426);
      case 'Z':
        return const Color(0xFFFA0087);
      case '@':
        return const Color(0xFFAA0DFE);

      default:
        return const Color(0xFFAA0DFE);
    }
  }
}
