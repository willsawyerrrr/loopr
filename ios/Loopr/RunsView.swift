import EventKit
import RouteKit
import SwiftData
import SwiftUI

struct RunsView: View {
    private enum Phase {
        case loading
        case needsPermission
        case denied
        case noCalendar
        case loaded([PlannedRun])
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Query private var routes: [SavedRoute]
    @State private var state = Phase.loading
    @State private var showSettings = false
    @State private var showScreenshot = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Runs")
                .toolbar {
                    Button("From screenshot", systemImage: "camera.viewfinder") { showScreenshot = true }
                    Button("Settings", systemImage: "gear") { showSettings = true }
                }
                .navigationDestination(for: PlannedRun.self) { RunDetailView(run: $0) }
        }
        .sheet(isPresented: $showSettings, onDismiss: refresh) { SettingsView() }
        .sheet(isPresented: $showScreenshot) { ScreenshotRouteView() }
        .task { refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active { refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
        case .needsPermission:
            ContentUnavailableView {
                Label("Calendar access", systemImage: "calendar")
            } description: {
                Text("Loopr reads your subscribed Runna calendar to find your upcoming runs.")
            } actions: {
                Button("Allow calendar access") {
                    Task {
                        _ = await RunCalendar.requestAccess()
                        refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .denied:
            ContentUnavailableView {
                Label("Calendar access is off", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Allow full calendar access for Loopr in Settings to see your upcoming runs.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        case .noCalendar:
            ContentUnavailableView {
                Label("No Runna calendar", systemImage: "calendar.badge.questionmark")
            } description: {
                Text("Subscribe to your Runna calendar, or choose which calendar holds your runs.")
            } actions: {
                Button("Choose calendar") { showSettings = true }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let runs) where runs.isEmpty:
            ContentUnavailableView(
                "No runs planned", systemImage: "figure.run",
                description: Text("Nothing on the calendar in the next \(RunPlan.windowDays) days."))
        case .loaded(let runs):
            List(runs) { run in
                NavigationLink(value: run) { RunRow(run: run, route: route(for: run)) }
            }
            .refreshable { refresh() }
        }
    }

    private func route(for run: PlannedRun) -> SavedRoute? {
        routes.first { $0.eventKey == run.key }
    }

    private func refresh() {
        switch RunCalendar.access {
        case .notDetermined:
            state = .needsPermission
        case .denied:
            state = .denied
        case .granted:
            state = RunCalendar.upcomingRuns().map(Phase.loaded) ?? Phase.noCalendar
        }
    }
}

private struct RunRow: View {
    let run: PlannedRun
    let route: SavedRoute?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(run.title).font(.headline)
                Text(run.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let route {
                Text(RouteFormat.distance(km: route.distanceKm)).font(.subheadline).monospacedDigit()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}

struct RunDetailView: View {
    let run: PlannedRun

    @Query private var routes: [SavedRoute]
    @State private var generating = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var editedShape: RouteShape?
    @State private var showShape = false

    init(run: PlannedRun) {
        self.run = run
        let key = run.key
        _routes = Query(filter: #Predicate<SavedRoute> { $0.eventKey == key })
    }

    private var route: SavedRoute? { routes.first }

    /// The shape chosen in the sheet, else the saved route's.
    private var shape: RouteShape { editedShape ?? route?.shape ?? RouteShape() }

    var body: some View {
        Form {
            if route == nil {
                Section {
                    Text(run.title).font(.headline)
                    LabeledContent("Date", value: run.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    if !run.notes.isEmpty {
                        Text(run.notes).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let route {
                Section {
                    RouteMapView(points: route.points, pins: route.shape?.pins ?? [], interactive: false)
                        .frame(height: 300)
                        .listRowInsets(EdgeInsets())
                    RouteStatsView(
                        distanceKm: route.distanceKm,
                        ascentM: route.ascentM,
                        descentM: route.descentM,
                        hilliness: route.hilliness,
                        elevationGainPerKm: route.elevationGainPerKm
                    )
                    ForEach(route.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.circle").font(.footnote)
                    }
                    if route.warnings.contains(where: RunPlan.isPaceWarning) {
                        Button("Add the pace in Settings, then regenerate") { showSettings = true }
                            .font(.footnote)
                    }
                }
                Section {
                    ShareLink(item: route.gpxFile, preview: SharePreview(route.name)) {
                        Label("Share GPX", systemImage: "square.and.arrow.up")
                    }
                }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            Section {
                ShapeRow(shape: shape) { showShape = true }
                if route == nil {
                    Button { generate(regenerate: false) } label: {
                        Label("Generate route", systemImage: "figure.run").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(generating)
                } else {
                    Button("Regenerate", systemImage: "arrow.clockwise") { generate(regenerate: true) }
                        .disabled(generating)
                }
                if generating { ProgressView() }
            }
        }
        .navigationTitle(run.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showShape) {
            ShapeSheet(shape: Binding(get: { shape }, set: { editedShape = $0 }), targetKm: route?.targetDistanceKm)
        }
    }

    private func generate(regenerate: Bool) {
        guard !generating else { return }
        generating = true
        errorMessage = nil
        Task {
            do {
                _ = try await RunPreparation.prepare(run, regenerate: regenerate, shape: shape)
            } catch {
                errorMessage = error.localizedDescription
            }
            generating = false
        }
    }
}
