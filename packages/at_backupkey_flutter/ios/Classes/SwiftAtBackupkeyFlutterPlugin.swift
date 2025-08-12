import Flutter
import UIKit

public class SwiftAtBackupkeyFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "at_backupkey_flutter", binaryMessenger: registrar.messenger())
    let instance = SwiftAtBackupkeyFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result("iOS " + UIDevice.current.systemVersion)
  }
}
