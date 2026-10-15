// One restaurant's menu, pushed from AddFoodSheet's Restaurants row: the
// chain's own categories (jump pills + sections, source order) and a search
// field that filters in memory on every keystroke (a few hundred rows — no SQL).
// A tapped item goes back through `onPick`, which AddFoodSheet routes into the
// same MealIngredientDetailSheet confirm/log flow as every other pick, so this
// view never writes a log itself. Data: `Domain/RestaurantCatalog.swift`.

import SwiftUI

struct RestaurantMenuView: View {
    let chain: RestaurantChain
    /// What followed the chain name in Add food ("shake shack fries" → "fries").
    let initialQuery: String
    let onPick: (RestaurantMenuItem) -> Void

    @Environment(\.theme) private var theme

    @State private var query = ""
    @State private var didSeed = false
    @FocusState private var searchFocused: Bool

    private var menu: [RestaurantMenuItem] { RestaurantCatalog.shared.menu(for: chain.slug) }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let sections = RestaurantMatcher.sections(menu)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField
                    if trimmedQuery.isEmpty {
                        if sections.count > 1 { categoryPills(sections, proxy: proxy) }
                        // Rows are lazy individually (a category can hold 400+
                        // drinks); the header carries the category id so a pill
                        // can scrollTo a section not yet built.
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.items) { row($0) }
                                } header: {
                                    sectionHeader(section.category)
                                        .padding(.top, 8)
                                        .id(section.category)
                                }
                            }
                        }
                    } else {
                        let hits = RestaurantMatcher.filter(menu, query: trimmedQuery)
                        if hits.isEmpty {
                            Text("Nothing on the \(chain.name) \(chain.isBrand ? "product list" : "menu") matches “\(trimmedQuery)”.")
                                .font(.callout).foregroundStyle(theme.dim)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(hits) { row($0) }
                            }
                        }
                    }
                    if menu.isEmpty {
                        Text("No \(chain.isBrand ? "products" : "menu items") for \(chain.name).")
                            .font(.callout).foregroundStyle(theme.dim)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(chain.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }
            }
        }
        .onAppear {
            guard !didSeed else { return }
            didSeed = true
            query = initialQuery
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.dim)
            TextField("Search \(chain.name)", text: $query)
                .foregroundStyle(theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .submitLabel(.done)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark") }
                    .tactile(.ghost)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func categoryPills(_ sections: [RestaurantMenuSection], proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections) { section in
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            proxy.scrollTo(section.category, anchor: .top)
                        }
                    } label: {
                        Text(section.category)
                    }
                    .tactile(.pill)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium)).tracking(2)
            .foregroundStyle(theme.dim)
    }

    /// The shared food row, showing the menu's own item name (the chain is the
    /// screen title). The logged food keeps its full "<Chain> <Item>" name.
    @ViewBuilder
    private func row(_ item: RestaurantMenuItem) -> some View {
        let f = item.food
        FoodResultRow(
            food: CommonFood(
                id: f.id, name: item.itemName, aliases: [], servingLabel: f.servingLabel,
                calories: f.calories, proteinG: f.proteinG, carbsG: f.carbsG,
                fatG: f.fatG, fiberG: f.fiberG
            )
        ) {
            Haptics.tap()
            onPick(item)
        }
    }
}
