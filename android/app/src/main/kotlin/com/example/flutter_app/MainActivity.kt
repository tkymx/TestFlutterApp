package com.example.flutter_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // HWCエラー対策: ハードウェアアクセラレーション設定
        try {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
            )
        } catch (e: Exception) {
            // ハードウェアアクセラレーションが利用できない場合のフォールバック
            android.util.Log.w("MainActivity", "Hardware acceleration not available: ${e.message}")
        }
    }
}
