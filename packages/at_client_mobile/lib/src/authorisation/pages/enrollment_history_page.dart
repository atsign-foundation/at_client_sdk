import 'package:flutter/material.dart';

import '../widgets/authorisation_section_header.dart';
import 'authorisation_page_section.dart';

class EnrollmentHistoryPage extends StatefulWidget {
  const EnrollmentHistoryPage({super.key});

  @override
  EnrollmentHistoryPageState createState() => EnrollmentHistoryPageState();
}

class EnrollmentHistoryPageState extends State<EnrollmentHistoryPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthorisationSectionHeader(
            title: AuthorisationPageSection.history.title(context),
            icon: AuthorisationPageSection.history.icon,
          ),
        ],
      ),
    );
  }
}
