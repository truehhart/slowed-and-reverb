# Player redesign reference

Visual reference: [player-redesign-reference.png](./player-redesign-reference.png)

This is a direction reference for the native SwiftUI redesign. The existing SwiftUI views and `PlayerModel` remain the source of truth for behavior. The generated image is useful for hierarchy, density, materials, and control language, but its text and values are not a pixel-level specification.

## Design direction

- Keep the warm tape-console identity, but reduce decorative skeuomorphism.
- Use a clearer hierarchy: app chrome, player workspace, persistent transport dock.
- Prefer native SwiftUI surfaces, continuous corners, semantic focus rings, and SF Symbols-style controls.
- Keep the charcoal, walnut, ivory, coral, and amber palette.
- Make active, disabled, loading, paused, and error states obvious without relying on color alone.
- Keep the first redesign within the existing fixed-window footprint so behavior and layout can change independently.

## Feature contract

The Player screen must continue to expose:

| Area | Required behavior |
| --- | --- |
| Navigation | Player, Library, Settings, GitHub/development link, version tag |
| Input | Add a video or playlist URL, replace the queue with Import, submit with Return, paste-to-add |
| Queue | Scrollable tracks, numbered rows, active track, select-to-play, clear queue, background preload |
| Effects | Speed 50–100%, reverb mix 0–100%, room/hall/plate, low cut 80/120/180/260 Hz |
| Transport | Play/pause, previous, next, restart/previous-track behavior, ±5 second seek, repeat off/queue/one |
| Timeline | Elapsed time, remaining time, draggable seek position, perceived tape counter |
| Output | Mute, master volume, L/R VU meters, animated reels |
| Async state | Resolving, downloading with progress, decoding, playing, paused, failed, user-visible errors |
| Settings | Cache size, segmented storage gauge, two-step cache purge |
| Keyboard | Space/K play-pause, J/L and arrows seek, arrows adjust volume, Command-V adds a URL |

## SwiftUI migration plan

1. Extract the visual tokens in `Theme` into surfaces, borders, typography, and interaction states. Keep the existing values initially so this is a safe no-behavior-change pass.
2. Rebuild `ConsoleView` and `PlateView` as the window shell. Keep the plain window and drag behavior, but make the tab rail and transport dock feel like one native composition.
3. Recompose `TapeTransportModule`, `EffectRackModule`, and `QueueModule` around shared surface and control primitives. Preserve their current bindings to `PlayerModel` and `QueueBoxModel`.
4. Refine `TransportDeck` as the primary focus area. Keep the existing actions and keyboard shortcuts, then improve disabled/loading/error affordances.
5. Update Settings and the Library placeholder using the same surface system. Do not add library behavior until the model supports it.
6. Verify each slice with `mise run check` and `mise run test`. Treat this as a visual migration, not a reason to move audio, network, or cache logic into views.

## Implementation guardrails

- `PlayerModel` remains the owner of playback, queue, cache, download, and Now Playing behavior.
- `QueueBoxModel` remains the owner of add/replace submission state.
- Views should compose existing actions rather than duplicate playback rules.
- Keep one non-private top-level type per file and the current Swift-format/file-structure checks.
- Use the generated image as a visual target, while using the feature contract above to catch anything the image cannot show, such as keyboard shortcuts and transient download failures.
