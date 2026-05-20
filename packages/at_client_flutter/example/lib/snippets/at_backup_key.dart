import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_commons/atsign.dart';
import 'package:at_file_saver/at_file_saver.dart';
import 'package:at_utils/at_logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

///Please edit these Strings to customize your widget
class Strings {
  static const String buttonText = "Backup AtKeys";

  // controls the keyFile that is stored
  // experimental: change only for extremely custom installs
  static const String keyFileSuffix = "_key";
  static const String keyFileExtension = ".atKeys";
  static const String keyFileName = "_key.atKeys";
}

class BackupKeyWidget extends StatelessWidget {
  final AtSignLogger _logger = AtSignLogger('AtBackupKey');

  ///required to provide backup keys for `atsign` to save.
  final Atsign atsign;

  ///takes a `String` and displays on button. set [isButton] to `true` to use this.
  final String buttonText;

  ///any double value for customizing width of button if [isButton] sets to `true`.
  final double? buttonWidth;

  ///any double value for customizing height of a button if [isButton] sets to `true`.
  final double? buttonHeight;

  ///Customize the button color if [isButton] sets to `true`.
  final Color? buttonColor;

  BackupKeyWidget({
    super.key,
    required this.atsign,
    this.buttonText = "Backup AtKeys",
    this.buttonWidth,
    this.buttonHeight,
    this.buttonColor,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        var result = await onBackup(context);
        if (result == false && context.mounted) {
          _showAlertDialog(context);
        }
      },
      child: Text(buttonText),
    );
  }

  _showAlertDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context1) {
        return AlertDialog(
          title: Row(
            children: [
              Text(
                'Error',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Icon(Icons.sentiment_dissatisfied, size: 25),
            ],
          ),
          content: Text(
            'Could not backup the key file',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context1);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  onBackup(BuildContext context) async {
    try {
      var keychain = KeychainAtKeysIo();
      var atKeys = await keychain.read(atsign);
      Map<String, dynamic> aesEncryptedKeys = jsonDecode(
        await keychain.encryptAtKeysWithSelfEncKey(atKeys),
      );
      if (aesEncryptedKeys.isEmpty) {
        return false;
      }
      String tempFilePath = await _generateFile(aesEncryptedKeys);
      if (Platform.isAndroid && context.mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        await showDialog(
          context: context,
          useRootNavigator: false,
          builder: (context) {
            return AlertDialog(
              contentPadding: EdgeInsets.zero,
              content: Container(
                color: Colors.white,
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    InkWell(
                      onTap: () async {
                        var status = await Permission.storage.status;
                        if (!status.isGranted) {
                          await Permission.storage.request();
                        }

                        String? dir = await getDownloadPath();
                        if (dir != null) {
                          String newPath = "$dir/$atsign${Strings.keyFileName}";
                          debugPrint(newPath);

                          try {
                            if (await File(newPath).exists()) {
                              if (context.mounted) {
                                throw Exception("File already exists");
                              }
                            } else {
                              final encryptedKeysFile = await File(
                                newPath,
                              ).create();
                              var keyString = jsonEncode(aesEncryptedKeys);
                              encryptedKeysFile.writeAsStringSync(keyString);
                              if (context.mounted) {
                                Navigator.of(context).pop(true);
                              }
                            }
                          } catch (e) {
                            debugPrint("$e");
                          }
                        }
                      },
                      child: Container(
                        height: 52,
                        width: double.infinity,
                        alignment: Alignment.centerLeft,
                        child: const Text("Download"),
                      ),
                    ),
                    const Divider(height: 1),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        shareFile(context: context, path: tempFilePath);
                      },
                      child: Container(
                        height: 52,
                        width: double.infinity,
                        alignment: Alignment.centerLeft,
                        child: const Text("Share"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      } else if (Platform.isIOS) {
        if (context.mounted) {
          var size = MediaQuery.of(context).size;
          await Share.shareXFiles(
            [XFile(tempFilePath)],
            sharePositionOrigin: Rect.fromLTWH(
              0,
              0,
              size.width,
              size.height / 2,
            ),
          ).then((ShareResult shareResult) {
            if (shareResult.status == ShareResultStatus.success &&
                context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File saved successfully')),
              );
            }
          });
        }
      } else {
        final path = await FilePicker.platform.saveFile(
          fileName: '$atsign${Strings.keyFileName}',
        );
        if (path == null) return;
        final file = XFile(tempFilePath);
        await file.saveTo(path);
        if (context.mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } on Exception catch (ex, s) {
      _logger.severe('BackingUp keys throws $ex exception \n ST: $s \n');
    } on Error catch (err, s) {
      _logger.severe('BackingUp keys throws $err error \n ST: $s\n');
    }
  }

  Future<String> _generateFile(Map<String, dynamic> aesEncryptedKeys) async {
    if (Platform.isAndroid || Platform.isIOS) {
      var status = await Permission.storage.status;
      if (status.isDenied || status.isRestricted) {
        await Permission.storage.request();
      }

      var directory = await path_provider.getApplicationSupportDirectory();
      String path = directory.path.toString() + Platform.pathSeparator;
      final encryptedKeysFile = await File(
        '$path$atsign${Strings.keyFileName}',
      ).create();
      var keyString = jsonEncode(aesEncryptedKeys);
      encryptedKeysFile.writeAsStringSync(keyString);
      return encryptedKeysFile.path;
    } else {
      String encryptedKeysFile = '$atsign${Strings.keyFileSuffix}';
      var keyString = jsonEncode(aesEncryptedKeys);
      final List<int> codeUnits = keyString.codeUnits;
      final Uint8List data = Uint8List.fromList(codeUnits);
      String desktopPath = await FileSaver.instance.saveFile(
        encryptedKeysFile,
        data,
        Strings.keyFileExtension,
        mimeType: MimeType.OTHER,
      );
      return desktopPath;
    }
  }

  void shareFile({required BuildContext context, required String path}) async {
    var size = MediaQuery.of(context).size;
    await Share.shareXFiles(
      [XFile(path)],
      sharePositionOrigin: Rect.fromLTWH(0, 0, size.width, size.height / 2),
    ).then((ShareResult shareResult) {
      if (shareResult.status == ShareResultStatus.success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File saved successfully')),
        );
      }
    });
  }

  static Future<String?> getDownloadPath() async {
    Directory? directory;
    if (Platform.isIOS) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        directory = await getExternalStorageDirectory();
      }
    }
    return directory?.path;
  }
}
