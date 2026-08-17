# Chrono Legions V0.7.1 — Endgame

Esta actualización conserva la base Android horizontal de V0.7 y corrige el bloqueo del final de partida.

## Nueva protección del Comandante

- La línea de Batalla protege al Comandante.
- Un aliado normal en Apoyo puede defender un ataque, pero no protege al Comandante.
- Solo una Fortificación muestra el icono de muralla y protege al Comandante desde Apoyo.
- Roma y Cartago mantienen 3 cartas con muralla por mazo.

## Brecha y ataque directo

- Si una ofensiva elimina la última protección, causa 1 daño de Brecha.
- Si el Comandante comienza Expuesto, se puede declarar un ataque directo.
- El daño al Comandante queda limitado a 1 por ofensiva.
- El bot reconoce cuándo un Comandante está Expuesto.

## Cierre de partida

- La partida termina inmediatamente al causar 10 daños al Comandante.
- También termina después de la ronda 15.
- En el límite gana quien conserve más resistencia.
- Si la resistencia empata, gana quien haya eliminado más cartas enemigas.
- Si ambos valores empatan, el resultado es empate.

## Prueba

```powershell
cd D:\Proyectos\wco_game_V0_7_1
flutter clean
flutter pub get
flutter test
flutter run -d HA1Z4REF
```
