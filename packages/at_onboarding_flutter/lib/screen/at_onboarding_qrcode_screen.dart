import 'dart:io';

import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_dialog.dart';
import 'package:at_sync_ui_flutter/at_sync_material.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

/// Represents the result of scanning a QR code during the onboarding process
class AtOnboardingQRCodeResult {
  /// The atSign associated with the QR result
  final String atSign;

  /// The secret associated with the QR result
  final String secret;

  AtOnboardingQRCodeResult({
    required this.atSign,
    required this.secret,
  });
}

/// The QR code screen used during the onboarding process.
class AtOnboardingQRCodeScreen extends StatefulWidget {
  /// Configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingQRCodeScreen({
    Key? key,
    required this.config,
  }) : super(key: key);

  @override
  State<AtOnboardingQRCodeScreen> createState() =>
      _AtOnboardingQRCodeScreenState();
}

class _AtOnboardingQRCodeScreenState extends State<AtOnboardingQRCodeScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  Barcode? result;
  QRViewController? _controller;

  bool isDetecting = false;
  bool showQRScanner = false;

  @override
  void initState() {
    _initialSetup();
    super.initState();
  }

  void _initialSetup() async {
    PermissionStatus cameraStatus = await Permission.camera.status;

    if (cameraStatus != PermissionStatus.denied) {
      if (cameraStatus == PermissionStatus.permanentlyDenied) {
        openAppSettings();
      } else {
        setState(() {
          showQRScanner = true;
        });
      }
    } else {
      final result = await Permission.camera.request();
      if (result != PermissionStatus.denied) {
        if (result == PermissionStatus.permanentlyDenied) {
          openAppSettings();
        } else {
          setState(() {
            showQRScanner = true;
          });
        }
      } else {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AtOnboardingLocalizations.current.no_permission,
            ),
          ),
        );
      }
    }
  }

  // In order to get hot reload to work we need to pause the camera if the platform
  // is android, or resume the camera if the platform is iOS.
  @override
  void reassemble() async {
    super.reassemble();
    if (Platform.isAndroid) {
      await _controller!.pauseCamera();
    } else if (Platform.isIOS) {
      await _controller!.resumeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      primaryColor: widget.config.theme?.primaryColor,
      textTheme: widget.config.theme?.textTheme,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: widget.config.theme?.primaryColor,
          ),
    );

    return AbsorbPointer(
      absorbing: false,
      child: Theme(
        data: theme,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              AtOnboardingLocalizations.current.scan_your_QR,
            ),
            actions: const [
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: AtSyncIndicator(color: Colors.white),
                ),
              ),
            ],
          ),
          body: showQRScanner
              ? _buildQrView(theme)
              : Container(
                  color: Colors.black,
                ),
        ),
      ),
    );
  }

  Widget _buildQrView(ThemeData theme) {
    // For this example we check how width or tall the device is and change the scanArea and overlay accordingly.
    var scanArea = (MediaQuery.of(context).size.width < 400 ||
            MediaQuery.of(context).size.height < 400)
        ? 250.0
        : 300.0;
    // To ensure the Scanner view is properly sizes after rotation
    // we need to listen for Flutter SizeChanged notification and update controller
    return QRView(
      key: qrKey,
      cameraFacing: CameraFacing.back,
      onQRViewCreated: _onQRViewCreated,
      formatsAllowed: const [BarcodeFormat.qrcode],
      overlay: QrScannerOverlayShape(
        borderColor: theme.primaryColor,
        borderRadius: 10,
        borderLength: 30,
        borderWidth: 10,
        cutOutSize: scanArea,
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      _controller = controller;
    });

    // call resumeCamera function
    if (Platform.isAndroid) {
      _controller!.resumeCamera();
    }

    _controller!.scannedDataStream.listen((scanData) {
      onScannedData(scanData.code);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void onScannedData(String? qrCode) async {
    if (isDetecting) {
      return;
    }

    isDetecting = true;
    if ((qrCode ?? '').isNotEmpty) {
      List<String> values = (qrCode ?? '').split(':');
      if (values.length == 2) {
        _controller?.pauseCamera();
        //It's issue from camera library so we need to add a delay to waiting for pause camera
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        Navigator.pop(
          context,
          AtOnboardingQRCodeResult(atSign: values[0], secret: values[1]),
        );
      } else {
        await _controller?.pauseCamera();
        if (!mounted) return;
        await AtOnboardingDialog.showError(
          context: context,
          message: AtOnboardingLocalizations.current.invalid_QR,
        );
        await _controller?.resumeCamera();
      }
    }
    isDetecting = false;
  }
}
