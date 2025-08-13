import 'dart:convert';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_login_flutter/domain/at_login_model.dart';
import 'package:at_login_flutter/services/at_login_service.dart';
import 'package:at_login_flutter/services/custom_nav.dart';
import 'package:at_login_flutter/services/size_config.dart';
import 'package:at_login_flutter/utils/app_constants.dart';
import 'package:at_login_flutter/utils/color_constants.dart';
import 'package:at_login_flutter/utils/custom_textstyles.dart';
import 'package:at_login_flutter/utils/strings.dart';
import 'package:at_login_flutter/widgets/custom_appbar.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_qr_reader/flutter_qr_reader.dart';
import 'package:permission_handler/permission_handler.dart';

class AtLogin {
  ///Required field as for navigation.
  final BuildContext context;

  ///By default the plugin connects to [root.atsign.org] to perform atLogin.
  final String? domain;

  ///The color of the screen to match with the app's aesthetics. By default it
  ///is [black].
  final Color? appColor;

  ///if logo is not null then displays the widget in the left side of appbar
  ///else displays nothing.
  final Widget? logo;

  ///Function returns atClientServiceMap successful login.
  final Function(Map<String, AtAuthService>, String) login;

  ///Function returns error when failed in atLogin the existing or given atsign
  ///if [nextScreen] is null;
  final Function(Object) onError;

  ///after successful login will redirect to this screen if it is not null.
  final Widget? nextScreen;

  final AtSignLogger _logger = AtSignLogger('AtLogin Flutter');

  final AtClientPreference atClientPreference;

  AtLogin(
      {Key? key,
      required this.context,
      required this.login,
      required this.onError,
      required this.atClientPreference,
      this.nextScreen,
      this.appColor,
      this.logo,
      this.domain}) {
    _show();
  }

  void _show() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AtLoginWidget(
                context: this.context,
                login: this.login,
                onError: this.onError,
                nextScreen: this.nextScreen!,
                appColor: this.appColor!,
                logo: this.logo!,
                domain: this.domain!,
                atClientPreference: this.atClientPreference,
              ));
    });
    _logger.info('Logging in...!');
  }
}

class AtLoginWidget extends StatefulWidget {
  ///Required field as for navigation.
  final BuildContext context;

  // final Function loginFunc;

  ///The atClientPreference [required] to continue after login.
  final AtClientPreference atClientPreference;

  ///By default the plugin connects to [root.atsign.org] to perform login.
  final String? domain;

  ///The color of the screen to match with the app's aesthetics. default it is [black].
  final Color? appColor;

  ///if logo is not null then displays the widget in the left side of appbar else displays nothing.
  final Widget? logo;

  ///Function returns atClientServiceMap on successful login.
  final Function(Map<String, AtAuthService>, String) login;

  ///Function returns error when failed in login the existing or given atsign if [nextScreen] is null;
  final Function(Object) onError;

  ///after successful login will gets redirected to this screen if it is not null.
  final Widget nextScreen;

  ///name of the follower atsign received from notification to follow them back immediately.
  final String? title;

  AtLoginWidget({
    Key? key,
    required this.context,
    required this.atClientPreference,
    required this.onError,
    required this.login,
    required this.nextScreen,
    this.appColor,
    this.logo,
    this.domain,
    this.title,
    // required this.loginFunc,
  });

  @override
  _AtLoginWidgetState createState() => _AtLoginWidgetState();
}

class _AtLoginWidgetState extends State<AtLoginWidget> {
  var _logger = AtSignLogger('AtLoginWidget');
  bool _permissionGranted = false;
  bool _loading = false;
  bool _scanCompleted = false;
  late String _currentAtsign;

  ///AtLoginObj that will be created.
  AtLoginObj _atLoginObj = AtLoginObj();
  AtLoginService _atLoginService = AtLoginService();
  late QrReaderViewController _controller;

