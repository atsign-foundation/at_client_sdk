import 'dart:io';

import 'package:at_follows_flutter/domain/connection_model.dart';
import 'package:at_follows_flutter/services/connections_service.dart';
import 'package:at_follows_flutter/services/sdk_service.dart';
import 'package:at_follows_flutter/utils/color_constants.dart';
import 'package:at_follows_flutter/utils/custom_textstyles.dart';
import 'package:at_follows_flutter/utils/strings.dart';
import 'package:at_follows_flutter/widgets/custom_appbar.dart';
import 'package:at_follows_flutter/widgets/custom_button.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_follows_flutter/services/size_config.dart';

class QrScan extends StatefulWidget {
  @override
  _QrScanState createState() => _QrScanState();
}

class _QrScanState extends State<QrScan> {
  var _logger = AtSignLogger('Connections QR Scan');
  bool permissionGrated = false;
  bool loading = false;
  bool _scanCompleted = false;
  QRViewController? _controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  Barcode? result;
  bool _isScan = false;

  @override
  initState() {
    checkPermissions();
    super.initState();
  }

  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _controller!.pauseCamera();
    } else if (Platform.isIOS) {
      _controller!.resumeCamera();
    }
  }

  checkPermissions() async {
    var cameraStatus = await Permission.camera.status;
    _logger.info("camera status => $cameraStatus");

    if (!cameraStatus.isGranted &&
        !cameraStatus.isPermanentlyDenied &&
        !cameraStatus.isLimited) {
      await askPermissions(Permission.camera);
    }
  }

  askPermissions(Permission type) async {
    if (type == Permission.camera) {
      var _res = await Permission.camera.request();

      if (_res == PermissionStatus.granted ||
          _res == PermissionStatus.limited) {
        setState(() {});
      }
    }
  }

  Future<bool> _validateFollowingAtsign(String? atsign,
      [bool isScan = false]) async {
    if (ConnectionProvider().containsFollowing(atsign)) {
      _showFollowersAlertDialog(context, atsign, isScan: isScan);
      return false;
    } else if (atsign == SDKService().atsign) {
      _showFollowersAlertDialog(context, atsign,
          message: Strings.ownAtsign, isScan: isScan);
      return false;
    } else if (atsign == Strings.invalidAtsign) {
      _showFollowersAlertDialog(context, atsign,
          message: Strings.invalidAtsignMessage, isScan: isScan);
      return false;
    }
    var atSignStatus = await SDKService().checkAtSignStatus(atsign!);
    if (atSignStatus == AtSignStatus.teapot ||
        atSignStatus == AtSignStatus.activated) {
      return true;
    } else {
      _showFollowersAlertDialog(context, atsign,
          message: Strings.getAtSignStatusMessage(atSignStatus),
          isScan: isScan);
      return false;
    }
  }

  Future<void> onScan(String? data, context) async {
    // _controller.stopCamera();
    this.setState(() {
      loading = true;
    });
    _logger.info('received data is $data');
    if (data != '') {
      var formattedAtsign = ConnectionsService().formatAtSign(data);
      var result = await _validateFollowingAtsign(formattedAtsign, true);

      if (result) {
        Navigator.pop(context);
        await ConnectionProvider().follow(formattedAtsign);
      }
    } else {
      _logger.severe('Scanning the QRcode throws error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: ColorConstants.backgroundColor,
        appBar: CustomAppBar(
          showTitle: true,
          title: SDKService().atsign,
        ),
        body: SingleChildScrollView(
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.10),
                  SwitchListTile(
                    title: Text(
                      Strings.qrscanDescription,
                      style: CustomTextStyles.fontR16primary,
                      textAlign: TextAlign.center,
                    ),
                    value: _isScan,
                    onChanged: (value) {
                      setState(() {
                        _isScan = value;
                      });
                    },
                    inactiveTrackColor: ColorConstants.inactiveTrackColor,
                    inactiveThumbColor: ColorConstants.inactiveThumbColor,
                    activeTrackColor: ColorConstants.activeTrackColor,
                    activeColor: ColorConstants.activeColor,
                  ),
                  SizedBox(height: 20.toHeight),
                  Center(
                    child: Builder(
                      builder: (context) => Container(
                        alignment: Alignment.center,
                        width: 300.toWidth,
                        height: 350.toHeight,
                        color: Colors.black,
                        child: !_isScan
                            ? SizedBox()
                            : Stack(
                                children: [
                                  QRView(
                                    key: qrKey,
                                    onQRViewCreated: _onQRViewCreated,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.toHeight),
                  Text(
                    'OR',
                    style: CustomTextStyles.fontR14primary,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20.toHeight),
                  CustomButton(
                      height: 40.toHeight,
                      isActive: true,
                      onPressedCallBack: (value) {
                        _getAtsignForm(context);
                      },
                      text: Strings.enterAtsignButton),
                  SizedBox(height: 20.toHeight),
                ],
              ),
              loading
                  ? SizedBox(
                      height: SizeConfig().screenHeight * 0.6,
                      width: SizeConfig().screenWidth,
                      child: Center(
                        child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color?>(
                                ColorConstants.buttonHighLightColor)),
                      ),
                    )
                  : SizedBox()
            ],
          ),
        ));
  }

  void _onQRViewCreated(QRViewController controller) async {
    this._controller = controller;
    _controller?.scannedDataStream.listen((scanData) {
      setState(() {
        result = scanData;
      });
    });
    if (result != null) {
      await onScan(result?.code, context);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  _getAtsignForm(BuildContext context) {
    final TextEditingController _atsignController = TextEditingController();
    final _formKey = GlobalKey<FormState>();
    showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
              title: Text(
                Strings.enterAtsignTitle,
                style: CustomTextStyles.fontR16primary,
              ),
              content: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.always,
                child: TextFormField(
                  validator: (value) {
                    if (value == null || value == '') {
                      return '@sign cannot be empty';
                    }
                    return null;
                  },
                  controller: _atsignController,
                  decoration: InputDecoration(
                      hintText: Strings.atsignHintText,
                      prefixText: '@',
                      border: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: ColorConstants.buttonHighLightColor!))),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      this.setState(() {
                        loading = true;
                      });
                      var formattedAtsign = ConnectionsService()
                          .formatAtSign(_atsignController.text);

                      Navigator.pop(_);
                      var result =
                          await _validateFollowingAtsign(formattedAtsign);

                      if (!result) {
                        setState(() {
                          loading = false;
                        });
                        return;
                      } else {
                        Navigator.pop(context, true);
                        await ConnectionProvider().follow(formattedAtsign);
                      }
                    }
                  },
                  child: Text(
                    Strings.submitButton,
                    style: TextStyle(
                        color: ColorConstants.buttonHighLightColor,
                        fontSize: 14.toFont),
                  ),
                ),
              ]);
        });
  }

  _showFollowersAlertDialog(BuildContext context, String? atsign,
      {String? message, bool isScan = false}) {
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: Text(
                message == null
                    ? '${Strings.existingFollower}$atsign'
                    : message,
                style: CustomTextStyles.fontR14dark),
            actions: [
              TextButton(
                child: Text(Strings.Close),
                onPressed: () {
                  Navigator.pop(context);
                  if (isScan) {
                    if (!_scanCompleted) {
                      QRView(key: qrKey, onQRViewCreated: _onQRViewCreated);
                    }
                    setState(() {
                      loading = false;
                      _scanCompleted = false;
                    });
                  }
                },
              )
            ],
          );
        });
  }
}
