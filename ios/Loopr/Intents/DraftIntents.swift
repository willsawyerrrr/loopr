import AppIntents
import RouteKit
import SwiftUI
import UIKit

struct RoutePreviewSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Route Preview"
    static let isDiscoverable = false

    @Parameter(title: "Draft")
    var draftID: String

    init() {}

    init(draftID: UUID) {
        self.draftID = draftID.uuidString
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard let id = UUID(uuidString: draftID) else { throw RouteDraftError.expired }
        let draft = try await DraftStore.shared.draft(id)
        return .result(view: RoutePreviewView(draft: draft))
    }
}

struct SaveRouteDraftIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Route"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = [.background]

    @Parameter(title: "Draft")
    var draftID: String

    init() {}

    init(draftID: UUID) {
        self.draftID = draftID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: draftID) else { throw RouteDraftError.expired }
        var draft = try await DraftStore.shared.draft(id)
        if draft.savedID == nil {
            draft.savedID = RouteStore.save(response: draft.response, points: draft.points).id
            await DraftStore.shared.put(draft)
        }
        RoutePreviewSnippetIntent.reload()
        return .result()
    }
}

struct RegenerateRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Regenerate Route"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = [.background]

    @Parameter(title: "Draft")
    var draftID: String

    init() {}

    init(draftID: UUID) {
        self.draftID = draftID.uuidString
    }

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        guard let id = UUID(uuidString: draftID) else { throw RouteDraftError.expired }
        let old = try await DraftStore.shared.draft(id)
        let draft = try await RouteGenerator.makeDraft(targetKm: old.targetKm, start: old.start)
        return .result(snippetIntent: RoutePreviewSnippetIntent(draftID: draft.id))
    }
}

struct RoutePreviewView: View {
    let draft: RouteDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = draft.snapshotPNG, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(RouteSnapshot.size.width / RouteSnapshot.size.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text(RouteFormat.subtitle(distanceKm: draft.response.route.distanceKm, ascentM: draft.response.route.ascentM))
                .font(.headline)
            Text(draft.response.route.hilliness.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                if draft.savedID == nil {
                    Button(intent: SaveRouteDraftIntent(draftID: draft.id)) {
                        Label("Save", systemImage: "bookmark")
                    }
                } else {
                    Label("Saved", systemImage: "bookmark.fill")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: RegenerateRouteIntent(draftID: draft.id)) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
