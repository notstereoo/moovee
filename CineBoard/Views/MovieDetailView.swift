import SwiftUI

struct MovieDetailView: View {
    let movie: Movie
    @Environment(\.catalog) private var catalog
    @State private var detail: Movie?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showSave = false

    private var shown: Movie { detail ?? movie }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    PosterImage(path: shown.posterPath, title: shown.title, size: .w500)
                        .frame(width: 140)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(shown.title).font(.title2.bold())
                        if let y = shown.year { Text(y).foregroundStyle(.secondary) }
                        if let r = shown.voteAverage, r > 0 {
                            Label(String(format: "%.1f", r), systemImage: "star.fill").foregroundStyle(.orange)
                        }
                        if let rt = shown.runtime, rt > 0 { Text("\(rt) мин").foregroundStyle(.secondary) }
                        if let g = shown.genres, !g.isEmpty {
                            Text(g.map(\.name).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    showSave = true
                } label: {
                    Label("Сохранить в подборку", systemImage: "bookmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if isLoading && detail == nil { ProgressView("Загружаем подробности…").frame(maxWidth: .infinity) }

                if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").font(.subheadline)
                        Button("Повторить") { Task { await load() } }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                if let overview = shown.overview, !overview.isEmpty {
                    Text("Описание").font(.headline)
                    Text(overview)
                } else if detail != nil {
                    Text("Описание отсутствует.").foregroundStyle(.secondary)
                }

                TMDBAttribution()
            }
            .padding()
        }
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSave) { SaveToCollectionSheet(movie: shown) }
        .task { await load() }
    }

    private func load() async {
        guard detail == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { detail = try await catalog.details(id: movie.id) } catch is CancellationError {} catch {
            errorMessage = userMessage(for: error)
        }
    }
}
