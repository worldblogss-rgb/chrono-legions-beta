# Chrono Legions — CL_V0.8 FINAL

Base utilizada: `main.dart` real de CL_V0.72b.

## Cambio de interfaz

Esta versión no es una simple recolorización.

### Menú
- Nueva portada en dos paneles.
- Identidad CL_V0.8 visible al iniciar.
- Panel de preparación de batalla separado.
- Roma y Cartago presentados como facciones.
- Mazos de prueba en bandeja propia.
- Campaña Antigüedad destacada.
- Diseño adaptable al ancho de Edge.

### Partida
- Se elimina la estructura visual tipo lista vertical en pantallas anchas.
- Cabecera táctica propia en lugar del AppBar tradicional.
- Comandantes quedan en una columna lateral izquierda.
- Campo de batalla ocupa el centro.
- Panel táctico y crónica de batalla quedan a la derecha.
- Mano se presenta como bandeja inferior.
- Zona central separa visualmente ambos frentes.
- Objetivos válidos durante ataque se resaltan.
- Órdenes mantienen su resaltado diferenciado.
- Comandante se destaca cuando queda disponible como objetivo directo.
- Fondo de batalla se genera por código y no requiere imágenes.
- En ventanas más estrechas la interfaz vuelve a una disposición compacta.

## Reglas que NO cambian
- Victoria por Comandante.
- 10 de resistencia.
- Recursos actuales.
- Iniciativa con tres dados.
- Preparación.
- Daño persistente.
- Contraataque.
- Batalla y Apoyo.
- Fortificaciones y Murallas.
- Brecha.
- Máximo una Orden por turno antes de la ofensiva.
- Bot Fácil / Normal actual.
- Mazo de prueba actual.
- Límite de 15 rondas y desempate actual.

## No implementado todavía
- Clases T-I/T-II/N-I/N-II.
- Leyendas.
- Reacciones.
- Habilidades particulares de unidades.
- Habilidades particulares de Fortificaciones.
- Constructor de mazos.
- Pool completo de cartas.
- Aire.

## Archivos
```text
lib/
  main.dart
  theme/
    chrono_theme.dart
  widgets/
    battlefield_backdrop.dart
```

No modifica `pubspec.yaml` y no necesita assets.

## Instalación
Conserva tus versiones anteriores.

```powershell
Copy-Item "P:\APK\wco_game_V0_73" "P:\APK\wco_game_V0_8" -Recurse
cd "P:\APK\wco_game_V0_8"
```

Reemplaza completamente la carpeta `lib` de `wco_game_V0_8` por la carpeta `lib` incluida aquí.

Después:

```powershell
flutter analyze
```

Si no aparecen errores:

```powershell
flutter run -d edge
```

## Importante
No uses el paquete V0.8 anterior. Este paquete `CL_V0_8_FINAL` lo sustituye.


## Corrección de entrega
Si instalaste previamente la primera V0.8, elimina estos dos archivos antiguos antes de analizar:

```powershell
Remove-Item ".\lib\widgets\battle_log_panel.dart" -Force -ErrorAction SilentlyContinue
Remove-Item ".\lib\widgets\turn_phase_banner.dart" -Force -ErrorAction SilentlyContinue
```

La versión corregida usa solamente:

```text
lib/
  main.dart
  theme/
    chrono_theme.dart
  widgets/
    battlefield_backdrop.dart
```
