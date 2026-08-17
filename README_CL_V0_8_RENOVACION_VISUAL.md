# Chrono Legions — CL V0.8 Renovación Visual Completa

Esta entrega corresponde exclusivamente a la **V0.8**. La V0.9 y su ventana de novedades no están incluidas.

## Qué incluye

- Menú principal completamente recompuesto como interfaz Flutter.
- Duelo visual Escipión vs. Aníbal con accesos directos a ambos mazos.
- Selector de modo, dificultad y civilización integrado al nuevo menú.
- Fondo de menú y campo de batalla renovados.
- Emblema, retratos e iconografía general incluidos en el paquete.
- **55 ilustraciones individuales**, una por cada código de carta existente:
  - 26 cartas únicas de Roma.
  - 26 cartas únicas de Cartago.
  - 3 cartas neutrales.
- Ilustraciones visibles en la mano, en las líneas del tablero y en la vista ampliada.

Las reglas y los datos de las cartas se mantienen como estaban en el prototipo V0.8.

## Instalación recomendada

1. Descomprime este paquete.
2. En PowerShell ejecuta:

~~~powershell
.\INSTALAR_CL_V0_8_VISUAL.ps1 -ProjectRoot "P:\APK\wco_game_V0_8"
~~~

El instalador crea un respaldo de los archivos reemplazados, copia las carpetas **lib** y **assets**, y registra la ruta de recursos en pubspec.yaml si hace falta.

Después ejecuta desde el proyecto:

~~~powershell
flutter pub get
flutter analyze
flutter run -d edge
~~~

## Instalación manual

También puedes copiar las carpetas **lib** y **assets** sobre el proyecto existente. Comprueba que pubspec.yaml contenga:

~~~yaml
flutter:
  assets:
    - assets/images/v08/
~~~

## Control de entrega

El archivo MANIFIESTO_IMAGENES_V08.csv relaciona cada código de carta con su imagen. El paquete fue comprobado con 55 códigos y 55 imágenes, sin faltantes ni sobrantes.
