import 'package:flutter/material.dart';

/// Colors used in the package
class ColorConstants {
  static const Color scaffoldColor = Colors.white;
  static const Color fontPrimary = Color(0xff131219);
  static const Color fontSecondary = Color(0xff868A92);
  static const Color dividerColor = Color(0xFF707070);
  static const Color appBarColor = Colors.white;
  static const Color fadedText = Color(0xFF6D6D79);
  static const Color dullText = Color(0xFFBEC0C8);
  static const Color greyText = Color(0xFF868A92);
  static const Color blueText = Color(0xFF03A2E0);
  static const Color redText = Color(0xFFF05E3E);
  static const Color inputFieldColor = Color(0xFFF7F7FF);
  static const Color appBarCloseColor = Color(0xff03A2E0);
  static const Color orangeColor = Color(0xffF05E3F);
  static const Color listBackground = Color(0xffF7F7FF);
  static const Color fadedbackground = Color(0xFFFDF9F9);
  static const Color mildGrey = Color(0xFFE4E4E4);
  static const Color fadedGreyBackground = Color(0xFFDBDBDB);
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
