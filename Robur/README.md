# Robur

App personal de gimnasio para iPhone: rutinas y registro de series, dieta con menús, sincronización con Apple Salud, progreso con peso y fotos, y cámara IA para estimar comidas.

SwiftUI + SwiftData, iOS 17+. Sin dependencias externas.

## Instalar en el iPhone sin Mac (Windows + GitHub Actions + AltStore)

1. Crea un repo en GitHub (privado vale) y sube esta carpeta entera (con `.github/`). Rama `main`.
2. Pestaña **Actions** → el workflow "Build IPA (sin firmar)" arranca solo con cada push (o con "Run workflow"). Tarda 5-8 min.
3. Cuando acabe, en la página del run, sección **Artifacts** → descarga `Robur-ipa` (un zip con `Robur.ipa` dentro).
4. En Windows abre **AltServer**, conecta el iPhone por USB (o Wi-Fi con AltStore ya instalado), y en AltStore (iPhone) → **My Apps → +** → elige `Robur.ipa`. AltStore lo firma con tu Apple ID y lo instala.
5. La app caduca a los 7 días; AltStore la refresca sola si AltServer está abierto en el PC en la misma red. Con cuenta gratuita: máximo 3 apps sideloaded a la vez.

Si el build falla, copia el log del paso "Archive" y pásamelo: normalmente son 2-3 errores de compilación de primera pasada.

### Con Mac (alternativa)

Abre `Robur.xcodeproj` con Xcode 16+, pon tu Team en Signing & Capabilities y ▶︎ al iPhone.

Si prefieres regenerar el proyecto con [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate` en esta carpeta (usa `project.yml`).

## Primer arranque

- Onboarding: nombre, altura, fecha de nacimiento, sexo, actividad, objetivo y peso actual → se calculan BMR (Mifflin-St Jeor), TDEE y macros.
- Ajustes → **Sincronizar con Salud** → acepta los permisos.
- Ajustes → **Cámara IA** → pega tu API key de Anthropic (se guarda en el Llavero). El modelo por defecto es `claude-sonnet-4-5`; cámbialo si quieres otro.

## Estructura

```
Robur/
├── RoburApp.swift            App, ModelContainer, tabs
├── Models/Models.swift       SwiftData: Exercise, Routine, WorkoutSession, WorkoutSet, Food, MealEntry, PlannedMeal, BodyMeasurement, UserProfile
├── Services/
│   ├── CalorieCalculator     BMR/TDEE/macros y kcal de sesión por METs
│   ├── HealthKitService      pasos, minutos, energía activa, guardar entrenos y peso
│   ├── OpenFoodFactsService  búsqueda por texto y por código de barras
│   ├── ClaudeVisionService   foto → JSON de alimentos y macros
│   ├── SeedService           carga exercises.json / foods.json la primera vez
│   └── Support               Keychain, PhotoStore, recordatorios, traducciones, helpers
├── Views/
│   ├── Today/                Dashboard diario
│   ├── Workout/              Rutinas, biblioteca, entreno activo, historial
│   ├── Diet/                 Diario, búsqueda, escáner, cámara IA, plan semanal
│   ├── Progress/             Peso + gráfico, fotos, comparador
│   └── Settings/             Onboarding y ajustes
└── Resources/
    ├── exercises.json        876 ejercicios (free-exercise-db, dominio público), 225 con nombre en español
    ├── foods.json            181 alimentos básicos españoles (valores por 100 g)
    └── mets.json             tabla MET de actividades
```

## Cómo se calculan las cosas

- **kcal de una sesión de fuerza**: MET del ejercicio × peso corporal × horas. La duración total de la sesión se reparte entre las series completadas (mínimo 45 s por serie). Es una estimación, como en cualquier app.
- **Cardio**: si registras minutos en un ejercicio de tipo cardio, se usa ese tiempo con su MET.
- **Objetivo calórico**: TDEE + (−400 definir / 0 mantener / +300 volumen). Proteína g/kg configurable, grasa 27 % de kcal, resto hidratos.
- **Cámara IA**: la foto se reduce a 1024 px y se envía a `/v1/messages` con un prompt que exige JSON. Puedes editar gramos y macros antes de guardar. Precisión orientativa (±25 %).

## Datos

- Ejercicios: [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (Unlicense). Las imágenes se cargan bajo demanda desde GitHub.
- Productos envasados: [Open Food Facts](https://world.openfoodfacts.org) (ODbL). Límite 10 búsquedas/min, de sobra.
- Los alimentos básicos de `foods.json` son valores medios habituales de tablas de composición; edítalos o crea los tuyos desde la app.

## Añadir traducciones de ejercicios

Edita el diccionario `ES` en `build_seed.py` (en la raíz del repo) y ejecuta `python3 build_seed.py`; copia el `exercises.json` resultante a `Robur/Resources/`. Sube `currentSeedVersion` en `SeedService` si quieres que la app vuelva a cargarlos (ojo: solo se insertan si la tabla está vacía; para recargar, borra la app o cambia la lógica).
