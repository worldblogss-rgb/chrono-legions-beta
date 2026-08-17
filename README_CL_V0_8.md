# Chrono Legions — CL_V0.8

## Objetivo de esta versión
CL_V0.8 toma la base funcional de CL_V0.73 y realiza el cambio grande de interfaz para seguir puliendo el juego en Edge.

### Cambios visuales
- Nueva paleta más oscura, histórica y contrastada.
- Campo de batalla con textura visual ligera, sin imágenes externas.
- Barra de turno con secuencia visual de fases.
- Panel táctico lateral automático en ventanas anchas.
- Últimos eventos visibles durante la partida sin abrir diálogos.
- Comandantes con lectura visual más clara.
- Objetivo directo al Comandante resaltado.
- Líneas de Batalla y Apoyo visualmente diferenciadas.
- Cartas de campo más grandes y legibles.
- Mano más grande y con cartas visualmente más claras.
- Estados de selección, preparación, objetivo y daño con mayor contraste.
- Diseño responsive: en ventanas más estrechas el panel lateral desaparece y el tablero conserva el ancho.

### Reglas que se mantienen
- Victoria por daño al Comandante.
- Comandante con 10 de resistencia.
- Máximo 15 rondas y desempate actual.
- Recursos sin cambios.
- Iniciativa con 3 dados.
- Preparación.
- Daño persistente.
- Contraataque.
- Batalla / Apoyo.
- Fortificaciones y Murallas.
- Brecha.
- Máximo 1 Orden por turno antes de la ofensiva.
- Bot fácil/normal actual.
- Mazos de prueba actuales de 30 cartas.

### Fuera de CL_V0.8 por ahora
- Clases T-I / T-II / N-I / N-II.
- Leyendas.
- Reacciones.
- Habilidades particulares de unidades y Fortificaciones.
- Constructor de mazos.
- Pool completo cercano a 200 cartas.
- Dominio Aire.

## Instalación
Conserva CL_V0.73 como respaldo.

```powershell
Copy-Item "P:\APK\wco_game_V0_73" "P:\APK\wco_game_V0_8" -Recurse
cd "P:\APK\wco_game_V0_8"
```

Reemplaza la carpeta `lib` por la incluida en este paquete.

Luego:

```powershell
flutter analyze
```

Si no hay errores:

```powershell
flutter run -d edge
```

## Qué probar
1. Menú inicial.
2. Iniciativa.
3. Turno de Roma y Cartago.
4. Panel táctico lateral en Edge con ventana ancha.
5. Despliegue.
6. Orden.
7. Selección de atacante y objetivos.
8. Comandante expuesto.
9. Resolución de ofensiva.
10. Daño persistente.
11. Murallas/Brecha.
12. Bot.
13. Historial.
14. Cambio de tamaño de ventana.

No es necesario modificar `pubspec.yaml`.
