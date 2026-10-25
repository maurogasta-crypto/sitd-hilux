import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/db/base.dart';
import '../features/audio/fuente_audio.dart';
import '../features/audio/regimen.dart';
import '../features/calibracion/calibracion.dart';
import '../features/calibracion/prueba_motor.dart';
import '../features/vibracion/fuente_vibracion.dart';
import '../features/vibracion/rueda.dart';
import '../features/vibracion/ventana.dart';
import 'formato.dart';

/// La pantalla de CALIBRACIÓN (`sitd-45`).
///
/// Lo pidió Mauro el 2026-10-25: «un botón que diga calibración. En esa
/// pantalla darán el registro de todos los datos que pueden hacerse en garage
/// antes de arrancar un viaje». Junta lo que se mide parado —la vuelta de la
/// rueda, la prueba con un peso, el motor a RPM conocidas— y lo guarda como
/// REFERENCIA en `calibraciones`, que viaja en el reporte.
///
/// **No mide andando**: lo que se mide andando es un viaje. La prueba del peso
/// sólo marca de cuándo a cuándo hay un peso puesto; lo que se mide en ese
/// tramo lo miden los viajes de siempre, y la ronda los cruza por la hora.
class PantallaCalibracion extends StatefulWidget {
  final Base base;

  /// Si hay un viaje midiendo: la prueba del motor necesita el acelerómetro y
  /// el micrófono para ella sola, y además se hace parado.
  final bool hayViajeMidiendo;

  const PantallaCalibracion({
    super.key,
    required this.base,
    this.hayViajeMidiendo = false,
  });

  @override
  State<PantallaCalibracion> createState() => _PantallaCalibracionState();
}

class _PantallaCalibracionState extends State<PantallaCalibracion> {
  late final RegistroDeCalibraciones _registro = RegistroDeCalibraciones(
    widget.base,
  );
  final _vueltas = TextEditingController(text: '10');
  final _metros = TextEditingController();
  final _presion = TextEditingController();
  final _carga = TextEditingController();
  final _gramos = TextEditingController();
  final _donde = TextEditingController();
  String _rueda = ruedas.first;
  String? _problemaRueda;

