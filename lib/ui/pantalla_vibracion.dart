import 'package:flutter/material.dart';

import '../features/vibracion/analisis.dart';
import '../features/vibracion/cobertura.dart';
import '../features/vibracion/espectro.dart';
import '../features/vibracion/registro_vibracion.dart';
import '../features/vibracion/ventana.dart';
import 'formato.dart';

/// Qué sabe la aplicación de cómo vibra esta camioneta.
///
/// La pantalla tiene que poder decir tres cosas distintas, y la tercera es la
/// que más cuesta: «todavía estoy aprendiendo», «está todo como siempre» y
/// «esto se repitió tres viajes seguidos». Un detector que sólo sabe decir las
/// dos primeras termina ignorado.
class PantallaVibracion extends StatelessWidget {
  final RegistroDeVibracion registro;

  const PantallaVibracion({super.key, required this.registro});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final porViaje = registro.porViaje();
    final ultimos = registro.ultimosViajes();
    final base = lineaBase(porViaje);
    final avisos = anomalias(porViaje, ultimos);
    final cubetas = base.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Vibración')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          if (avisos.isEmpty)
            _SinAvisos(
              hayBase: base.values.any((b) => b.suficiente),
              viajes: porViaje.length,
            )
          else
            for (final a in avisos) _Aviso(anomalia: a),
          const SizedBox(height: 16),
          _Cobertura(cobertura: cobertura(registro.ventanasPorCubeta())),
          const SizedBox(height: 16),
          Text('Lo que fue aprendiendo', style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Cada velocidad se compara sólo contra sí misma. Un desbalanceo a '
            '60 km/h está cerca de 8 Hz y a 110 cerca de 15: mezclarlas haría '
            'que todo pareciera una anomalía.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          if (cubetas.isEmpty)
            Text(
              'Todavía no hay ninguna medición. Se toman solas mientras un '
              'viaje está andando, arriba de '
              '${velocidadMinimaKmh.toStringAsFixed(0)} km/h.',
              style: t.textTheme.bodySmall,
            ),
          for (final c in cubetas) _Cubeta(base: base[c]!),
        ],
      ),
    );
  }
}

class _SinAvisos extends StatelessWidget {
  final bool hayBase;
  final int viajes;

  const _SinAvisos({required this.hayBase, required this.viajes});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hayBase ? Icons.check_circle : Icons.hourglass_bottom,
              color: hayBase ? Colors.green : t.colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hayBase ? 'Sin novedad' : 'Todavía aprendiendo',
                    style: t.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hayBase
                        ? 'La vibración de los últimos viajes se parece a la '
                              'de siempre. Se avisa sólo cuando algo se '
                              'repite $viajesSeguidosParaAvisar viajes '
                              'seguidos, y al terminar el viaje — nunca '
                              'manejando.'
                        : 'Hace falta juntar unos minutos a cada velocidad '
                              'antes de poder comparar: con poca historia, '
                              'cualquier cosa parece una anomalía. Van '
                              '$viajes ${viajes == 1 ? "viaje" : "viajes"} '
                              'con mediciones.',
                    style: t.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final Anomalia anomalia;

