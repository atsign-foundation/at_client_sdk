import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_backupkey_flutter/services/backupkey_service.dart';
import 'package:at_backupkey_flutter/utils/size_config.dart';
import 'package:at_backupkey_flutter/utils/strings.dart';
import 'package:at_utils/at_logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:showcaseview/showcaseview.dart';

class BackupKeyWidget extends StatelessWidget {
  final AtSignLogger _logger = AtSignLogger('BackUp Key Widget');

  ///[required] to provide backup keys for `atsign` to save.
  final String atsign;

  ///set to `true` for using widget as a button.
  final bool isButton;

  ///set to `true` for using widget as an icon.
  final bool? isIcon;

  ///takes a `String` and displays on button. set [isButton] to `true` to use this.
  final String? buttonText;

  ///Color of the icon can be set if [isIcon] is set as `true`.
  final Color? iconColor;

  ///any double value for customizing width of button if [isButton] sets to `true`.
  final double? buttonWidth;

  ///any double value for customizing height of a button if [isButton] sets to `true`.
  final double? buttonHeight;

  ///any double value for customizing size of the icon if [isIcon] sets to `true`.
  final double? iconSize;

  ///Customize the button color if [isButton] sets to `true`.
  final Color? buttonColor;

  BackupKeyWidget(
      {super.key,
      required this.atsign,
      this.isButton = false,
      this.isIcon,
      this.buttonText,
      this.iconColor,
      this.buttonWidth,
      this.buttonHeight,
      this.buttonColor,
      this.iconSize});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return isButton
        ? GestureDetector(
            onTap: () async {
              var result = await onBackup(context);
              if (result == false && context.mounted) {
                _showAlertDialog(context);
              }
            },
            child: Container(
              width: buttonWidth ?? 158.toWidth,
              height: buttonHeight ?? (50.toHeight),
              padding: EdgeInsets.symmetric(horizontal: 10.toWidth),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30.toWidth),
                  color: buttonColor ?? Colors.black),
              child: Center(
                child: Text(buttonText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16.toFont,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          )
        : IconButton(
            icon: Icon(
              Icons.file_copy,
              color: iconColor,
            ),
            onPressed: () {
              showBackupDialog(context);
            },
          );
  }

