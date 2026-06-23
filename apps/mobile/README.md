# Benthyo Mobile

Flutter app for Benthyo — dive logging, species tracking, and site discovery.
Targets **iOS, Android, and the Web** from a single codebase.

## Setup

1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.32+).
2. Set dart-defines when running or building:
   - `SUPABASE_URL` (default: `http://127.0.0.1:54321` from `supabase start`)
   - `SUPABASE_PUBLISHABLE_KEY` (alias: `SUPABASE_ANON_KEY` still works)
   - `API_URL` (default: `http://localhost:3000/api/v1`)

   ```bash
   flutter run \
     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
     --dart-define=SUPABASE_PUBLISHABLE_KEY=eyJh...
   ```

3. Run `flutter pub get` then pick your target:

   ```bash
   flutter run -d chrome        # web (no offline queue — uses in-memory)
   flutter run -d ios           # iPhone simulator
   flutter run -d android       # Android emulator
   flutter run -d <device-id>  # any physical device
   flutter build web            # production web bundle in build/web
   ```

## Architecture

Feature-first layout with Riverpod state management and GoRouter navigation.

### Platform notes

- **iOS / Android / desktop** — full offline support. The sync queue is
  backed by `sqflite` and the `autoSyncCoordinatorProvider` drains it
  when connectivity is restored.
- **Web** — the sync queue is **in-memory only** (`sqflite` is not
  available in the browser). This is fine because a web tab is always
  online; the repositories' `isOnline` path posts directly to the API
  and never enqueues. The auto-sync coordinator no-ops on web to keep
  the bundle small and avoid wasted work.
- **Photo uploads** use the R2 presigned-PUT flow from `docs/api.md`.
  On web the user can pick a file via the file-input picker; on mobile
  `image_picker` provides the camera + gallery.

## Testing & quality

```bash
flutter analyze           # strict lints — must pass
flutter test              # unit tests
flutter build web         # production web bundle
```
