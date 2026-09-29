package ru.studio37.kopilych

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicLong

class MainActivity : FlutterActivity() {
    private val channelName = "ru.studio37.kopilych/offline_tts"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sequence = AtomicLong()
    private var tts: TextToSpeech? = null
    private var ready = false
    private var generation = 0
    private val pending = mutableMapOf<String, MethodChannel.Result>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "synthesize" -> {
                        val text = call.argument<String>("text")
                        val path = call.argument<String>("path")
                        if (text.isNullOrBlank() || path.isNullOrBlank()) {
                            result.error("INVALID_INPUT", "Missing text or output path", null)
                        } else {
                            synthesize(text, path, result)
                        }
                    }
                    "stop" -> {
                        generation++
                        tts?.stop()
                        failPending("STOPPED", "Speech stopped")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun synthesize(text: String, path: String, result: MethodChannel.Result) {
        val engine = tts
        if (engine == null) {
            val requestGeneration = generation
            tts = TextToSpeech(applicationContext) { status ->
                mainHandler.post {
                    if (requestGeneration != generation) {
                        tts?.shutdown()
                        tts = null
                        ready = false
                        result.error("STOPPED", "Speech stopped", null)
                        return@post
                    }
                    ready = status == TextToSpeech.SUCCESS
                    if (!ready) {
                        tts?.shutdown()
                        tts = null
                        result.error("TTS_UNAVAILABLE", "Android speech engine unavailable", null)
                    } else {
                        synthesizeReady(text, path, result)
                    }
                }
            }
        } else if (ready) {
            synthesizeReady(text, path, result)
        } else {
            result.error("TTS_STARTING", "Android speech engine is starting", null)
        }
    }

    private fun synthesizeReady(text: String, path: String, result: MethodChannel.Result) {
        val engine = tts ?: run {
            result.error("TTS_UNAVAILABLE", "Android speech engine unavailable", null)
            return
        }
        val voice = engine.voices
            ?.filter { it.locale.language == "ru" && !it.isNetworkConnectionRequired }
            ?.maxByOrNull { it.quality }
        if (voice == null || engine.setVoice(voice) == TextToSpeech.ERROR) {
            result.error("NO_OFFLINE_RUSSIAN_VOICE", "No installed offline Russian speech voice", null)
            return
        }
        val id = "speech-${sequence.incrementAndGet()}"
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String) = Unit
            override fun onDone(utteranceId: String) = finish(utteranceId, null)
            override fun onError(utteranceId: String) = finish(utteranceId, "Speech synthesis failed")
            override fun onError(utteranceId: String, errorCode: Int) =
                finish(utteranceId, "Speech synthesis failed ($errorCode)")
        })
        pending[id] = result
        val status = engine.synthesizeToFile(text, Bundle.EMPTY, File(path), id)
        if (status == TextToSpeech.ERROR) finish(id, "Speech synthesis could not start")
    }

    private fun finish(id: String, error: String?) {
        mainHandler.post {
            val result = pending.remove(id) ?: return@post
            if (error == null) result.success(null)
            else result.error("SYNTHESIS_FAILED", error, null)
        }
    }

    private fun failPending(code: String, message: String) {
        pending.values.forEach { it.error(code, message, null) }
        pending.clear()
    }

    override fun onDestroy() {
        generation++
        tts?.stop()
        failPending("DESTROYED", "Speech engine closed")
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