  void _showAlertDialog(BuildContext context) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context1) {
          return AlertDialog(
            title: Row(
              children: [
                Text(
                  'Error',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14.toFont),
                ),
                Icon(Icons.sentiment_dissatisfied, size: 25.toFont)
              ],
            ),
            content: Text(
              'Could not backup the key file',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 14.toFont),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context1);
                },
                child: const Text('Close'),
              )
            ],
          );
        });
  }

  void showBackupDialog(BuildContext context) {
    SizeConfig().init(context);
    GlobalKey key = GlobalKey();
    BuildContext? myContext;
    showDialog(
        context: context,
        builder: (BuildContext ctxt) {
          return ShowCaseWidget(builder: (context) {
            myContext = context;
            return Dialog(
              child: Container(
                padding: const EdgeInsets.all(20),
                width:
                    (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                        ? 600
                        : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: Showcase(
                              key: key,
                              description:
                                  'Each atSign has a unique key used to verify ownership and encrypt your data. You will get this key when you first activate your atSign, and you will need it to pair your atSign with other devices and all atPlatform apps.'
                                  '\n\n'
                                  'PLEASE SECURELY SAVE YOUR KEYS. WE DO NOT HAVE ACCESS TO THEM AND CANNOT CREATE A BACKUP OR RESET THEM.',
                              targetShapeBorder: const CircleBorder(),
                              disableMovingAnimation: true,
                              targetBorderRadius:
                                  const BorderRadius.all(Radius.circular(40)),
                              showArrow: false,
                              targetPadding: const EdgeInsets.all(5),
                              blurValue: 2,
                              child: Text(
                                Strings.backUpKeysTitle,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.toFont,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            ShowCaseWidget.of(myContext!).startShowCase([key]);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(50)),
                            margin: const EdgeInsets.all(0),
                            height: 20,
                            width: 20,
                            child: const Icon(
                              Icons.question_mark,
                              size: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          Strings.backUpKeysDescription,
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 20.toHeight),
                        Row(
                          children: [
                            TextButton(
                                child: const Text(Strings.backButtonTitle,
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () async {
                                  var result = await onBackup(context);
                                  if (context.mounted) {
                                    Navigator.pop(ctxt);
                                  }
                                  if (result == false && context.mounted) {
                                    _showAlertDialog(context);
                                  }
                                }),
                            const Spacer(),
                            TextButton(
                                child: const Text(Strings.cancelButtonTitle,
                                    style: TextStyle()),
                                onPressed: () {
                                  Navigator.pop(context);
                                })
                          ],
                        )
                      ],
                    ),
                  ],
                ),
              ),
            );
          });
        });
  }

  Future<bool> onBackup(BuildContext context) async {
    try {
      var aesEncryptedKeys = await BackUpKeyService.getEncryptedKeys(atsign);
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
                          String newPath =
                              "$dir/$atsign${Strings.backupKeyName}";
                          debugPrint(newPath);

                          try {
                            if (await File(newPath).exists()) {
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                showSnackBar(
                                    context: context, content: "File exists!");
                              }
                            } else {
                              final encryptedKeysFile =
                                  await File(newPath).create();
                              var keyString = jsonEncode(aesEncryptedKeys);
                              encryptedKeysFile.writeAsStringSync(keyString);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                showSnackBar(
                                  context: context,
                                  content: 'File saved successfully',
                                );
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
                        shareFile(
                          context: context,
                          path: tempFilePath,
                        );
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
        return true;
      } else if (Platform.isIOS) {
        if (context.mounted) {
          var size = MediaQuery.of(context).size;
          await Share.shareXFiles(
            [XFile(tempFilePath)],
            sharePositionOrigin:
                Rect.fromLTWH(0, 0, size.width, size.height / 2),
          ).then((ShareResult shareResult) {
            if (shareResult.status == ShareResultStatus.success &&
                context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File saved successfully')));
            }
          });
        }
        return true;
      } else {
        final path = await FilePicker.platform.saveFile(
          fileName: '$atsign${Strings.backupKeyName}',
        );
        if (path == null) return false;
        final file = XFile(tempFilePath);
        await file.saveTo(path);
        if (context.mounted) {
          showSnackBar(
            context: context,
            content: 'File saved successfully',
          );
        }
        return true;
      }
    } on Exception catch (ex) {
      _logger.severe('BackingUp keys throws $ex exception');
      return false;
    } on Error catch (err) {
      _logger.severe('BackingUp keys throws $err error');
      return false;
    }
  }

  Future<String> _generateFile(Map<String, String> aesEncryptedKeys) async {
    if (Platform.isAndroid || Platform.isIOS) {
      var status = await Permission.storage.status;
      if (status.isDenied || status.isRestricted) {
        await Permission.storage.request();
      }

      var directory = await path_provider.getApplicationSupportDirectory();
      String path = directory.path.toString() + Platform.pathSeparator;
      final encryptedKeysFile =
          await File('$path$atsign${Strings.backupKeyName}').create();
      var keyString = jsonEncode(aesEncryptedKeys);
      encryptedKeysFile.writeAsStringSync(keyString);
      return encryptedKeysFile.path;
    } else {
      String encryptedKeysFile = '$atsign${Strings.backupKeySuffix}';
      var keyString = jsonEncode(aesEncryptedKeys);
      final List<int> codeUnits = keyString.codeUnits;
      final Uint8List data = Uint8List.fromList(codeUnits);
      String desktopPath = await FileSaver.instance.saveFile(
          name: encryptedKeysFile,
          bytes: data,
          fileExtension: Strings.backupKeyExtension,
          mimeType: MimeType.other);
      return desktopPath;
    }
  }

  void shareFile({
    required BuildContext context,
    required String path,
  }) async {
    var size = MediaQuery.of(context).size;
    await Share.shareXFiles(
      [XFile(path)],
      sharePositionOrigin: Rect.fromLTWH(0, 0, size.width, size.height / 2),
    ).then((ShareResult shareResult) {
      if (shareResult.status == ShareResultStatus.success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File saved successfully')));
      }
    });
  }

  void showSnackBar({
    required BuildContext context,
    String content = '',
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          content,
        ),
      ),
    );
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
