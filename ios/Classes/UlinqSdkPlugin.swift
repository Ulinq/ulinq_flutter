import Flutter
import StoreKit
import UIKit

public class UlinqSdkPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ulinq/install_referrer", binaryMessenger: registrar.messenger())
    let instance = UlinqSdkPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getInstallReferrer":
      result(nil)
    case "getPendingInstallToken":
      result(UIPasteboard.general.string)
    case "updateSkAdConversionValue":
      guard let args = call.arguments as? [String: Any],
            let value = args["value"] as? Int else {
        result(false)
        return
      }
      if #available(iOS 14.0, *) {
        SKAdNetwork.updateConversionValue(value)
        result(true)
      } else {
        result(false)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
