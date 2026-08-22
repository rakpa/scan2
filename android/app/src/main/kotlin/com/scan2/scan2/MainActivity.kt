package com.scan2.scan2

import android.graphics.BitmapFactory
import android.os.Build
import android.view.HapticFeedbackConstants
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scanella/haptics")
            .setMethodCallHandler { call, result ->
                val view = window.decorView
                when (call.method) {
                    "prepare" -> result.success(null)
                    "selection" -> {
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        result.success(null)
                    }
                    "impactLight" -> {
                        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                        result.success(null)
                    }
                    "impactMedium" -> {
                        val type = if (Build.VERSION.SDK_INT >= 30) {
                            HapticFeedbackConstants.CONFIRM
                        } else {
                            HapticFeedbackConstants.KEYBOARD_TAP
                        }
                        view.performHapticFeedback(type)
                        result.success(null)
                    }
                    "success" -> {
                        val type = if (Build.VERSION.SDK_INT >= 30) {
                            HapticFeedbackConstants.CONFIRM
                        } else {
                            HapticFeedbackConstants.VIRTUAL_KEY
                        }
                        view.performHapticFeedback(type)
                        result.success(null)
                    }
                    "error" -> {
                        val type = if (Build.VERSION.SDK_INT >= 30) {
                            HapticFeedbackConstants.REJECT
                        } else {
                            HapticFeedbackConstants.LONG_PRESS
                        }
                        view.performHapticFeedback(type)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scanella/ocr")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.arguments as? ByteArray
                if (bytes == null) {
                    result.error("bad_image", "Could not read that image.", null)
                    return@setMethodCallHandler
                }
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap == null) {
                    result.error("bad_image", "Could not decode that image.", null)
                    return@setMethodCallHandler
                }
                val image = InputImage.fromBitmap(bitmap, 0)
                TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                    .process(image)
                    .addOnSuccessListener { text -> result.success(text.text) }
                    .addOnFailureListener { error ->
                        result.error("ocr_failed", error.message, null)
                    }
            }
    }
}
