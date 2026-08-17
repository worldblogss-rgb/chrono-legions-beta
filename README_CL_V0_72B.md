# Chrono Legions CL_V0.72b — Órdenes y dados

Versión experimental para pruebas locales en Edge. Mantiene separada la versión estable CL_V0.7.1.

## Contenido principal

- Mazo de 30 cartas por civilización: 20 unidades, 5 Fortificaciones y 5 Órdenes.
- Solo 2 Fortificaciones por mazo tienen Muralla y protegen al Comandante.
- Máximo 1 Orden por turno, siempre antes de declarar la ofensiva.
- Flujo de Órdenes: ACTIVAR, elegir objetivo válido, pagar recursos y enviar al descarte.
- Cinco efectos simples: +2 Fuerza, restaurar 2 de daño, causar 1 de daño, robar 1 carta y bono de Fuerza mediante dado.
- El bot puede utilizar Órdenes con selección básica de objetivos.
- Iniciativa aleatoria: cada civilización lanza 3 dados; el total mayor comienza y los empates se relanzan.
- Historial de iniciativa, Órdenes y combates.

## Prueba recomendada

```powershell
cd D:\Proyectos\wco_game_V0_72b
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d edge
```

Esta versión no debe publicarse todavía en GitHub Pages. Su finalidad es probar mecánicas y balance en Edge.
