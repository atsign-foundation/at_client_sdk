import 'package:flutter/material.dart';

import '../widgets/authorisation_section_header.dart';
import 'authorisation_page_section.dart';

class SetPinPage extends StatefulWidget {
  const SetPinPage({super.key});

  @override
  SetPinPageState createState() => SetPinPageState();
}

class SetPinPageState extends State<SetPinPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthorisationSectionHeader(
            title: AuthorisationPageSection.setPin.title(context),
            icon: AuthorisationPageSection.setPin.icon,
          ),
        ],
      ),
    );
  }
}
