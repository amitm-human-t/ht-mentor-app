# SwiftUI Navigation — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swiftui-navigation`
**Use when:** Adding routes, screen transitions, deep links, back navigation.

---

## AppRoute Enum (App/AppModel.swift)

```swift
enum AppRoute: Hashable {
    case taskPicker
    case taskRunner(TaskDefinition)
    case userChooser
    case results(RunSummaryDraft)
    case analysis(PersistentIdentifier)
    case leaderboards
    case reports
    case curriculum
    case curriculumRun(CurriculumRecord)
    case userManagement
    case customTaskConfig
    case bleConsole
    case diagnostics
    case permissionCenter
}
```

## NavigationStack Setup (ContentView.swift)

```swift
NavigationStack(path: $appModel.navigationPath) {
    HubView()
        .navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .taskPicker:       TaskPickerView(appModel: appModel)
            case .taskRunner(let t): TaskRunnerView(appModel: appModel, taskDefinition: t)
            case .userChooser:      UserChooserView(appModel: appModel)
            // ... all routes
            }
        }
}
```

## Programmatic Navigation (AppModel methods)

```swift
// Always navigate via AppModel — never from a child view
appModel.navigate(to: .taskPicker)
appModel.navigateBack()
appModel.popToRoot()
```

## Zoom Transition (TaskPicker → TaskRunner)

```swift
// TaskPickerView — attach namespace to cards
@Namespace private var zoomNS

TaskCard(task: task)
    .matchedTransitionSource(id: task.id, in: zoomNS)
    .onTapGesture { appModel.navigate(to: .taskRunner(task)) }

// TaskRunnerView — receive namespace (passed down or via env)
TaskRunnerView(...)
    .navigationTransition(.zoom(sourceID: task.id, in: zoomNS))
```

## Sheet Presentation

```swift
// App-level sheet state on AppModel
@Observable final class AppModel {
    var activeSheet: SheetRoute? = nil
}

// In view
.sheet(item: $appModel.activeSheet) { sheet in
    switch sheet {
    case .userForm(let user): UserFormView(user: user)
    }
}
```

## Rules

- Every key screen must be reachable via `AppRoute` (supports deep links)
- Never push to `navigationPath` from within a view — always call `AppModel.navigate(to:)`
- Each modal/sheet dismisses itself: `@Environment(\.dismiss) var dismiss`
- `TaskRunnerView` suppresses the system nav bar: `.toolbar(.hidden, for: .navigationBar)`
