# PAI Mobile

Private mobile interface for the Personal AI Infrastructure (PAI). This is not a public product — it is the mobile remote for my Digital Assistant, operating over a private Tailscale network.

## Monorepo Structure

```text
mobile-app/
  apps/
    mobile/                 # Expo Router app (React Native)
  packages/
    shared-types/           # TypeScript contracts
    shared-schemas/         # Validation schemas
    opencode-mobile-client/ # OpenCode Server API client
    opencode-mobile-plugin/ # Notification plugin (server-side)
    ui-system/              # Material 3 design system
    audio-elevenlabs/       # STT/TTS abstraction
    test-utils/             # Shared test fixtures
```

## Requirements

- [Bun](https://bun.sh/) >= 1.1.0
- Node.js (for Expo CLI compatibility)
- iOS: Xcode + Simulator
- Android: Android Studio + Emulator

## Quick Start

```bash
# Install dependencies
bun install

# Start the mobile app
bun run dev

# Typecheck all packages
bun run typecheck

# Run tests
bun run test
```

## Package Manager

This repository uses **Bun workspaces**. Do not use npm or pnpm. The root `package.json` declares:

```json
"packageManager": "bun@1.1.0",
"workspaces": ["apps/*", "packages/*"]
```

## Why Bun?

The original technical plan mentioned pnpm, but Bun was chosen because:

1. It is the standard across all PAI projects
2. Bun workspaces satisfy the same monorepo need with lower overhead
3. Lockfile (`bun.lockb`) is simpler and faster
4. The ecosystem gap for React Native has closed in recent Bun versions

## Tech Stack

- **Framework**: Expo (React Native)
- **Router**: Expo Router
- **Language**: TypeScript (strict mode)
- **State**: Zustand
- **UI Base**: Material 3
- **Storage**: expo-secure-store + expo-sqlite
- **Audio**: ElevenLabs (STT + TTS)
- **Push**: Expo Notifications

## Development Workflow

See [`docs/KIMI_WORKFLOW.md`](docs/KIMI_WORKFLOW.md) for the Kimi-driven coding protocol used in this repository.

For the real-device Android workflow that proved stable in this repo, see [`docs/SAMSUNG_WSL_EXPO_WORKFLOW.md`](docs/SAMSUNG_WSL_EXPO_WORKFLOW.md).

## Milestones

| Milestone | Description | Status |
|-----------|-------------|--------|
| M0 | Workspace & Bootstrap | Done |
| M1 | Contracts & Internal Architecture | Done |
| M2 | Navigation, App State & Settings | Done |
| M3 | OpenCode Client & Sessions | Done |
| M4 | SSE Foreground & Rehydration | Partial |
| M5 | Timeline, Rendering & Permissions | In Progress |
| M6 | Audio: STT/TTS with ElevenLabs | Planned |
| M7 | OpenCode Notification Plugin | Planned |
| M8 | Deep Linking & Notification UX | Planned |
| M9 | Resilience, Security & Observability | Planned |
| M10 | QA, Build & Private Release | Planned |

## License

Private — not for distribution.
