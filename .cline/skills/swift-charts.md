# Swift Charts — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swift-charts`
**Use when:** AnalysisView (sparklines, score over time), ReportsView (bar charts, comparisons), LeaderboardsView.

---

## Common Chart Patterns

### Score Over Time (Sparkline)

```swift
Chart(runs) { run in
    LineMark(
        x: .value("Date", run.startedAt),
        y: .value("Score", run.score)
    )
    .foregroundStyle(Color.hxCyan)
    .interpolationMethod(.catmullRom)

    AreaMark(
        x: .value("Date", run.startedAt),
        y: .value("Score", run.score)
    )
    .foregroundStyle(
        LinearGradient(
            colors: [Color.hxCyan.opacity(0.3), .clear],
            startPoint: .top, endPoint: .bottom
        )
    )
}
.chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) }
.chartYAxis { AxisMarks(position: .leading) }
.frame(height: 120)
```

### Per-Task Session Count (Bar Chart)

```swift
Chart(taskCounts) { item in
    BarMark(
        x: .value("Task", item.taskName),
        y: .value("Sessions", item.count)
    )
    .foregroundStyle(item.accentColor)
    .cornerRadius(4)
}
.chartXAxis { AxisMarks { _ in AxisValueLabel(centered: true) } }
```

### Duration Histogram

```swift
Chart(runs) { run in
    BarMark(
        x: .value("Duration", run.durationBucket),  // e.g. "<1min", "1-3min"
        y: .value("Count", run.count)
    )
    .foregroundStyle(Color.hxAmber)
}
```

## Chart Styling for Dark Theme

```swift
.chartBackground { chartProxy in
    Color.hxSurface
}
.chartXAxis {
    AxisMarks {
        AxisGridLine().foregroundStyle(Color.hxSurfaceBorder)
        AxisValueLabel().foregroundStyle(Color.hxTextMuted)
    }
}
.chartYAxis {
    AxisMarks(position: .leading) {
        AxisGridLine().foregroundStyle(Color.hxSurfaceBorder)
        AxisValueLabel().foregroundStyle(Color.hxTextMuted)
    }
}
```

## Accessibility

Always add `.accessibilityLabel` to charts and provide tabular fallback:
```swift
Chart { ... }
    .accessibilityLabel("Score trend over time")
    .accessibilityValue("\(runs.count) sessions, best score \(bestScore)")
```

## Data Prep Patterns

```swift
// Group by task for bar chart
let taskCounts: [(taskName: String, count: Int)] = Dictionary(
    grouping: allRuns, by: { $0.taskID }
).map { (taskName: $0.key, count: $0.value.count) }
.sorted { $0.count > $1.count }

// Rolling 7-day average
let rollingAvg = runs.windows(ofCount: 7).map { window in
    Double(window.map(\.score).reduce(0, +)) / Double(window.count)
}
```

## AnalysisView Tab Structure

```swift
TabView(selection: $selectedTab) {
    overviewTab.tag(0)
    taskSpecificTab.tag(1)
    handXTab.tag(2)
    notesTab.tag(3)
}
.tabViewStyle(.page)
.indexViewStyle(.page(backgroundDisplayMode: .always))
```
