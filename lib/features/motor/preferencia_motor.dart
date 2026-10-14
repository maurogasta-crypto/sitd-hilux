import '../../core/db/base.dart';

/// El interruptor «Empezar y terminar con el motor» (`sitd-37`). Encendido de
/// fábrica: lo pidió Mauro. Vive en `ajustes`, que es de ESTE teléfono y no
/// viaja en un respaldo — el cargador de la Hilux es de la Hilux.
class PreferenciaMotor {
  final Base base;
  static const String _clave = 'viaje_con_el_motor';

  PreferenciaMotor(this.base);

  bool get activa => (base.leerAjuste(_clave) ?? 'si') == 'si';
  set activa(bool v) => base.escribirAjuste(_clave, v ? 'si' : 'no');
}
