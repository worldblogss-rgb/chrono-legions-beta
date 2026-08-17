import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wco_game/main.dart';

void main() {
  testWidgets('Muestra el menú horizontal de Chrono Legions', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const WcoApp());

    expect(find.text('CHRONO LEGIONS'), findsOneWidget);
    expect(find.text('LA HISTORIA ENTRA EN BATALLA'), findsOneWidget);
    expect(find.text('JUGADOR LOCAL'), findsOneWidget);
    expect(find.text('MIS DOS MAZOS FAVORITOS'), findsOneWidget);
    expect(find.text('EDADES'), findsOneWidget);
    expect(find.text('ANTIGÜEDAD'), findsOneWidget);
    expect(find.text('Escipión el Africano'), findsWidgets);
    expect(find.text('Aníbal Barca'), findsWidgets);
    expect(find.text('Contra bot'), findsOneWidget);
    expect(find.text('Fácil'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Prueba libre'), findsOneWidget);
    expect(find.text('NUEVA PARTIDA'), findsOneWidget);
    expect(
      find.text(
        'CL_V0.72b · Edge beta · Mazos de 30 cartas con Órdenes',
      ),
      findsOneWidget,
    );
  });

  test('Los dos mazos tienen composición 20/5/5', () {
    for (final faction in Faction.values) {
      final composition = debugDeckComposition(faction);
      expect(composition['Unidad'], 20);
      expect(composition['Fortificación'], 5);
      expect(composition['Orden'], 5);
      expect(composition.values.reduce((a, b) => a + b), 30);
      expect(debugWallCount(faction), 2);
    }
  });

  test('La Orden de dados limita el bono de Fuerza entre 1 y 3', () {
    expect(diceOrderBonus(1), 1);
    expect(diceOrderBonus(2), 1);
    expect(diceOrderBonus(3), 2);
    expect(diceOrderBonus(4), 2);
    expect(diceOrderBonus(5), 3);
    expect(diceOrderBonus(6), 3);
    expect(() => diceOrderBonus(0), throwsRangeError);
    expect(() => diceOrderBonus(7), throwsRangeError);
  });
}
