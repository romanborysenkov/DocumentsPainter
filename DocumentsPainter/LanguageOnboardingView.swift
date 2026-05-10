import SwiftUI

struct LanguageOnboardingView: View {
    @AppStorage("settings.nativeLanguage") private var nativeLanguage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    Text("Оберіть рідну мову")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Це вплине на автоімпорт перекладів і локалізацію бібліотеки.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(BibleLibraryCatalog.supportedLanguages) { language in
                                languageOptionButton(language)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)

                    if let selected = selectedLanguage {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Вибрано: \(selected.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var selectedLanguage: AppLanguage? {
        BibleLibraryCatalog.supportedLanguages.first(where: { $0.id == nativeLanguage })
    }

    private func languageOptionButton(_ language: AppLanguage) -> some View {
        let isSelected = nativeLanguage == language.id
        return Button {
            nativeLanguage = language.id
        } label: {
            VStack(spacing: 7) {
                Text(flag(for: language.id))
                    .font(.system(size: 28))
                    .frame(width: 68, height: 68)
                    .background(
                        Circle()
                            .fill(isSelected ? Color(UIColor.systemBackground) : Color(UIColor.tertiarySystemBackground))
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.primary : Color(UIColor.separator).opacity(0.5), lineWidth: isSelected ? 2.2 : 1)
                    )

                Text(language.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 98)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.title)
    }

    private func flag(for languageId: String) -> String {
        switch languageId {
        case "uk": return "🇺🇦"
        case "en": return "🇺🇸"
        case "ru": return "🇷🇺"
        case "es": return "🇪🇸"
        case "pt": return "🇵🇹"
        default: return "🌐"
        }
    }
}
