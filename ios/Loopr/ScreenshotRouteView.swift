import PhotosUI
import RouteKit
import SwiftUI
import UniformTypeIdentifiers

/// Makes a route from a screenshot of a Runna workout, picked from Photos or pasted.
struct ScreenshotRouteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = ScreenshotRouteModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        PhotosPicker(selection: $pickerItem, matching: .screenshots) {
                            Label("Choose a screenshot", systemImage: "photo")
                        }
                        PasteButton(supportedContentTypes: [.image]) { providers in
                            Task { await paste(providers) }
                        }
                    } footer: {
                        Text("Take a screenshot of the workout in Runna, then choose it here. Back Tap or the Action Button can also run the *Create Route from Screenshot* shortcut for you.")
                    }

                    if model.isBusy {
                        Section {
                            HStack {
                                Text(busyLabel)
                                Spacer()
                                ProgressView()
                            }
                        }
                    }

                    if !model.text.isEmpty { recognisedText }
                    outcome
                }
                .onChange(of: resultID) {
                    guard resultID != nil else { return }
                    withAnimation { proxy.scrollTo("result", anchor: .top) }
                }
            }
            .navigationTitle("From screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onChange(of: pickerItem) {
                guard let pickerItem else { return }
                Task {
                    if let data = try? await pickerItem.loadTransferable(type: Data.self) {
                        await model.load(data)
                    }
                    self.pickerItem = nil
                }
            }
        }
    }

    private var busyLabel: String {
        if case .recognising = model.phase { "Reading the screenshot" } else { "Making the route" }
    }

    private var resultID: String? {
        if case .route(let response, _, _) = model.phase { response.filename + String(response.route.distanceKm) } else { nil }
    }

    private var recognisedText: some View {
        Section {
            TextEditor(text: $model.text)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 140)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Make route from this text", systemImage: "arrow.clockwise") {
                Task { await model.regenerate() }
            }
            .disabled(model.isBusy)
        } header: {
            Text("Recognised workout")
        } footer: {
            Text("Fix anything that was misread, then make the route again.")
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch model.phase {
        case .idle, .recognising, .generating:
            EmptyView()
        case .failed(let message):
            Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
        case .needsDistance(let problems):
            Section {
                ForEach(problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle").font(.footnote)
                }
                Stepper(value: $model.manualKm, in: RouteDistance.allowedKm, step: 0.5) {
                    LabeledContent("Distance", value: RouteFormat.distance(km: model.manualKm))
                }
                Button("Make a route of this distance") { Task { await model.generateManual() } }
                    .disabled(model.isBusy)
            } header: {
                Text("Couldn't confirm the distance")
            } footer: {
                Text("Correct the text above, or set the distance yourself.")
            }
        case .route(let response, let points, let notes):
            RouteResultSections(
                response: response, points: points, startLabel: model.startLabel, name: model.saveName, savedID: $model.savedID)
            if !notes.isEmpty || response.warnings.contains(where: RunPlan.isPaceWarning) {
                Section {
                    ForEach(notes, id: \.self) { Label($0, systemImage: "info.circle").font(.footnote) }
                    if response.warnings.contains(where: RunPlan.isPaceWarning) {
                        Button("Add the pace in Settings, then make the route again") { showSettings = true }
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private func paste(_ providers: [NSItemProvider]) async {
        guard let provider = providers.first,
            let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }),
            let data = await data(of: provider, type: type)
        else { return }
        await model.load(data)
    }

    private func data(of provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
