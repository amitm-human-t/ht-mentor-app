# SwiftUI Patterns — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swiftui-patterns`
**Use when:** @Observable migration, view composition, state ownership, environment injection, async loading.

---

## Project-Specific Patterns

### @Observable Classes in This Repo

```swift
@Observable
@MainActor
final class AppModel { ... }          // App/AppModel.swift

@Observable
@MainActor
final class RunnerCoordinator { ... } // Core/Session/RunnerCoordinator.swift
```

Both are injected via `.environment()`:
```swift
// p2_appApp.swift
ContentView()
    .environment(appModel)

// In child views — read-only
struct HubView: View {
    @Environment(AppModel.self) var appModel
}

// In child views — two-way binding
struct EditView: View {
    @Bindable var coordinator: RunnerCoordinator
}
```

### State Ownership Rules

| Situation | Use |
|-----------|-----|
| View owns state locally | `@State private var` |
| View receives @Observable, read-only | `let model: SomeModel` |
| View receives @Observable, needs `$binding` | `@Bindable var model: SomeModel` |
| Shared app-wide service | `@Environment(Type.self)` |
| SwiftData live list | `@Query` in view |

### MV Pattern (not MVVM)

No view models. Logic lives in `@Observable` model objects or services.
Views are thin: bind data, call methods, show state.

```swift
// CORRECT — view calls model method
Button("Start") {
    Task { await coordinator.start() }
}

// WRONG — logic in view body
Button("Start") {
    guard bleConnected && !isLoading else { return }
    coordinator.state = .running  // don't mutate internals from view
    ...
}
```

### View Composition

Break views at 150–200 lines. Extract as `private var` computed properties first,
then as private structs when they need `@State` or want to be reused.

```swift
// Computed property (same file, no state)
private var scoreDisplay: some View { ... }

// Private struct (needs its own @State or reused elsewhere)
private struct TaskCard: View { ... }

// Public struct (reused across feature modules)
struct AvatarView: View { ... }   // UserChooserView.swift → reused in HubView
```

### Async Loading

Always `.task` — it auto-cancels on view disappear:

```swift
.task {
    await viewModel.loadSomething()
}

// Re-trigger when dependency changes
.task(id: selectedUserID) {
    await loadUserProfile(selectedUserID)
}
```

### Common Mistakes to Avoid

- Don't use `ObservableObject` / `@Published` — project is fully `@Observable`
- Don't put navigation logic in views — use `AppModel.navigate(to:)`
- Don't use `AnyView` — use `@ViewBuilder` or `Group`
- Don't run async work in `onAppear` — use `.task`
