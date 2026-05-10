//
//  DocumentsPainterApp.swift
//  DocumentsPainter
//
//  Created by Romsya Borysenko on 2/16/26.
//

import SwiftUI

@main
struct DocumentsPainterApp: App {
    @AppStorage("settings.appLanguage") private var appLanguage = "en"

    var body: some Scene {
        WindowGroup {
            ProjectLibraryView()
                .environment(\.locale, Locale(identifier: normalizedAppLanguageId))
        }
    }

    private var normalizedAppLanguageId: String {
        appLanguage == "uk" ? "uk" : "en"
    }
}
