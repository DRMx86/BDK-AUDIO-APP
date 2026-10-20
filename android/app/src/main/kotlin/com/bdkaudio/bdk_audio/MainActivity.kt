package com.bdkaudio.bdk_audio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Intent
import android.os.Build
import android.os.Bundle

class MainActivity : FlutterActivity() {
    private var codecBridge: CodecBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // The branded B animation is Flutter's first frame. Remove Android's
            // starting surface immediately instead of playing a second icon exit.
            splashScreen.setOnExitAnimationListener { view -> view.remove() }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        codecBridge?.close()
        codecBridge = CodecBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (codecBridge?.onRequestPermissionsResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (codecBridge?.onActivityResult(requestCode, resultCode) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        codecBridge?.close()
        codecBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        codecBridge?.close()
        codecBridge = null
        super.onDestroy()
    }
}
