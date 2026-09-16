import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/bitacora.dart';

void main() {
  test('anota con el reloj inyectado y en orden', () {
    var t = 1000;
    final b = Bitacora(reloj: () => t);
    b.anotar(Origen.gps, 'uno');
    t = 2000;
    b.anotar(Origen.permiso, 'dos');

    expect(b.cuantas, 2);
    expect(b.anotaciones.first.texto, 'uno');
    expect(b.anotaciones.first.t, 1000);
    expect(b.anotaciones.last.origen, Origen.permiso);
    expect(b.anotaciones.last.t, 2000);
    // En pantalla se lee al revés: lo último arriba.
    expect(b.alReves.first.texto, 'dos');
  });

  test('es un ANILLO: pasada la capacidad se caen las viejas', () {
    final b = Bitacora(capacidad: 3, reloj: () => 0);
    for (var i = 0; i < 10; i++) {
      b.anotar(Origen.gps, 'linea $i');
    }

    expect(b.cuantas, 3);
    expect(b.anotaciones.map((a) => a.texto).toList(), [
      'linea 7',
      'linea 8',
      'linea 9',
    ]);
  });

  test('anotarSiCambio descarta la repetida seguida, no la que vuelve', () {
    final b = Bitacora(reloj: () => 0);
    b.anotarSiCambio(Origen.satelites, 've 0');
    b.anotarSiCambio(Origen.satelites, 've 0');
    b.anotarSiCambio(Origen.satelites, 've 0');
    expect(b.cuantas, 1);

    b.anotarSiCambio(Origen.satelites, 've 4');
    b.anotarSiCambio(Origen.satelites, 've 0');
    // La tercera vuelve a «ve 0» pero no está pegada a la anterior igual, así
    // que entra: si no, se perdería el ida y vuelta, que es justo lo que se
    // quiere ver.
    expect(b.cuantas, 3);
  });

  test('el mismo texto con otro origen no es una repetición', () {
    final b = Bitacora(reloj: () => 0);
    b.anotarSiCambio(Origen.gps, 'listo');
    b.anotarSiCambio(Origen.permiso, 'listo');
    expect(b.cuantas, 2);
  });

  test('limpiar la deja vacía y avisa', () {
    final b = Bitacora(reloj: () => 0);
    b.anotar(Origen.gps, 'algo');
    final antes = b.cambios.value;
    b.limpiar();
    expect(b.cuantas, 0);
    expect(b.cambios.value, greaterThan(antes));
  });

  test('cada anotación sube el contador que escucha la pantalla', () {
    final b = Bitacora(reloj: () => 0);
    expect(b.cambios.value, 0);
    b.anotar(Origen.gps, 'a');
    b.anotar(Origen.gps, 'b');
    expect(b.cambios.value, 2);
  });

  test('la lista que devuelve no se puede modificar desde afuera', () {
    final b = Bitacora(reloj: () => 0);
    b.anotar(Origen.gps, 'a');
    expect(
      () => b.anotaciones.add(
        const Anotacion(t: 0, origen: Origen.gps, texto: 'colado'),
      ),
      throwsUnsupportedError,
    );
  });

  test('se serializa a JSON con los tres campos y nada más', () {
    final b = Bitacora(reloj: () => 77);
    b.anotar(Origen.viaje, 'empezó');
    final m = b.aMapa();

    expect(m, [
      {'t': 77, 'origen': 'viaje', 'texto': 'empezó'},
    ]);
    // Tiene que poder viajar en el reporte.
    expect(jsonEncode(m), contains('empezó'));
  });

  test('cada origen tiene su nombre para leer', () {
    for (final o in Origen.values) {
      expect(nombreDeOrigen(o), isNotEmpty);
    }
  });

  test('la bitácora global existe y es usable sin construir nada', () {
    final antes = bitacora.cuantas;
    bitacora.anotar(Origen.sistema, 'prueba del banco');
    expect(bitacora.cuantas, antes + 1);
    expect(bitacora.alReves.first.texto, 'prueba del banco');
  });
}
