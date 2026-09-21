import RouteKit
import SwiftUI

struct SettingsView: View {
    private struct PaceRow: Identifiable, Equatable {
        let id = UUID()
        var phrase: String
        var pace: Double
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(RunCalendar.chosenCalendarKey) private var calendarID = ""
    @AppStorage(MorningRefresh.enabledKey) private var morningEnabled = false

    @State private var calendars: [CalendarSummary] = []
    @State private var rows = PaceStore().paces.sorted { $0.key < $1.key }.map { PaceRow(phrase: $0.key, pace: $0.value) }
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if RunCalendar.access == .granted {
                        Picker("Calendar", selection: $calendarID) {
                            Text("Automatic (\(RunPlan.calendarName))").tag("")
                            ForEach(calendars, id: \.id) { Text($0.title).tag($0.id) }
                        }
                    } else {
                        Text("Allow calendar access on the Runs tab to choose a calendar.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Automatic uses the calendar whose name contains “\(RunPlan.calendarName)”.")
                }

                Section("Route preferences") { PreferenceSliders() }

                Section {
                    ForEach($rows) { $row in
                        HStack {
                            TextField("Pace phrase", text: $row.phrase)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("min/km", value: $row.pace, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("min/km").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    Button("Add pace", systemImage: "plus") { rows.append(PaceRow(phrase: "", pace: 6)) }
                } header: {
                    Text("Paces")
                } footer: {
                    Text("Runna pace phrases and how fast you run them, used to work out each workout's distance. Add a phrase when a route warns that its pace isn't configured.")
                }

                Section {
                    Toggle("Prepare routes each morning", isOn: morningBinding)
                } footer: {
                    Text(
                        notificationsDenied
                            ? "Notifications are off for Loopr. Allow them in the system Settings to use this."
                            : "Around 06:00 Loopr prepares the route for today's (or the next) run and notifies you. iOS chooses when background refreshes run, so timing isn't guaranteed."
                    )
                }
                if notificationsDenied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .onAppear { calendars = RunCalendar.access == .granted ? RunCalendar.calendars().sorted { $0.title < $1.title } : [] }
            .onChange(of: rows) {
                PaceStore().save(
                    Dictionary(
                        rows.map { ($0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.pace) },
                        uniquingKeysWith: { _, new in new }))
            }
        }
    }

    private var morningBinding: Binding<Bool> {
        Binding(
            get: { morningEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        notificationsDenied = !(await MorningRefresh.enable())
                    }
                } else {
                    morningEnabled = false
                    MorningRefresh.schedule()
                    notificationsDenied = false
                }
            }
        )
    }
}
