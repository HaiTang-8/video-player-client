package com.mediaserver.nativeplayer

import io.flutter.embedding.engine.plugins.FlutterPlugin

class NativePlayerPlugin : FlutterPlugin {
  private var host: NativePlayerHost? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val host =
      NativePlayerHost(
        binding.applicationContext,
        NativePlayerEventsApi(binding.binaryMessenger),
        binding.flutterAssets::getAssetFilePathByName,
      )
    NativePlayerHostApi.setUp(binding.binaryMessenger, host)
    binding.platformViewRegistry.registerViewFactory(
      NativeVideoViewFactory.VIEW_TYPE,
      NativeVideoViewFactory(host),
    )
    this.host = host
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    NativePlayerHostApi.setUp(binding.binaryMessenger, null)
    host?.disposeAll()
    host = null
  }
}
