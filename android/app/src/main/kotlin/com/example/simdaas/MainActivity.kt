package com.example.simdaas

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Hand-rolled replacement for path_provider's getTemporaryDirectory() on
// Android only -- the pub-resolved path_provider_android version kept
// failing to register (see lib/features/reports/presentation/screens/
// report_details_screen.dart's _shareReport history), throwing
// MissingPluginException on real devices despite working in every local
// check. MainActivity is the app's own code, not a third-party plugin, so
// there's no separate package version to ever drift out of registration --
// this channel is guaranteed to exist whenever the engine does.
private const val CACHE_DIR_CHANNEL = "com.simdaas.agrios/cache_dir"

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CACHE_DIR_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getCacheDir") {
                    result.success(applicationContext.cacheDir.absolutePath)
                } else {
                    result.notImplemented()
                }
            }
    }
}
