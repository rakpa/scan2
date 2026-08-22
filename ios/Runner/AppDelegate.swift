import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let ocr = engineBridge.pluginRegistry.registrar(forPlugin: "ScanellaOcr")!
    ScanellaOcrPlugin.register(with: ocr)
    let haptics = engineBridge.pluginRegistry.registrar(forPlugin: "ScanellaHaptics")!
    ScanellaHapticsPlugin.register(with: haptics)
  }
}

private enum ScanellaHapticsPlugin {
  static let selection = UISelectionFeedbackGenerator()
  static let light = UIImpactFeedbackGenerator(style: .light)
  static let medium = UIImpactFeedbackGenerator(style: .medium)
  static let notify = UINotificationFeedbackGenerator()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "scanella/haptics",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "prepare":
        selection.prepare()
        light.prepare()
        medium.prepare()
        notify.prepare()
        result(nil)
      case "selection":
        selection.selectionChanged()
        selection.prepare()
        result(nil)
      case "impactLight":
        light.impactOccurred()
        light.prepare()
        result(nil)
      case "impactMedium":
        medium.impactOccurred()
        medium.prepare()
        result(nil)
      case "success":
        notify.notificationOccurred(.success)
        notify.prepare()
        result(nil)
      case "error":
        notify.notificationOccurred(.error)
        notify.prepare()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private enum ScanellaOcrPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "scanella/ocr",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let data: Data?
      if let typed = call.arguments as? FlutterStandardTypedData {
        data = typed.data
      } else {
        data = call.arguments as? Data
      }
      guard let imageData = data else {
        result(
          FlutterError(
            code: "bad_image",
            message: "Could not read that image.",
            details: nil
          )
        )
        return
      }
      recognize(data: imageData, result: result)
    }
  }

  static func recognize(data: Data, result: @escaping FlutterResult) {
    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        result(
          FlutterError(
            code: "ocr_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
        return
      }
      let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
      let lines = observations.compactMap { $0.topCandidates(1).first?.string }
      result(lines.joined(separator: "\n"))
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(data: data, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        result(
          FlutterError(
            code: "ocr_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }
}
