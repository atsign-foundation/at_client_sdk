import 'package:flutter/material.dart';

/// default colors for message bubbles
class CustomColors {
  static const Color incomingMessageColor = Color(0xffF1F2F3);
  static const Color outgoingMessageColor = Color(0xffC0D9EA);
  static const Color defaultColor = Color(0xFFF05E3E);
}

/// randomize the avatar background color based on alphabet
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
