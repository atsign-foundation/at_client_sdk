import 'package:flutter/material.dart';

import '../widgets/authorisation_section_header.dart';
import 'authorisation_page_section.dart';

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});

  @override
  RequestsPageState createState() => RequestsPageState();
}

class RequestsPageState extends State<RequestsPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthorisationSectionHeader(
            title: AuthorisationPageSection.requests.title(context),
            icon: AuthorisationPageSection.requests.icon,
          ),
        ],
      ),
    );
  }
}