  @override
  void dispose() {
    for (final c in [_vueltas, _metros, _presion, _carga, _gramos, _donde]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _numero(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _guardarRueda() {
    final r = medidaDeRueda(
      vueltas: _numero(_vueltas),
      metros: _numero(_metros),
      presionPsi: _numero(_presion),
      carga: _carga.text,
    );
    if (r.datos == null) {
      setState(() => _problemaRueda = r.problema);
      return;
    }
    _registro.guardar(
      Calibracion(
        tipo: 'rueda',
        inicio: DateTime.now().millisecondsSinceEpoch,
        fin: DateTime.now().millisecondsSinceEpoch,
        datos: r.datos!,
      ),
    );
    _registro.aplicarRueda();
    _metros.clear();
    setState(() => _problemaRueda = null);
    _contar(
      'Guardada: ${_coma(r.datos!['circunferenciaM'] as double, 3)} m '
      'por vuelta. Desde ahora la usa la lectura de la vibración.',
    );
  }

  void _empezarPeso() {
    final gramos = _numero(_gramos);
    if (gramos == null || gramos <= 0) {
      _contar('Falta cuántos gramos tiene el peso.');
      return;
    }
    _registro.guardar(
      Calibracion(
        tipo: 'peso',
        inicio: DateTime.now().millisecondsSinceEpoch,
        datos: {
          'rueda': _rueda,
          'gramos': gramos,
          if (_donde.text.trim().isNotEmpty) 'donde': _donde.text.trim(),
        },
      ),
    );
    setState(() {});
    _contar('Prueba con peso en curso. Los viajes de ahora quedan marcados.');
  }

  void _terminarPeso(Calibracion c) {
    _registro.cerrar(c.id!, DateTime.now().millisecondsSinceEpoch);
    setState(() {});
    _contar('Prueba con peso terminada. Ahora un viaje igual, sin peso.');
  }

  void _contar(String texto) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _probarMotor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PantallaPruebaMotor(registro: _registro),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final peso = _registro.pesoEnCurso();
    final ruedasMedidas = _registro.ultimas(tipo: 'rueda', cuantas: 5);
    final pesos = _registro.ultimas(tipo: 'peso', cuantas: 5);
    final motores = _registro.ultimas(tipo: 'motor', cuantas: 5);
    final gris = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline);

    return Scaffold(
      appBar: AppBar(title: const Text('Calibración')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(
            'Lo que se mide parado, en el garage, para leer después los '
            'viajes. Queda guardado como referencia y viaja en el reporte.',
            style: gris,
          ),
          const SizedBox(height: 12),
          _Tarjeta(
            titulo: 'Antes de un viaje de prueba',
            hijos: [
              for (final paso in const [
                'El teléfono en su soporte de siempre, firme. Si cambiás el '
                    'soporte, anotalo en Sensores → «Probar la medición».',
                'La presión de las cubiertas, la de siempre (anotala abajo '
                    'cuando midas la rueda).',
                'Qué carga lleva la camioneta: vacía, con gente, con carga.',
                'Si hay un peso puesto en una rueda, que la prueba esté '
                    'empezada acá (punto 2).',
                'Al empezar el viaje, el odómetro del tablero.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $paso'),
                ),
            ],
          ),
          _Tarjeta(
            titulo: '1 · Cuánto avanza por vuelta de rueda',
            hijos: [
              Text(
                'Con carga liviana y la presión de siempre: marcá con tiza la '
                'cubierta y el piso donde apoya. Avanzá despacio en línea '
                'recta hasta que la marca de la cubierta vuelva abajo, tantas '
                'vueltas como puedas (10 es un buen número), y marcá el piso. '
                'Medí con cinta entre la primera y la última marca. Mejor dos '
                'o tres veces.',
              ),
              const SizedBox(height: 8),
              Text(
                circunferenciaEsMedida
                    ? 'Hoy usa la MEDIDA: ${_coma(circunferencia, 3)} m '
                          'por vuelta.'
                    : 'Hoy usa el diámetro de siempre (76 cm): '
                          '${_coma(circunferencia, 3)} m por vuelta.',
                style: gris,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _Campo(_vueltas, 'Vueltas', numero: true)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Campo(_metros, 'Metros medidos', numero: true),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _Campo(_presion, 'Presión (psi)', numero: true),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _Campo(_carga, 'Carga (ej.: vacía)')),
                ],
              ),
              if (_problemaRueda != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _problemaRueda!,
                    style: TextStyle(color: t.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _guardarRueda,
                child: const Text('Guardar la medida'),
              ),
              for (final c in ruedasMedidas)
                _Renglon(
                  texto:
                      '${formatearFecha(c.inicio)} · ${c.datos['vueltas']} '
                      'vueltas = ${c.datos['metros']} m → '
                      '${c.datos['circunferenciaM']} m'
                      '${c.datos['presionPsi'] != null ? ' · ${c.datos['presionPsi']} psi' : ''}'
                      '${c.datos['carga'] != null ? ' · ${c.datos['carga']}' : ''}',
                  alBorrar: () {
                    _registro.borrar(c.id!);
                    _registro.aplicarRueda();
                    setState(() {});
                  },
                ),
            ],
          ),
          _Tarjeta(
            titulo: '2 · Desbalanceo: una prueba con un peso',
            hijos: [
              const Text(
                'Sirve para saber si la app ve un desbalanceo de verdad. '
                'En orden:',
              ),
              for (final (i, paso) in const [
                'Un viaje SIN peso por un tramo que puedas repetir, a '
                    'velocidades parejas (60, 80, y 100 si es seguro).',
                'Poné el peso en la llanta: una pesa de balanceo bien pegada '
                    'o de clip, de 30 a 60 g. Anotá en qué rueda y cuántos '
                    'gramos.',
                'Tocá «Empezar la prueba» acá abajo.',
                'El MISMO tramo, a las mismas velocidades.',
                'Sacá el peso y tocá «Terminar: saqué el peso».',
                'Otro viaje igual sin peso, para ver que vuelve a lo normal.',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${i + 1}. $paso'),
                ),
              const SizedBox(height: 6),
              Text(
                'Nunca un peso suelto: en una rueda que gira es peligroso.',
                style: TextStyle(color: t.colorScheme.error),
              ),
              const SizedBox(height: 10),
              if (peso != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '⚖️ En curso desde las ${formatearHora(peso.inicio)}: '
                    '${peso.datos['gramos']} g en la ${peso.datos['rueda']}'
                    '${peso.datos['donde'] != null ? ' (${peso.datos['donde']})' : ''}. '
                    'Lo que midan los viajes ahora queda «con peso».',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => _terminarPeso(peso),
                  child: const Text('Terminar: saqué el peso'),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: _rueda,
                  decoration: const InputDecoration(labelText: 'Rueda'),
                  items: [
                    for (final r in ruedas)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (r) => setState(() => _rueda = r ?? _rueda),
                ),
                Row(
                  children: [
                    Expanded(child: _Campo(_gramos, 'Gramos', numero: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _Campo(_donde, 'Dónde (opcional)')),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _empezarPeso,
                  child: const Text('Empezar la prueba'),
                ),
              ],
              for (final c in pesos.where((c) => !c.abierta))
                _Renglon(
                  texto:
                      '${formatearFechaYHora(c.inicio)} → '
                      '${formatearHora(c.fin!)} · ${c.datos['gramos']} g, '
                      '${c.datos['rueda']}',
                  alBorrar: () {
                    _registro.borrar(c.id!);
                    setState(() {});
                  },
                ),
            ],
          ),
          _Tarjeta(
            titulo: '3 · El motor parado: ralentí, 1000, 1500 y 2000 RPM',
            hijos: [
              const Text(
                'Camioneta estacionada, freno de mano y en punto muerto, el '
                'teléfono en su soporte de siempre y sin música. La app te va '
                'diciendo qué RPM sostener con el tacómetro y cuánto tiempo: '
                'casi cuatro minutos. Guarda cómo vibra y cómo suena '
                'el motor solo, sin camino, como referencia para los viajes.',
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: widget.hayViajeMidiendo ? null : _probarMotor,
                icon: const Icon(Icons.speed),
                label: const Text('Empezar la prueba del motor'),
              ),
              if (widget.hayViajeMidiendo)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Hay un viaje midiendo: pausalo o terminalo antes. La '
                    'prueba usa el acelerómetro y el micrófono para ella sola.',
                    style: gris,
                  ),
                ),
              for (final c in motores)
                _Renglon(
                  texto:
                      '${formatearFechaYHora(c.inicio)} · '
                      '${_resumenMotor(c)}',
                  alBorrar: () {
                    _registro.borrar(c.id!);
                    setState(() {});
                  },
                ),
            ],
          ),
          _Tarjeta(
            titulo: 'Para sumar más adelante',
            hijos: [
              for (final idea in const [
                'Motor apagado, teléfono en el soporte, un minuto quieto: el '
                    'ruido propio del sensor y del soporte.',
                'Unos golpecitos en el soporte: su resonancia propia (¿es el '
                    'pico fijo de 4 a 6 Hz?).',
                'Aire acondicionado o ventilador prendido a ralentí: su '
                    'zumbido, para no confundirlo con el motor.',
                'Rodar en punto muerto por una bajada suave: la rueda y el '
                    'camino sin el motor.',
                'La vuelta de la rueda con la camioneta cargada: cuánto cambia '
                    'con el peso.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $idea', style: gris),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _resumenMotor(Calibracion c) {
    final pasos = (c.datos['pasos'] as List?) ?? const [];
    if (pasos.isEmpty) return 'sin datos';
    return [
      for (final p in pasos.whereType<Map>())
        '${p['paso']}${p['rpmOida'] != null ? ' (oye ${p['rpmOida']})' : ''}',
    ].join(' · ');
  }
}

/// La prueba del motor, paso por paso, con el reloj a la vista.
class PantallaPruebaMotor extends StatefulWidget {
  final RegistroDeCalibraciones registro;

  const PantallaPruebaMotor({super.key, required this.registro});

  @override
  State<PantallaPruebaMotor> createState() => _PantallaPruebaMotorState();
}

enum _Fase { lista, acomodo, midiendo, terminada }

class _PantallaPruebaMotorState extends State<PantallaPruebaMotor> {
  _Fase _fase = _Fase.lista;
  int _paso = 0;
  int _quedan = 0;
  Timer? _reloj;
  StreamSubscription<Sacudon>? _vib;
  StreamSubscription<List<int>>? _mic;
  bool _sinMicrofono = false;
  int _inicio = 0;

  // Lo del paso que se está midiendo.
  final List<double> _magnitud = [];
  int _desde = 0;
  final List<VentanaVibracion> _ventanas = [];
  final List<LecturaMotor> _escuchas = [];
  LecturaMotor? _ultimaEscucha;
  VentanaVibracion? _ultimaVentana;
  final List<Map<String, dynamic>> _resumenes = [];

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  void _soltar() {
    _reloj?.cancel();
    _vib?.cancel();
    _mic?.cancel();
    _vib = null;
    _mic = null;
  }

  Future<void> _empezar() async {
    var permiso = await Permission.microphone.status;
    if (permiso.isDenied) permiso = await Permission.microphone.request();
    _sinMicrofono = !permiso.isGranted;
    _inicio = DateTime.now().millisecondsSinceEpoch;
    _vib = Acelerometro().sacudones.listen(_alSacudon, onError: (_) {});
    if (!_sinMicrofono) {
      try {
        _mic = MicrofonoDelTelefono().trozos().listen(
          _alTrozo,
          onError: (_) => setState(() => _sinMicrofono = true),
        );
      } catch (_) {
        _sinMicrofono = true;
      }
    }
    _arrancarPaso(0);
  }

  void _arrancarPaso(int i) {
    _paso = i;
    _magnitud.clear();
    _ventanas.clear();
    _escuchas.clear();
    _fase = _Fase.acomodo;
    _quedan = pasosDelMotor[i].acomodo;
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) => _tic());
    setState(() {});
  }

  void _tic() {
    if (!mounted) return;
    setState(() => _quedan--);
    if (_quedan > 0) return;
    if (_fase == _Fase.acomodo) {
      _fase = _Fase.midiendo;
      _quedan = pasosDelMotor[_paso].segundos;
      _magnitud.clear();
      _desde = DateTime.now().millisecondsSinceEpoch;
    } else if (_fase == _Fase.midiendo) {
      _cerrarVentana(DateTime.now().millisecondsSinceEpoch);
      _resumenes.add(
        resumirPaso(pasosDelMotor[_paso], [..._ventanas], [..._escuchas]),
      );
      if (_paso + 1 < pasosDelMotor.length) {
        _arrancarPaso(_paso + 1);
      } else {
        _terminar();
      }
    }
  }

  void _alSacudon(Sacudon s) {
    if (_fase != _Fase.midiendo) return;
    _magnitud.add(s.magnitud);
    if (s.t - _desde >= 5000) _cerrarVentana(s.t);
  }

  void _cerrarVentana(int hasta) {
    final v = armarVentana(
      magnitud: [..._magnitud],
      tInicio: _desde,
      tFin: hasta,
      cubeta: cubetaParado,
    );
    if (v != null) {
      _ventanas.add(v);
      _ultimaVentana = v;
    }
    _magnitud.clear();
    _desde = hasta;
  }

  void _alTrozo(List<int> pcm) {
    final l = leerMotor(pcm);
    _ultimaEscucha = l;
    if (_fase == _Fase.midiendo) _escuchas.add(l);
  }

  void _terminar() {
    _soltar();
    widget.registro.guardar(
      Calibracion(
        tipo: 'motor',
        inicio: _inicio,
        fin: DateTime.now().millisecondsSinceEpoch,
        datos: {'pasos': _resumenes, if (_sinMicrofono) 'sinMicrofono': true},
      ),
    );
    setState(() => _fase = _Fase.terminada);
  }

  void _cancelar() {
    _soltar();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final paso = pasosDelMotor[_paso];
    return Scaffold(
      appBar: AppBar(title: const Text('Prueba del motor')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (_fase) {
          _Fase.lista => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Antes de empezar: camioneta estacionada, freno de mano, en '
                'punto muerto, el teléfono en su soporte de siempre y sin '
                'música. Prendé el motor.',
              ),
              const SizedBox(height: 12),
              for (final p in pasosDelMotor)
                Text('• ${p.titulo}: ${p.segundos} s'),
              const SizedBox(height: 20),
              FilledButton(onPressed: _empezar, child: const Text('Empezar')),
            ],
          ),
          _Fase.terminada => ListView(
            children: [
              Text('Listo, quedó guardada.', style: t.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final r in _resumenes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${r['paso']}: ${r['ventanas']} ventanas, '
                    '${r['escuchasConRpm']} de ${r['escuchas']} escuchas con '
                    'RPM${r['rpmOida'] != null ? ' (oye ${r['rpmOida']})' : ''}'
                    '${r['encendidoEnVibracion'] == true ? ' · el motor se ve en la vibración' : ''}',
                  ),
                ),
              if (_sinMicrofono)
                const Text('Sin permiso del micrófono: sólo la vibración.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Volver'),
              ),
            ],
          ),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Paso ${_paso + 1} de ${pasosDelMotor.length}',
                style: t.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                paso.titulo,
                style: t.textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                paso.instruccion,
                style: t.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                _fase == _Fase.acomodo
                    ? 'Llegá al régimen… mido en $_quedan s'
                    : 'Midiendo · quedan $_quedan s',
                style: t.textTheme.headlineSmall?.copyWith(
                  color: _fase == _Fase.midiendo ? t.colorScheme.primary : null,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                _sinMicrofono
                    ? 'Sin micrófono: sólo vibración.'
                    : _ultimaEscucha?.rpm != null
                    ? 'La app oye unas ${_ultimaEscucha!.rpm!.round()} RPM'
                    : 'La app todavía no distingue el motor',
                textAlign: TextAlign.center,
              ),
              if (_ultimaVentana != null)
                Text(
                  'Vibración: ${_ultimaVentana!.hz.toStringAsFixed(0)} Hz de '
                  'muestreo, ${_coma(_ultimaVentana!.rms, 3)} de '
                  'intensidad',
                  textAlign: TextAlign.center,
                ),
              const Spacer(),
              OutlinedButton(
                onPressed: _cancelar,
                child: const Text('Cancelar (no guarda nada)'),
              ),
            ],
          ),
        },
      ),
    );
  }
}

/// Un número como se escribe acá: con coma.
String _coma(double x, int decimales) =>
    x.toStringAsFixed(decimales).replaceAll('.', ',');

class _Tarjeta extends StatelessWidget {
  final String titulo;
  final List<Widget> hijos;

  const _Tarjeta({required this.titulo, required this.hijos});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...hijos,
        ],
      ),
    ),
  );
}

class _Campo extends StatelessWidget {
  final TextEditingController controlador;
  final String etiqueta;
  final bool numero;

  const _Campo(this.controlador, this.etiqueta, {this.numero = false});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controlador,
    keyboardType: numero
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(labelText: etiqueta),
  );
}

class _Renglon extends StatelessWidget {
  final String texto;
  final VoidCallback alBorrar;

  const _Renglon({required this.texto, required this.alBorrar});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(texto, style: Theme.of(context).textTheme.bodySmall),
      ),
      IconButton(
        tooltip: 'Borrar',
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: alBorrar,
      ),
    ],
  );
}
