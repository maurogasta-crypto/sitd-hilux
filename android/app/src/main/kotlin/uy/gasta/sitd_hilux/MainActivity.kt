package uy.gasta.sitd_hilux

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.BatteryManager
import android.os.Build
import android.location.GnssStatus
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * El único código nativo del proyecto, y existe por una razón que ninguna
 * biblioteca de Dart puede cubrir: **cuántos satélites VE el receptor antes de
 * que exista una posición.**
 *
 * El 2026-09-16 el teléfono estuvo seis minutos a la intemperie con el permiso
 * dado, la ubicación del sistema encendida y cero posiciones — y además el
 * sistema no tenía NINGUNA posición conocida, ni de esta aplicación ni de otra.
 * Con eso, todo lo que pasa del lado de Dart ya está contestado y no alcanza:
 * `getPositionStream` es una llamada y después silencio, así que un registro de
 * ese intercambio diría «me suscribí y no llegó nada», que es lo que la pantalla
 * ya decía.
 *
 * `GnssStatus` es otra cosa: es el receptor contando qué satélites tiene a la
 * vista y con cuánta señal, **aunque no logre fijar ninguno**. Separa dos
 * mundos que hasta ahora se veían igual:
 *
 *  - ve satélites y no fija  → la efeméride está vieja (arranque en frío de
 *    verdad, que después de cruzar el mundo tarda muchos minutos, no uno) y lo
 *    que hay que hacer es esperar quieto a cielo abierto;
 *  - no ve ninguno           → la antena o la radio no están entregando, y eso
 *    no lo arregla ningún código de esta aplicación.
 *
 * Se pregunta por sondeo y no por un canal de eventos a propósito: la pantalla
 * de sensores ya se redibuja dos veces por segundo, así que un canal de eventos
 * agregaría una segunda cadencia para el mismo dibujo. Y si el canal no está
 * —una versión vieja, otra plataforma— el lado de Dart lo trata como «no
 * disponible» y sigue: esto diagnostica, no mide.
 */
class MainActivity : FlutterActivity() {
    private val canal = "uy.gasta.sitd_hilux/satelites"

    private var gestor: LocationManager? = null
    private var escucha: GnssStatus.Callback? = null

