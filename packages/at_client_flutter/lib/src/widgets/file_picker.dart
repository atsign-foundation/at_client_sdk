import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// A dialog widget that allows users to select a local atKey file for authentication.
///
/// Use `AtKeysFileDialog.show` to display the dialog and retrieve the selected file.
///
/// Returns:
/// - A `FileAtKeysIo` instance representing the selected atKey file, or null if no file was selected.
class AtKeysFileDialog extends StatelessWidget {
  const AtKeysFileDialog({super.key});

  static Future<FileAtKeysIo?> show(BuildContext context) async {
    return await showDialog<FileAtKeysIo>(
      context: context,
      builder: (context) => const AtKeysFileDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Text(
              'Authenticate',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Upload atKey',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message:
                            'Select a local atKey file for authentication.',
                        child: Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select a local .atKeys file',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        var result = await FilePicker.pickFiles(
                          type: FileType.custom,
                          initialDirectory: Directory.current.path,
                          allowedExtensions: ['atKeys'],
                        );
                        if (result != null && result.files.isNotEmpty) {
                          File file = File(result.files.single.path!);
                          print('Selected atKey file: ${file.path}');
                          FileAtKeysIo fileAtKeysIo = FileAtKeysIo(
                            filePath: (_) => file.path,
                          );
                          Navigator.of(context).pop(fileAtKeysIo);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: const BorderSide(color: Colors.black54),
                      ),
                      child: const Text(
                        'Select atKey',
                        style: TextStyle(color: Colors.black, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
