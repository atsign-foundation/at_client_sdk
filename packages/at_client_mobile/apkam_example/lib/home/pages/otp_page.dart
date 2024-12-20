import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

import '../../authorisation/models/models.dart';
import '../../authorisation/services/authorisation_service.dart';

class OtpPage extends StatefulWidget {
  const OtpPage({super.key});

  @override
  OtpPageState createState() => OtpPageState();
}

class OtpPageState extends State<OtpPage> {
  late final service = AuthorisationService(AtClientManager.getInstance().atClient);
  late final sppController = TextEditingController();

  late Future<Otp> getOtp;
  late Future<Otp?> getSpp;

  @override
  void initState() {
    super.initState();
    getOtp = service.generateOtp();
    getSpp = service.getActiveSpp();
  }

  @override
  void dispose() {
    sppController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OTP Page'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FutureBuilder<Otp>(
            future: getOtp,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              return Text('OTP: ${snapshot.data}');
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<Otp?>(
            future: getSpp,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              if (snapshot.data == null) {
                return const Text('No SPP set');
              }
              return Text('Saved SPP: ${snapshot.data!.otp}. Expires: ${snapshot.data!.expiry}');
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: sppController,
          ),
          ElevatedButton(
            onPressed: () async {
              await service.setSpp(spp: sppController.text);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('SPP set successfully'),
                  ),
                );
                sppController.clear();
                setState(() {
                  getSpp = service.getActiveSpp();
                });
              }
            },
            child: const Text('Submit SPP'),
          ),
        ],
      ),
    );
  }
}
