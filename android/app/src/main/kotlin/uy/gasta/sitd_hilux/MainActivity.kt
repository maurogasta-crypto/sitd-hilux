package uy.gasta.sitd_hilux

import android.content.Context
import android.location.GnssStatus
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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
