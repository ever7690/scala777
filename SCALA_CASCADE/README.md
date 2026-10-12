# SCALA CASCADE — vertical slice Android 3D
Proyecto nuevo de SCALA GAMES. No usa archivos GLB, WebView, HTML, ni recursos externos.
- Motor: Godot 4.3, GL Compatibility.
- Juego: carrera lateral, un personaje animado por articulaciones, terreno y bosques, cristales, rescates, obstáculos y grupo acompañante.
- Audio: música y efectos sintetizados por el motor.
- Android: ARMv7 y ARM64; exportación APK debug firmada.
- Estado: primera misión jugable en proceso de validación. No afirmar calidad comercial final.
- Entrada: un toque en pantalla / clic / barra espaciadora para saltar.

## Compilación con Godot 4.3
```bash
godot --headless --editor --path . --import
mkdir -p build
godot --headless --path . --export-debug Android build/SCALA_CASCADE_DEBUG.apk
```

El flujo automatizado en `.github/workflows/scala-cascade-android.yml` debe generar un artefacto APK. El artefacto solo se considera validado cuando la compilación y chequeo del ZIP tengan éxito.

## Alcance
Los modelos están montados en el motor mediante mallas 3D y pivotes animados en tiempo real; no son recursos pre-renderizados. **No incluye rig esquelético Skin/Skeleton3D con pesos**, ni texturas pintadas a mano. Se plantea como un primer corte nativo de jugabilidad, no una entrega visual premium.
