import 'package:at_client_mobile/src/onboarding/widgets/apkam_choice.dart';
import 'package:flutter/material.dart';

class EnrollmentPage extends StatefulWidget {
  const EnrollmentPage({super.key});

  @override
  EnrollmentPageState createState() => EnrollmentPageState();
}

class EnrollmentPageState extends State<EnrollmentPage> {
  @override
  Widget build(BuildContext context) {
    // TODO(Doug): Manage the flow through the enrollment process here.
    return ApkamChoice();
  }
}
