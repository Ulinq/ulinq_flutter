package cc.ulinq.sdk

import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class UlinqSdkPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = binding
        channel = MethodChannel(binding.binaryMessenger, "ulinq/install_referrer")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getInstallReferrer" -> getInstallReferrer(result)
            "getPendingInstallToken" -> result.success(null)
            "updateSkAdConversionValue" -> result.success(false)
            else -> result.notImplemented()
        }
    }

    private fun getInstallReferrer(result: Result) {
        val context = pluginBinding?.applicationContext
        if (context == null) {
            result.success(null)
            return
        }

        val client = InstallReferrerClient.newBuilder(context).build()
        client.startConnection(object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                try {
                    if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                        val details = client.installReferrer
                        result.success(details.installReferrer)
                    } else {
                        result.success(null)
                    }
                } catch (_: Exception) {
                    result.success(null)
                } finally {
                    runCatching { client.endConnection() }
                }
            }

            override fun onInstallReferrerServiceDisconnected() {
                result.success(null)
                runCatching { client.endConnection() }
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pluginBinding = null
    }
}
