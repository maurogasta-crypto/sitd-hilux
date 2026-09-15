import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/core/db/esquema.dart';

void main() {
  group('esquema (sin base)', () {
    test('la revision no encuentra problemas', () {
      expect(revisarEsquema(), isEmpty);
    });

    test('hay una migracion por version', () {
      expect(migraciones.length, versionEsquema);
    });

    test('ninguna migracion esta vacia', () {
      for (final paso in migraciones) {
        expect(paso, isNotEmpty);
      }
    });
  });

  group('migracion real', () {
    test('una base nueva queda en la ultima version con sus tablas', () {
      final b = Base.abrir(':memory:');
      addTearDown(b.cerrar);
      expect(b.version, versionEsquema);
      expect(b.tablas, containsAll(['ajustes', 'cargas', 'puntos', 'viajes']));
    });

    test('migrar dos veces no hace nada la segunda', () {
      final b = Base.abrir(':memory:');
      addTearDown(b.cerrar);
      final antes = b.tablas;
      // Volver a migrar sobre la misma conexion tiene que ser inocuo.
      expect(b.version, versionEsquema);
      expect(b.tablas, antes);
    });

    test('los ajustes se escriben, se leen y se pisan', () {
      final b = Base.abrir(':memory:');
      addTearDown(b.cerrar);
      expect(b.leerAjuste('factor'), isNull);
      b.escribirAjuste('factor', '1.05');
      expect(b.leerAjuste('factor'), '1.05');
      b.escribirAjuste('factor', '1.07');
      expect(b.leerAjuste('factor'), '1.07');
    });

    test('borrar un viaje se lleva sus puntos (foreign keys encendidas)', () {
      final b = Base.abrir(':memory:');
      addTearDown(b.cerrar);
      b.db.execute('INSERT INTO viajes (inicio) VALUES (1000)');
      final viaje = b.db.lastInsertRowId;
      b.db.execute(
        'INSERT INTO puntos (viaje, t, lat, lon, velocidad, precision_m) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [viaje, 1000, -34.9, -56.2, 20.0, 5.0],
      );
      expect(b.db.select('SELECT * FROM puntos').length, 1);
      b.db.execute('DELETE FROM viajes WHERE id = ?', [viaje]);
      expect(b.db.select('SELECT * FROM puntos'), isEmpty);
    });

    test('un punto huerfano se rechaza', () {
      final b = Base.abrir(':memory:');
      addTearDown(b.cerrar);
      expect(
        () => b.db.execute(
          'INSERT INTO puntos (viaje, t, lat, lon, velocidad, precision_m) '
          'VALUES (999, 1, 0, 0, 0, 1)',
        ),
        throwsA(anything),
      );
    });

    test('la moneda por defecto es UYU y no se mezcla sola', () {
      final b = Base.abrir(':memory:');
      addTearDown(b.cerrar);
      b.db.execute(
        'INSERT INTO cargas (t, litros, odo_tablero) VALUES (1, 50.0, 120000)',
      );
      final f = b.db.select('SELECT moneda FROM cargas').first;
      expect(f['moneda'], 'UYU');
    });
  });
}
