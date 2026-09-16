import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/bitacora.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/core/registro_eventos.dart';

void main() {
  late Base base;
  late RegistroDeEventos eventos;

  setUp(() {
    base = Base.abrir(':memory:');
    eventos = RegistroDeEventos(base, capacidad: 5);
  });

  tearDown(() => base.cerrar());

  Anotacion a(int t, String texto, [Origen o = Origen.gps]) =>
      Anotacion(t: t, origen: o, texto: texto);

  test('guarda y devuelve del más viejo al más nuevo', () {
    eventos.guardar(a(100, 'uno', Origen.permiso));
    eventos.guardar(a(200, 'dos'));

    final l = eventos.ultimos();
    expect(l.length, 2);
    expect(l.first['texto'], 'uno');
    expect(l.first['origen'], 'permiso');
    expect(l.first['t'], 100);
    expect(l.last['texto'], 'dos');
  });

  test('ultimos(n) devuelve los n MÁS NUEVOS, no los primeros', () {
    for (var i = 0; i < 10; i++) {
      eventos.guardar(a(i, 'linea $i'));
    }
    final l = eventos.ultimos(3);
    expect(l.map((e) => e['texto']).toList(), [
      'linea 7',
      'linea 8',
      'linea 9',
    ]);
  });

  test('podar deja sólo la capacidad, y deja las más nuevas', () {
    for (var i = 0; i < 12; i++) {
      eventos.guardar(a(i, 'linea $i'));
    }
    eventos.podar();

    expect(eventos.cuantos, 5);
    expect(eventos.ultimos().first['texto'], 'linea 7');
    expect(eventos.ultimos().last['texto'], 'linea 11');
  });

  // Sin techo, una aplicación atornillada a una cabina llenaría la tarjeta con
  // su propio diagnóstico — que es la peor forma de perder los datos que sí
  // importan.
  test('poda sola pasadas cien escrituras, sin que nadie se lo pida', () {
    for (var i = 0; i < 100; i++) {
      eventos.guardar(a(i, 'linea $i'));
    }
    expect(eventos.cuantos, 5);
  });

  test('limpiar la deja vacía', () {
    eventos.guardar(a(1, 'algo'));
    eventos.limpiar();
    expect(eventos.cuantos, 0);
    expect(eventos.ultimos(), isEmpty);
  });

  // Ésta es la razón de existir del archivo: el primer reporte real salió con
  // la bitácora vacía porque vivía en memoria y se generó dos horas después.
  test('lo anotado sobrevive a que se caiga la Bitacora de memoria', () {
    final b = Bitacora(reloj: () => 42)..alDisco = eventos.guardar;
    b.anotar(Origen.viaje, 'empezó el viaje');
    b.anotar(Origen.gps, 'llegó la primera');

    // Otra corrida de la aplicación: la memoria arranca vacía.
    final nueva = Bitacora(reloj: () => 99);
    expect(nueva.cuantas, 0);
    // Pero el disco sigue ahí.
    expect(eventos.cuantos, 2);
    expect(eventos.ultimos().first['texto'], 'empezó el viaje');
  });

  test('si el disco falla, la Bitacora no se cae', () {
    final b = Bitacora(reloj: () => 0)
      ..alDisco = (_) => throw StateError('base cerrada');

    expect(() => b.anotar(Origen.sistema, 'algo'), returnsNormally);
    // Y lo sigue teniendo en memoria, que es lo que se ve en pantalla.
    expect(b.cuantas, 1);
  });

  test('la tabla existe en el esquema que se crea de cero', () {
    expect(base.tablas, contains('eventos'));
  });
}
