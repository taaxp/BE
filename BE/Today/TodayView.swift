import SwiftUI
import BECore

/// Home: nothing but widgets. Each one updates live as Apple Health changes
/// and carries a one-line coach note on what it means and what to do.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(HomeLayout.key) private var layoutRaw = HomeLayout.encode(HomeWidget.defaultOrder)
    @State private var editing = false
    @State private var selected: MetricKind?

    private var widgets: [HomeWidget] { HomeLayout.decode(layoutRaw) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.gridSpacing) {
                    ForEach(Array(HomeLayout.rows(widgets).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Theme.gridSpacing) {
                            ForEach(row) { w in
                                WidgetView(widget: w, onSelect: { selected = $0 })
                                    .frame(minHeight: 160)
                            }
                            if row.count == 1 && row[0].size == .small { Color.clear.frame(maxWidth: .infinity) }
                        }
                        // Widgets in a row share one height, and grow with Dynamic Type.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    syncFooter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }
                }
            }
            .refreshable { await model.refreshAll() }
            .sheet(isPresented: $editing) { EditHomeView(layoutRaw: $layoutRaw) }
            .navigationDestination(item: $selected) { MetricDetailView(metric: $0) }
        }
    }

    private var syncFooter: some View {
        Group {
            if let t = model.lastSync {
                Label("Synced with Apple Health \(t.formatted(.relative(presentation: .named)))", systemImage: "heart.text.square")
            } else {
                Label("Connecting to Apple Health…", systemImage: "heart.text.square")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }
}

/// Show, hide and reorder Home widgets.
struct EditHomeView: View {
    @Binding var layoutRaw: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Shown") {
                    ForEach(HomeLayout.decode(layoutRaw)) { w in
                        Label(w.title, systemImage: "line.3.horizontal")
                    }
                    .onMove { from, to in
                        var items = HomeLayout.decode(layoutRaw)
                        items.move(fromOffsets: from, toOffset: to)
                        layoutRaw = HomeLayout.encode(items)
                    }
                    .onDelete { offsets in
                        var items = HomeLayout.decode(layoutRaw)
                        items.remove(atOffsets: offsets)
                        layoutRaw = HomeLayout.encode(items.isEmpty ? [.rings] : items)
                    }
                }
                let hidden = HomeWidget.allCases.filter { !HomeLayout.decode(layoutRaw).contains($0) }
                if !hidden.isEmpty {
                    Section("Add") {
                        ForEach(hidden) { w in
                            Button {
                                layoutRaw = HomeLayout.encode(HomeLayout.decode(layoutRaw) + [w])
                            } label: {
                                Label(w.title, systemImage: "plus.circle.fill")
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