  const _Aviso({required this.anomalia});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      color: t.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Algo vibra distinto a ${nombreDeCubeta(anomalia.cubeta)}',
              style: t.textTheme.titleMedium?.copyWith(
                color: t.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              textoDeAnomalia(anomalia),
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El texto de un aviso, en un solo lugar: lo usan esta pantalla y el cartel
/// que sale al terminar el viaje, y son la misma frase.
///
/// **No dice qué está roto, dice dónde mirar.** Con un acelerómetro de
/// teléfono no se puede distinguir un desbalanceo de una rueda de una junta
/// homocinética gastada, y afirmarlo sería inventar. Lo que sí se puede decir
/// es a qué velocidad pasa, en qué frecuencia, cuánto cambió y desde cuándo.
String textoDeAnomalia(Anomalia a) {
  final veces = a.ultimo.normal <= 0
      ? null
      : (a.ultimo.ahora / a.ultimo.normal);
  // Desde `sitd-33` lo que se compara es la FORMA del espectro, no la
  // energía: `ahora` y `normal` son la parte de la vibración que se lleva esa
  // banda. Por eso la frase dice «se lleva más parte» y no «vibra más fuerte»
  // — un camino peor hace vibrar todo más fuerte, y eso a propósito no avisa.
  return 'Entre ${a.ultimo.rango}, esa zona de frecuencias se lleva '
      '${veces == null ? "más parte" : "${veces.toStringAsFixed(1).replaceAll('.', ',')} veces más parte"} '
      'de la vibración que lo habitual a esa velocidad, y se repitió en los '
      '${a.viajes} últimos viajes. Un camino peor no hace esto: sube todo '
      'parejo. No dice qué es: dice dónde mirar. En esa zona de frecuencias '
      'suelen estar las ruedas y lo que gira con ellas — balanceo, un '
      'neumático deformado, un semieje.';
}

class _Cubeta extends StatelessWidget {
  final LineaBase base;

  const _Cubeta({required this.base});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final maximo = base.mediana.fold<double>(0, (m, x) => x > m ? x : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  nombreDeCubeta(base.cubeta),
                  style: t.textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  base.suficiente
                      ? '${base.ventanas} mediciones'
                      : '${base.ventanas} de $ventanasParaLineaBase',
                  style: t.textTheme.labelSmall?.copyWith(
                    color: base.suficiente
                        ? t.colorScheme.outline
                        : t.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Un gráfico de barras hecho a mano: ocho números no justifican
            // traerse una biblioteca, y ésta tiene que dibujarse en un Helio
            // G85.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var b = 0; b < cantidadDeBandas; b++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: maximo <= 0
                                ? 2
                                : 6 + 44 * (base.mediana[b] / maximo),
                            decoration: BoxDecoration(
                              color: t.colorScheme.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bordesHz[b].toStringAsFixed(0),
                            style: t.textTheme.labelSmall?.copyWith(
                              color: t.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'hertz · ${formatearDuracion(base.ventanas * 5000)} de andar a '
              'esta velocidad',
              style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuánto sabe de cada velocidad, y a qué velocidad hay que salir a andar.
///
/// **Es la tarjeta que contesta «¿está todo bien o todavía no aprendió?».**
/// Sin ella, la pantalla en silencio significaba las dos cosas a la vez, que
/// es la peor forma de no decir nada. Y traduce «faltan 12 ventanas» a «falta
/// un minuto a esa velocidad», que es lo único con lo que alguien puede hacer
/// algo.
class _Cobertura extends StatelessWidget {
  final List<CoberturaDeCubeta> cobertura;

  const _Cobertura({required this.cobertura});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final listas = cobertura.where((c) => c.lista).length;
    final empezadas = cobertura.where((c) => c.ventanas > 0 && !c.lista);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cuánto aprendió', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              listas == 0
                  ? 'Ninguna velocidad tiene todavía suficiente historia. '
                        'Hasta que alguna la tenga, el silencio de arriba no '
                        'quiere decir que esté todo bien: quiere decir que no '
                        'sabe.'
                  : '$listas de ${cobertura.length} velocidades ya tienen '
                        'historia suficiente. En ésas, el silencio SÍ quiere '
                        'decir que está como siempre.',
              style: t.textTheme.bodySmall?.copyWith(
                color: listas == 0
                    ? t.colorScheme.tertiary
                    : t.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            for (final c in cobertura)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            nombreDeCubeta(c.cubeta),
                            style: t.textTheme.bodyMedium,
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: c.avance,
                              minHeight: 8,
                              color: c.lista
                                  ? t.colorScheme.primary
                                  : t.colorScheme.tertiary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${c.ventanas}/${c.necesarias}',
                          style: t.textTheme.labelSmall?.copyWith(
                            color: t.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    if (!c.lista)
                      Padding(
                        padding: const EdgeInsets.only(left: 96, top: 2),
                        child: Text(
                          c.comoVa,
                          style: t.textTheme.labelSmall?.copyWith(
                            color: t.colorScheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (empezadas.isEmpty && listas == 0)
              Text(
                'Una ventana son cinco segundos andando. Treinta ventanas '
                '—dos minutos y medio a esa velocidad— es lo mínimo para que '
                'la referencia no se mueva con cada viaje.',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
