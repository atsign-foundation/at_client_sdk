import 'package:flutter/material.dart';

import '../providers/keys_upload_notifier_provider.dart';

class ApkamChoice extends StatefulWidget {
  const ApkamChoice({
    required this.onKeysUpload,
    required this.onApkamChosen,
    super.key,
  });

  final void Function(String keysFile) onKeysUpload;
  final VoidCallback onApkamChosen;

  @override
  ApkamChoiceState createState() => ApkamChoiceState();
}

class ApkamChoiceState extends State<ApkamChoice> {
  static const _kButtonWidth = 170.0;

  @override
  Widget build(BuildContext context) {
    final keysUploadNotifier = KeysUploadNotifierProvider.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Authenticate.',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.black),
        ),
        const SizedBox(height: 4),
        Text(
          'Select your enrollment method.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload atKey',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).primaryColor,
                          ),
                    ),
                    Text(
                      'Select a local atKey file.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: _kButtonWidth,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    textStyle: const TextStyle(
                      fontSize: 18,
                    ),
                    foregroundColor: Theme.of(context).primaryColor,
                    side: BorderSide(color: Theme.of(context).primaryColor),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    if (!keysUploadNotifier.isLoading) {
                      await keysUploadNotifier.filesUpload();
                      if (keysUploadNotifier.error == null) {
                        widget.onKeysUpload(keysUploadNotifier.keysFile!);
                      }
                    }
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: keysUploadNotifier.isLoading
                        ? SizedBox(
                            width: 21,
                            height: 21,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Text('Select atKey'),
                  ),
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enroll with Authenticator',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).primaryColor,
                          ),
                    ),
                    Text(
                      'Authenticate through app with manager keys',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: _kButtonWidth,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(
                      fontSize: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: widget.onApkamChosen,
                  child: Text('Enroll'),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }
}
