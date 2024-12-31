import 'package:flutter/material.dart';

import '../widgets/authorisation_section_header.dart';
import 'authorisation_page_section.dart';

class ApprovedEnrollmentsPage extends StatefulWidget {
  const ApprovedEnrollmentsPage({super.key});

  @override
  ApprovedEnrollmentsPageState createState() => ApprovedEnrollmentsPageState();
}

class ApprovedEnrollmentsPageState extends State<ApprovedEnrollmentsPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthorisationSectionHeader(
            title: AuthorisationPageSection.approvedEnrollments.title(context),
            icon: AuthorisationPageSection.approvedEnrollments.icon,
          ),
        ],
      ),
    );
  }
}
