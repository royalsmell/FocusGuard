import SharedCore
import SwiftUI

struct ProviderListView: View {
    @Environment(AppModel.self) private var model
    @State private var editingProvider: ProviderConfig?
    @State private var showingAddEditor = false

    var body: some View {
        List {
            ForEach(model.providerStore.providers) { provider in
                Button {
                    model.providerStore.setActiveProvider(id: provider.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.name).font(.headline)
                            Text(provider.model).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.providerStore.activeProviderID == provider.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        Button {
                            editingProvider = provider
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .padding(.leading, 8)
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if model.providerStore.providers.count > 1 {
                        Button(role: .destructive) {
                            model.providerStore.deleteProvider(id: provider.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("API 账户")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingProvider) { provider in
            NavigationStack {
                ProviderEditorView(initialConfig: provider)
            }
        }
        .sheet(isPresented: $showingAddEditor) {
            NavigationStack {
                ProviderEditorView(initialConfig: nil)
            }
        }
    }
}
