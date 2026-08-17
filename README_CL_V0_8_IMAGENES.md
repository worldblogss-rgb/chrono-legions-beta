# Chrono Legions — CL_V0.8 con imágenes

Esta entrega usa las imágenes que ya copiaste localmente en:

`P:\APK\wco_game_V0_8\assets\images\v08\`

No incluye las imágenes dentro del ZIP.

## Nombres canónicos usados por el código

- `menu_v08.png`
- `chrono_logo.png`
- `battlefield_v08.png`
- `icons_resources_battle.png`
- `icons_ui.png`
- `scipio.png`
- `hannibal.png`
- `hannibal_gold.png`

El script `PREPARAR_ASSETS_V08.ps1` intenta crear esos nombres automáticamente si las imágenes todavía conservan nombres descriptivos.

## Cambios visibles

- Arte del menú V0.8 como fondo de portada.
- Logo real de Chrono Legions en lugar del icono provisional.
- Tablero oscuro real como fondo de partida.
- Retrato de Escipión en Roma.
- Retratos de Aníbal en Cartago.
- Retratos integrados en selección de facción, mazos y paneles de Comandante.
- Hoja de iconos de interfaz visible en la portada.
- Arte de recursos/batalla integrado al panel táctico.
- Se mantiene el layout táctico de CL_V0.8: Comandantes laterales, tablero central, crónica a la derecha y bandeja de mano.
- Se mantienen las reglas ya aprobadas.

## Instalación

1. Reemplaza `lib` por la carpeta `lib` de este paquete.
2. Copia `PREPARAR_ASSETS_V08.ps1` a la raíz del proyecto.
3. Desde PowerShell:

```powershell
cd "P:\APK\wco_game_V0_8"
.\PREPARAR_ASSETS_V08.ps1
flutter pub get
flutter analyze
```

4. Si el análisis no muestra errores:

```powershell
flutter run -d edge
```

## Importante

No reemplazamos tu `pubspec.yaml` completo porque contiene la configuración real de tu proyecto. El script agrega solamente:

```yaml
flutter:
  assets:
    - assets/images/v08/
```

sin tocar las dependencias existentes.
