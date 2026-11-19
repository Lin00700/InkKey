//
//  RootView.swift
//  InkKey
//

import SwiftUI

struct RootView: View {
    @ObservedObject private var settings = InkSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let palette = InkPalette.resolve(settings.theme, scheme: colorScheme)
        TabView {
            SetupView()
                .tabItem { Label("键盘", systemImage: "keyboard") }
            VocabularyView()
                .tabItem { Label("生词本", systemImage: "book.closed") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .tint(palette.seal)
        .onAppear(perform: refreshSharedState)
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshSharedState() }
        }
    }

    private func refreshSharedState() {
        settings.reload()
        InkFontCenter.shared.reloadFromDefaults()
        VocabularyStore.shared.reload()
        InkDictionaryStore.shared.load()
    }
}

#Preview {
    RootView()
}
