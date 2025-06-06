package com.zeroone.theconduit

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register the SharedChannelHandler for both channels
        SharedChannelHandler.registerWith(flutterEngine, context)
    }
}