# AI Skills — HandX Training Hub

Project-specific reference sheets for each AI skill domain used in this repo.
All agents (Claude Code, Cline, Codex) should consult the relevant skill file
before writing code in that domain.

Plugin source: `~/.claude/plugins/cache/swift-ios-skills/ios-ai-ml-skills/3.1.0/`

---

## Quick Dispatch Table

| You are working on… | Read this file |
|---------------------|---------------|
| View state, @Observable, environment injection | [swiftui-patterns.md](swiftui-patterns.md) |
| Liquid Glass cards, `.glassEffect`, GlassEffectContainer | [swiftui-liquid-glass.md](swiftui-liquid-glass.md) |
| Spring animations, PhaseAnimator, zoom transitions, numericText | [swiftui-animation.md](swiftui-animation.md) |
| LazyVGrid, custom layouts, split-panel views, FlowLayout | [swiftui-layout-components.md](swiftui-layout-components.md) |
| NavigationStack, AppRoute enum, deep links, zoom nav | [swiftui-navigation.md](swiftui-navigation.md) |
| SwiftData @Model, @Query, FetchDescriptor, migration | [swiftdata.md](swiftdata.md) |
| Swift Charts (sparklines, bar, area, analysis) | [swift-charts.md](swift-charts.md) |
| CoreBluetooth, HandX BLE, disconnect policy | [core-bluetooth.md](core-bluetooth.md) |
| CoreML inference, VNCoreMLRequest, model registry | [coreml.md](coreml.md) |
| Actors, AsyncStream, TaskGroup, Swift 6 concurrency | [swift-concurrency.md](swift-concurrency.md) |
| AVFoundation, camera session, audio players | [avkit.md](avkit.md) |
| Render isolation, Instruments, drawingGroup, Thermal | [swiftui-performance.md](swiftui-performance.md) |
| Swift Testing framework, unit/integration tests | [swift-testing.md](swift-testing.md) |
| UI/UX decisions, color palette, typography, layout rules | [ui-ux-pro-max.md](ui-ux-pro-max.md) |

---

## Xcode Relevance

These skill files are for AI code-generation agents. Xcode has no equivalent
plugin system, but the same patterns apply when:
- Writing build phases or run scripts → see `swift-concurrency.md` + `avkit.md`
- Adding CoreML model targets → see `coreml.md`
- Configuring signing/entitlements for BLE → see `core-bluetooth.md`
- Running Instruments profiling → see `swiftui-performance.md`

The full master context is always in `CLAUDE.md` (project root).
Session state lives in `SESSION_AUDIT.md` (project root).