    private var vistos = 0
    private var usados = 0
    private var mejorCn0 = 0.0
    private var cn0: MutableList<Double> = mutableListOf()
    private var ultimoEvento = "sin arrancar"
    private var msDelUltimo = 0L
    private var huboPrimerFijado = false

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, canal).setMethodCallHandler {
            llamada, respuesta ->
            when (llamada.method) {
                "arrancar" -> respuesta.success(arrancar())
                "detener" -> {
                    detener()
                    respuesta.success(true)
                }
                "leer" -> respuesta.success(leer())
                else -> respuesta.notImplemented()
            }
        }
        // `sitd-37`: el micrófono (etapa E), lo que suena, y el cargador.
        EventChannel(engine.dartExecutor.binaryMessenger, "uy.gasta.sitd_hilux/audio")
            .setStreamHandler(Microfono())
        MethodChannel(engine.dartExecutor.binaryMessenger, "uy.gasta.sitd_hilux/audio_estado")
            .setMethodCallHandler { llamada, respuesta ->
                when (llamada.method) {
                    "ocupado" -> respuesta.success(ocupado())
                    "fuenteMicrofono" -> respuesta.success(fuenteMicrofono)
                    else -> respuesta.notImplemented()
                }
            }
        EventChannel(engine.dartExecutor.binaryMessenger, "uy.gasta.sitd_hilux/carga")
            .setStreamHandler(Cargador())
        // sitd-44 (hilux:D5): en qué teléfono se mide cada viaje. Sin permisos.
        MethodChannel(engine.dartExecutor.binaryMessenger, "uy.gasta.sitd_hilux/aparato")
            .setMethodCallHandler { llamada, respuesta ->
                if (llamada.method == "modelo") respuesta.success("${Build.MANUFACTURER} ${Build.MODEL}") else respuesta.notImplemented()
            }
        // sitd-57 (general:C4): le pasa a la Pizarra de ESTE teléfono el viaje en
        // vivo y lo que pasa, para que ella lo mande a la Pizarra cerca sin datos.
        // Una línea a su puerta local; si la Pizarra no está o no la deja, false.
        MethodChannel(engine.dartExecutor.binaryMessenger, "uy.gasta.sitd_hilux/enlace")
            .setMethodCallHandler { llamada, respuesta ->
                if (llamada.method != "enviar") { respuesta.notImplemented(); return@setMethodCallHandler }
                val json = llamada.argument<String>("mensaje")
                respuesta.success(try {
                    json != null && contentResolver.insert(
                        android.net.Uri.parse("content://com.maurogasta.pizarra.enlace/mensajes"),
                        android.content.ContentValues().apply { put("mensaje", json) },
                    ) != null
                } catch (e: Throwable) { false })
            }
    }

    /**
     * Si hay música sonando o una llamada. Sin permisos: `isMusicActive` y el
     * modo del audio los da el sistema a cualquiera. Si algo falla se contesta
     * «ocupado», que del lado de Dart quiere decir no escuchar.
     */
    private fun ocupado(): Map<String, Boolean> = try {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        mapOf(
            "musica" to am.isMusicActive,
            "llamada" to (am.mode == AudioManager.MODE_IN_CALL ||
                am.mode == AudioManager.MODE_IN_COMMUNICATION || am.mode == AudioManager.MODE_RINGTONE),
        )
    } catch (e: Exception) {
        mapOf("musica" to true, "llamada" to true)
    }

    /**
     * El micrófono, en trozos de un segundo de PCM de 16 bits (`sitd-37`).
     *
     * Lee en un hilo propio y manda cada trozo a Dart por el hilo principal,
     * que es el único por el que Flutter acepta eventos. **Nada se guarda
     * acá**: el trozo se manda y se suelta, y del lado de Dart se resume en
     * números (`regimen.dart`). Si falta el permiso o el micrófono está
     * tomado, se avisa con un error y el viaje sigue sin audio.
     */
    /** Con qué modo quedó abierto el micrófono la última vez (`sitd-47`). */
    @Volatile private var fuenteMicrofono: String? = null

    /**
     * Abre el micrófono con el modo SIN PROCESAR si el teléfono lo tiene
     * (`sitd-47`): VOICE_RECOGNITION está pensado para la voz y en el Note 9
     * no dejaba oír el ralentí (el encendido suena a 30 Hz, debajo de la voz).
     * Si el teléfono no lo declara o no abre, vuelve a VOICE_RECOGNITION.
     */
    private fun abrirGrabador(hz: Int, buffer: Int): AudioRecord {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val sinProcesar = try {
            am.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
        } catch (e: Exception) { false }
        if (sinProcesar) {
            try {
                val g = AudioRecord(MediaRecorder.AudioSource.UNPROCESSED, hz,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buffer)
                if (g.state == AudioRecord.STATE_INITIALIZED) { fuenteMicrofono = "sin procesar"; return g }
                g.release()
            } catch (e: IllegalArgumentException) { }
        }
        // VOICE_RECOGNITION trae el procesado mínimo de los demás (sin el
        // supresor de ruido de una llamada, que se comería el motor).
        val g = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, hz,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buffer)
        fuenteMicrofono = if (sinProcesar) "voz (el sin procesar no abrió)" else "voz (no tiene sin procesar)"
        return g
    }

    private inner class Microfono : EventChannel.StreamHandler {
        @Volatile private var corriendo = false
        private var hilo: Thread? = null

        override fun onListen(argumentos: Any?, sumidero: EventChannel.EventSink?) {
            if (sumidero == null || corriendo) return
            val hz = ((argumentos as? Map<*, *>)?.get("hz") as? Int) ?: 8000
            val principal = Handler(Looper.getMainLooper())
            corriendo = true
            hilo = Thread {
                var grabador: AudioRecord? = null
                try {
                    val minimo = AudioRecord.getMinBufferSize(hz, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                    grabador = abrirGrabador(hz, maxOf(minimo, hz * 2))
                    if (grabador.state != AudioRecord.STATE_INITIALIZED) throw IllegalStateException("el micrófono no se pudo abrir")
                    grabador.startRecording()
                    val trozo = ShortArray(hz)
                    while (corriendo) {
                        var leidas = 0
                        while (corriendo && leidas < trozo.size) {
                            val n = grabador.read(trozo, leidas, trozo.size - leidas)
                            if (n < 0) throw IllegalStateException("el micrófono devolvió $n")
                            leidas += n
                        }
                        if (!corriendo) break
                        val bytes = ByteArray(trozo.size * 2)
                        for (i in trozo.indices) {
                            bytes[2 * i] = (trozo[i].toInt() and 0xff).toByte()
                            bytes[2 * i + 1] = ((trozo[i].toInt() shr 8) and 0xff).toByte()
                        }
                        principal.post { if (corriendo) sumidero.success(bytes) }
                    }
                } catch (e: SecurityException) {
                    principal.post { sumidero.error("permiso", "falta el permiso del micrófono", null) }
                } catch (e: Exception) {
                    principal.post { sumidero.error("microfono", e.message ?: e.javaClass.simpleName, null) }
                } finally {
                    try { grabador?.stop() } catch (e: Exception) { }
                    grabador?.release()
                }
            }.apply { isDaemon = true; start() }
        }

        override fun onCancel(argumentos: Any?) {
            corriendo = false
            hilo = null
        }
    }

    /**
     * El cargador (`sitd-37`): el primer aviso dice cómo estaba («inicial»), y
     * después llega uno por cada vez que se enchufa o se desenchufa. Con el
     * cargador del encendedor de la camioneta, eso es el contacto puesto.
     */
    private inner class Cargador : EventChannel.StreamHandler {
        private var receptor: BroadcastReceiver? = null

        override fun onListen(argumentos: Any?, sumidero: EventChannel.EventSink?) {
            if (sumidero == null) return
            try {
                val estado = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val enchufado = (estado?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
                sumidero.success(mapOf("conectado" to enchufado, "inicial" to true))
                val r = object : BroadcastReceiver() {
                    override fun onReceive(c: Context?, i: Intent?) {
                        val conectado = i?.action == Intent.ACTION_POWER_CONNECTED
                        sumidero.success(mapOf("conectado" to conectado, "inicial" to false))
                    }
                }
                val filtro = IntentFilter().apply {
                    addAction(Intent.ACTION_POWER_CONNECTED)
                    addAction(Intent.ACTION_POWER_DISCONNECTED)
                }
                registerReceiver(r, filtro)
                receptor = r
            } catch (e: Exception) {
                sumidero.error("cargador", e.message ?: e.javaClass.simpleName, null)
            }
        }

        override fun onCancel(argumentos: Any?) {
            try { receptor?.let { unregisterReceiver(it) } } catch (e: Exception) { }
            receptor = null
        }
    }

    /**
     * Devuelve `false` si no se pudo enganchar. No lanza: que no haya cuenta de
     * satélites no puede impedir que se mida, y el lado de Dart tiene que poder
     * decir «no disponible» en vez de caerse.
     */
    private fun arrancar(): Boolean {
        if (escucha != null) return true
        return try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val cb =
                object : GnssStatus.Callback() {
                    override fun onStarted() {
                        ultimoEvento = "el motor GNSS arrancó"
                        msDelUltimo = SystemClock.elapsedRealtime()
                    }

                    override fun onStopped() {
                        ultimoEvento = "el motor GNSS se detuvo"
                        msDelUltimo = SystemClock.elapsedRealtime()
                    }

                    override fun onFirstFix(msHastaElPrimero: Int) {
                        huboPrimerFijado = true
                        ultimoEvento = "primer fijado a los $msHastaElPrimero ms"
                        msDelUltimo = SystemClock.elapsedRealtime()
                    }

                    override fun onSatelliteStatusChanged(estado: GnssStatus) {
                        var enUso = 0
                        var mejor = 0.0
                        val lista = mutableListOf<Double>()
                        for (i in 0 until estado.satelliteCount) {
                            val c = estado.getCn0DbHz(i).toDouble()
                            lista.add(c)
                            if (c > mejor) mejor = c
                            if (estado.usedInFix(i)) enUso++
                        }
                        lista.sortDescending()
                        vistos = estado.satelliteCount
                        usados = enUso
                        mejorCn0 = mejor
                        cn0 = lista.take(8).toMutableList()
                        msDelUltimo = SystemClock.elapsedRealtime()
                        if (!huboPrimerFijado) {
                            ultimoEvento = "contando satélites"
                        }
                    }
                }
            // La versión con Handler está desde la API 24 y este proyecto pide
            // 29, así que no hace falta el camino viejo con GpsStatus.
            val enganchado = lm.registerGnssStatusCallback(cb, Handler(Looper.getMainLooper()))
            if (!enganchado) return false
            gestor = lm
            escucha = cb
            ultimoEvento = "escuchando, todavía sin contar"
            msDelUltimo = SystemClock.elapsedRealtime()
            true
        } catch (e: SecurityException) {
            // Falta el permiso de ubicación fina. El lado de Dart ya lo dice
            // con sus palabras; acá sólo hay que no caerse.
            false
        } catch (e: Exception) {
            false
        }
    }

    private fun detener() {
        try {
            escucha?.let { gestor?.unregisterGnssStatusCallback(it) }
        } catch (e: Exception) {
            // Soltar algo que ya estaba suelto no es un problema.
        }
        escucha = null
        gestor = null
    }

    private fun leer(): Map<String, Any> {
        val desde =
            if (msDelUltimo == 0L) -1L else SystemClock.elapsedRealtime() - msDelUltimo
        return mapOf(
            "enganchado" to (escucha != null),
            "vistos" to vistos,
            "usados" to usados,
            "mejorCn0" to mejorCn0,
            "cn0" to cn0.toList(),
            "evento" to ultimoEvento,
            "msDelUltimo" to desde,
            "huboPrimerFijado" to huboPrimerFijado,
        )
    }

    override fun onDestroy() {
        detener()
        super.onDestroy()
    }
}
