# Ejecutar desde P:\APK\wco_game_V0_8
Remove-Item ".\lib\widgets\battle_log_panel.dart" -Force -ErrorAction SilentlyContinue
Remove-Item ".\lib\widgets\turn_phase_banner.dart" -Force -ErrorAction SilentlyContinue
Write-Host "Restos de la V0.8 anterior eliminados."
Write-Host "Ahora reemplaza lib con la carpeta lib de CL_V0_8_CORREGIDA y ejecuta: flutter analyze"
