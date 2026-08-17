# Chrono Legions V0.7 — Android

Esta versión conserva la jugabilidad V0.6.2 y prepara la primera prueba completa en un teléfono Android.

## Cambios principales

- orientación horizontal obligatoria en Android;
- nuevo menú adaptable para teléfono y tableta;
- nombre de jugador local editable durante la sesión;
- acceso directo a los dos mazos favoritos: Roma y Cartago;
- filas horizontales de edades, comandantes y mazos;
- Edad Antigua activa; Edad Media y Edad Moderna visibles como futuras;
- inicio directo con Escipión o Aníbal;
- confirmación antes de abandonar una partida;
- `compileSdk` y `targetSdk` configurados en Android API 36;
- versión de aplicación `0.7.0+7`.

## Cómo probar en el teléfono

Desde PowerShell, dentro de `D:\Proyectos\wco_game`:

```powershell
flutter clean
flutter pub get
flutter test
flutter devices
flutter run
```

Conecta el teléfono por USB, activa **Opciones de desarrollador** y **Depuración USB**, y acepta la autorización que aparezca en el teléfono. Si hay más de un dispositivo, ejecuta:

```powershell
flutter run -d ID_DEL_TELEFONO
```

Si Flutter informa que falta Android API 36, abre Android Studio, entra a **SDK Manager** e instala **Android 16 (API 36)**.

## Importante antes de Google Play

El identificador continúa temporalmente como `com.example.wco_game`. Debe cambiarse una sola vez cuando se confirme el nombre/editor final, antes de publicar la primera ficha en Google Play. El icono definitivo, firma de lanzamiento y políticas quedan para la etapa de publicación.