  @override
  void initState() {
    AppConstants.rootDomain = widget.domain;
    // _atLoginService.setLogo = widget.logo;
    _atLoginService.nextScreen = widget.nextScreen;
    // _atLoginService.loginFunc = widget.login;
    // ColorConstants.setAppColor = widget.appColor;
    _atLoginService.atClientPreference = widget.atClientPreference;
    checkPermissions();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
        backgroundColor: ColorConstants.backgroundColor,
        appBar: CustomAppBar(
          showTitle: true,
          showBackButton: true,
        ),
        body: SingleChildScrollView(
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.10),
                  Text(
                    Strings.qrscanDescription,
                    style: CustomTextStyles.fontR16primary,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20.toHeight),
                  Center(
                    child: Builder(
                      builder: (context) => Container(
                        alignment: Alignment.center,
                        width: 300.toWidth,
                        height: 350.toHeight,
                        color: Colors.black,
                        child: !_permissionGranted
                            ? SizedBox()
                            : Stack(
                                children: [
                                  QrReaderView(
                                    width: 300.toWidth,
                                    height: 350.toHeight,
                                    callback: (container) {
                                      this._controller = container;
                                      _controller.startCamera((data, offsets) {
                                        if (!_scanCompleted) {
                                          _controller.stopCamera();
                                          onScan(data, offsets, context);
                                          _scanCompleted = true;
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.toHeight),
                ],
              ),
              _loading
                  ? SizedBox(
                      height: SizeConfig().screenHeight * 0.6,
                      width: SizeConfig().screenWidth,
                      child: Center(
                        child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(ColorConstants.buttonHighLightColor!)),
                      ),
                    )
                  : SizedBox()
            ],
          ),
        ));
  }

  checkPermissions() async {
    var cameraStatus = await Permission.camera.status;
    _logger.info("camera status => $cameraStatus");

    if (cameraStatus.isRestricted || cameraStatus.isDenied || cameraStatus.isPermanentlyDenied) {
      await askPermissions(Permission.camera);
    } else if (cameraStatus.isGranted) {
      setState(() {
        _permissionGranted = true;
      });
    }
  }

  askPermissions(Permission type) async {
    if (type == Permission.camera) {
      await Permission.camera.request();
    } else if (type == Permission.storage) {
      await Permission.storage.request();
    }
  }

  Future<bool> _validateLoginAtsign(String atsign) async {
    var atsignStatus = await _atLoginService.checkAtSignStatus(atsign);
    if (atsignStatus == AtSignStatus.activated) {
      return true;
    } else {
      _problemMessageDialog(
        context,
        Strings.getAtSignStatusMessage(atsignStatus),
      );
      return false;
    }
  }

  Future<void> onScan(String data, List<Offset> offsets, context) async {
    _controller.stopCamera();
    this.setState(() {
      _loading = false;
    });
    _logger.info('onScan|received data $data');
    if (data != '') {
      Map jsonMap = json.decode(data);
      var challenge = jsonMap['challenge'];
      var requestorUrl = jsonMap['requestUrl'];
      _currentAtsign = _atLoginService.formatAtSign(jsonMap['atsign'])!;
      var isPaired = await _atLoginService.atsignIsPaired(_currentAtsign);
      if (isPaired) {
        var message = Strings.loginRequest + ' for ' + _currentAtsign + ' from ' + requestorUrl;
        _atLoginObj.requestorUrl = requestorUrl;
        _atLoginObj.atsign = _currentAtsign;
        _atLoginObj.challenge = challenge;
        var result = await _validateLoginAtsign(_currentAtsign);
        if (!result) {
          _logger.severe(Strings.atServerNotAvailable);
          var message = _currentAtsign + Strings.atServerNotAvailable;
          _problemMessageDialog(context, message);
        }
        _authorizeLoginDialog(context, message);
      } else {
        var message = _currentAtsign + Strings.atSignNotPaired;
        _problemMessageDialog(context, message);
      }
    } else {
      _logger.severe(Strings.badQr);
      var message = _currentAtsign + Strings.badQr;
      _problemMessageDialog(context, message);
    }
  }

  Future<bool> _completeLogin() async {
    bool proofed = false;
    bool saved = false;
    proofed = await _saveProof();
    if (proofed) {
      saved = await _saveLoginResult();
    }
    _logger.info('_completeLogin|result|${proofed && saved}');
    return (proofed && saved);
  }

  Future<bool> _saveProof() async {
    var proofed = await _atLoginService.putLoginProof(_atLoginObj);
    _logger.info('_saveProof|proofed=$proofed');
    return proofed;
  }

  Future<bool> _saveLoginResult() async {
    var saved = await _atLoginService.handleAtLogin(_atLoginObj);
    _logger.info('_saveLogin|saved=$saved');
    return saved;
  }

  _authorizeLoginDialog(BuildContext context, String message) {
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: Text(message, style: CustomTextStyles.fontR20primary),
            actions: [
              OverflowBar(
                children: [
                  ElevatedButton(
                    child: const Text(Strings.loginDenied),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        // padding: EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                        textStyle: TextStyle(
                          fontSize: 18,
                        )),
                    onPressed: () async {
                      _atLoginObj.allowLogin = false;
                      bool success = await _completeLogin();
                      if (success) {
                        CustomNav().pop(context);
                        CustomNav().push(widget.nextScreen, context);
                      }
                    },
                  ),
                  ElevatedButton(
                    child: Text(Strings.loginAllowed),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        textStyle: TextStyle(
                          fontSize: 18,
                        )),
                    onPressed: () async {
                      _atLoginObj.allowLogin = true;
                      bool success = await _completeLogin();
                      if (success) {
                        CustomNav().pop(context);
                        CustomNav().push(widget.nextScreen, context);
                      }
                    },
                  ),
                ],
              )
            ],
          );
        });
  }

  _problemMessageDialog(BuildContext context, String message) {
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: Text(message, style: CustomTextStyles.fontR20primary),
            actions: [
              OverflowBar(
                children: [
                  ElevatedButton(
                      child: const Text(Strings.notPairAtsign),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          // padding: EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                          textStyle: TextStyle(
                            fontSize: 18,
                          )),
                      onPressed: () {
                        CustomNav().pop(context);
                        CustomNav().push(widget.nextScreen, context);
                      } // Navigator.pop(context).push(widget.nextScreen, context); // Navigator.pop(context);
                      ),
                  ElevatedButton(
                    child: Text(Strings.pairAtsign),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        textStyle: TextStyle(
                          fontSize: 18,
                        )),
                    onPressed: () {
                      CustomNav().pop(context);
                      CustomNav().push(widget.nextScreen, context);
                    },
                  ),
                ],
              )
            ],
          );
        });
  }
}
