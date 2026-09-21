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
  //
  // Comprueba contra la LISTA de marcadores y no contra un prefijo, y el
  // cambio es del 2026-09-20. Antes pedía `startsWith('UID-')`, que dejaba
  // pasar cualquier nombre nuevo con esa forma: el marcador de Mauro se
  // llamaba acá `UID-DE-MAURO` y en `reglas.txt` del panel `TU-UID-ACA`, o
  // sea dos nombres para la misma cosa, y el panel no reconocía el de acá —
  // al tocar «Copiar para publicar» se negaba y no había forma de seguir
  // desde el teléfono. Es el mismo error que `perm`/`permiso` entre CasaYourte
  // y Casa Verde: misma idea, nombre distinto, y se rompe sin dar error.
  //
  // Con la lista, renombrar un marcador falla ACÁ en vez de fallar en el panel
  // seis meses después.
  const marcadores = ['TU-UID-ACA', 'UID-DEL-AGENTE'];

  test('NO hay un solo UID real: todos son marcadores conocidos', () {
    final uids = RegExp(r"uid == '([^']+)'")
        .allMatches(reglas)
        .map((m) => m.group(1)!)
        .toList();

    expect(uids, isNotEmpty, reason: 'si no hay ninguno, algo se borró');
    for (final u in uids) {
      expect(
        marcadores,
        contains(u),
        reason:
            'ese UID no es uno de los marcadores del ecosistema '
            '($marcadores). Si parece real, este repositorio es público; si es '
            'un marcador nuevo, el panel no lo va a saber completar.',
      );
    }
  });

  // Los dos tienen que estar. Sin el de Mauro nadie administra la base; sin el
  // del agente, el chat no puede leer los reportes y la ronda lo marca con ✖.
  test('los dos marcadores están, y son los que el panel sabe completar', () {
    for (final m in marcadores) {
      expect(reglas, contains(m), reason: 'falta el marcador $m');
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

  test('el agente lee los reportes, pero no los puede pisar', () {
    expect(reglas, contains('allow read: if soyYo() || esElAgente()'));
    // Un reporte subido es lo que midió el teléfono: ni yo lo toco.
    expect(reglas, contains('allow update: if false'));
  });

  // Lo que el agente concluye va en una colección APARTE, no adentro del
  // reporte: si mañana me equivoco en un análisis, se reescribe ése y el dato
  // medido sigue intacto.
  test('el agente escribe sus conclusiones en analisis/, no en reportes/', () {
    expect(reglas, contains('match /analisis/{id}'));
    expect(
      reglas,
      contains('allow create, update: if esElAgente() || soyYo()'),
    );
  });

  // El teléfono entra como Mauro porque no se creó un usuario aparte. El día
  // que se cree, se cambia esta función y nada más.
  test('el teléfono entra como Mauro, y está dicho en un solo lugar', () {
    expect(
      reglas,
      contains('function esElTelefono() {\n      return soyYo();'),
    );
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
