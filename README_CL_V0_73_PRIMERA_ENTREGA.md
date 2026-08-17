# Chrono Legions — CL_V0.73 · Primera entrega

Esta entrega parte directamente del `main.dart` real de CL_V0.72b.

## Qué cambia
- Nueva paleta visual centralizada.
- Fondo de campo de batalla con textura ligera, sin assets externos.
- Indicador superior de civilización activa, fase y ronda.
- Cartas del campo más altas y legibles.
- Transiciones visuales cortas al cambiar estados.
- Objetivos válidos de ataque resaltados en verde.
- Objetivos válidos de Órdenes mantienen un resaltado propio.
- Comandante resaltado cuando es un objetivo directo válido.
- Cartas de la mano más anchas y con borde visual consistente.
- Identificación interna actualizada a CL_V0.73.

## Qué NO cambia
- Condición de victoria.
- Recursos.
- Iniciativa.
- Órdenes y su límite de uso.
- Daño persistente.
- Fortificaciones/Murallas.
- Contraataques.
- Bot.
- Tamaño de los mazos actuales.
- Límite de rondas.

## Instalación recomendada

Mantén CL_V0.72b intacta y crea una copia:

```powershell
Copy-Item "P:\APK\wco_game_V0_72b" "P:\APK\wco_game_V0_73" -Recurse
cd "P:\APK\wco_game_V0_73"
```

Dentro de esa copia reemplaza la carpeta `lib` por la carpeta `lib` de este paquete.

Luego:

```powershell
flutter analyze
```

Si no aparecen errores:

```powershell
flutter run -d edge
```

## Archivos de esta entrega

```text
lib/
  main.dart
  theme/
    chrono_theme.dart
  widgets/
    battlefield_backdrop.dart
    turn_phase_banner.dart
```

## Qué revisar en Edge

1. Menú inicial.
2. Tirada de iniciativa.
3. Despliegue en Batalla y Apoyo.
4. Selección de atacante.
5. Resaltado de objetivos válidos.
6. Ataque directo al Comandante cuando queda expuesto.
7. Activación de una Orden.
8. Daño persistente y destrucción.
9. Turno del bot.
10. Historial y reglamento.

Esta es una primera entrega visual de CL_V0.73. No requiere modificar `pubspec.yaml`.
