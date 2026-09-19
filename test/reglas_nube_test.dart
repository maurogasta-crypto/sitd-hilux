import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El banco de las reglas de Firestore.
///
/// No corren contra Firestore —eso necesitaría el emulador y una cadena de
/// Node— pero sí comprueban lo que se puede comprobar leyendo el archivo, que
/// resulta ser justo lo que más caro sale equivocar: que no se escape un UID
/// real a un repositorio público, y que las cuatro decisiones de fondo sigan
/// escritas.
void main() {
  late String reglas;

  setUpAll(() => reglas = File('firestore.rules').readAsStringSync());

  // La que importa más. Este repositorio es público.
  test('NO hay un solo UID real: los tres son marcadores', () {
    final uids = RegExp(r"uid == '([^']+)'")
        .allMatches(reglas)
        .map((m) => m.group(1)!)
        .toList();

    expect(uids, isNotEmpty, reason: 'si no hay ninguno, algo se borró');
    for (final u in uids) {
      expect(
        u,
        startsWith('UID-'),
        reason: 'ese UID parece real, y este repositorio es público',
      );
    }
  });

  test('el teléfono sólo puede CREAR: ni leer, ni pisar, ni borrar', () {
    expect(reglas, contains('allow create: if esElTelefono()'));
    // Leer no: si la credencial del APK se conoce —y hay que asumir que sí—,
    // quien la tenga no puede llevarse la historia.
    expect(reglas, isNot(contains('allow read: if esElTelefono')));
    // Un reporte subido es un hecho del pasado.
    expect(reglas, contains('allow update: if false'));
  });

  test('el agente lee y no escribe', () {
    expect(reglas, contains('allow read: if soyYo() || esElAgente()'));
    expect(reglas, isNot(contains('esElAgente() && request.resource')));
  });

  // Rige el deny por defecto: una colección nueva entra con su regla o queda
  // inaccesible. Es la regla del ecosistema y acá vale igual.
  test('hay cierre: lo que no está nombrado queda negado', () {
    expect(reglas, contains('match /{document=**}'));
    expect(reglas, contains('allow read, write: if false'));
  });

  test('se limita la forma y el tamaño de lo que entra', () {
    expect(
      reglas,
      contains(
        "hasOnly(\n                         ['json', 'sello', 'generado'])",
      ),
    );
    expect(reglas, contains('json.size() < 900000'));
  });
}
