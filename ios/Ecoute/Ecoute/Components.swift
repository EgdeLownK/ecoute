import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Carte arrondie sur fond groupé.
struct CardModifier: ViewModifier {
    var dashed = false
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(dashed ? Color.clear : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(.secondary.opacity(0.5))
                }
            }
    }
}
extension View {
    func card(dashed: Bool = false) -> some View { modifier(CardModifier(dashed: dashed)) }
}

struct CategoryChip: View {
    let cat: Category
    let selected: Bool
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(hex: cat.colorHex)).frame(width: 9, height: 9)
            Text(cat.name).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(selected ? Color(hex: cat.colorHex).opacity(0.18) : Color(.secondarySystemGroupedBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? Color(hex: cat.colorHex) : Color.clear, lineWidth: 1.5))
        .foregroundStyle(.primary)
    }
}

struct PulseDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Color.red).frame(width: 11, height: 11)
            .overlay(Circle().stroke(Color.red.opacity(0.5), lineWidth: 2).scaleEffect(on ? 2.2 : 1).opacity(on ? 0 : 1))
            .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true } }
    }
}

/// Petite animation d'écoute (pas un flux de données).
struct ListeningBars: View {
    var color: Color = .accentColor
    @State private var on = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 4, height: on ? 18 : 5)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.12), value: on)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .onAppear { on = true }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
    }
}

/// Liste à puces simple.
struct BulletList: View {
    let items: [String]
    var font: Font = .body
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, x in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Color.secondary.opacity(0.6)).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                    Text(x).font(font).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Encadré des points essentiels.
struct KeyPointsCard: View {
    var title = "À retenir"
    let items: [String]
    var color: Color = .accentColor
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "star.fill").font(.subheadline.weight(.semibold)).foregroundStyle(color)
            BulletList(items: items)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// La fiche d'une partie : chapeau, essentiel, sections avec intertitres, puis les rubriques.
struct WriteupView: View {
    let writeup: Writeup
    let part: Part
    var showChapo = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showChapo, !writeup.chapeau.isEmpty {
                Text(writeup.chapeau).font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
            if !writeup.aRetenir.isEmpty { KeyPointsCard(items: writeup.aRetenir) }
            if !writeup.shownSections.isEmpty {
                ForEach(Array(writeup.shownSections.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 6) {
                        if !s.intertitre.isEmpty { Text(s.intertitre).font(.headline) }
                        Text(s.texte).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ForEach(Array(writeup.compteRendu.enumerated()), id: \.offset) { _, para in
                    Text(para).font(.body).lineSpacing(4)
                }
            }
            rubric("Décisions", writeup.decisions)
            if !writeup.actions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Actions")
                    ForEach(Array(writeup.actions.enumerated()), id: \.offset) { _, a in ActionRow(action: a) }
                }
            }
            if !writeup.definitions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Définitions")
                    ForEach(Array(writeup.definitions.enumerated()), id: \.offset) { _, d in DefinitionRow(def: d) }
                }
            }
            let quotes = writeup.citations.isEmpty ? part.quotes : writeup.citations
            if !quotes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Citations")
                    ForEach(Array(quotes.enumerated()), id: \.offset) { _, q in QuoteRow(quote: q) }
                }
            }
            let refs = writeup.references.isEmpty ? part.refs : writeup.references
            if !refs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Références")
                    ForEach(Array(refs.enumerated()), id: \.offset) { _, r in ReferenceRow(ref: r) }
                }
            }
            rubric("Pour aller plus loin", writeup.questions)
        }
    }

    @ViewBuilder
    private func rubric(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: title)
                BulletList(items: items)
            }
        }
    }
}

struct QuoteRow: View {
    let quote: Quote
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("« \(quote.texte) »").italic().fixedSize(horizontal: false, vertical: true)
                if !quote.auteur.isEmpty { Text(quote.auteur).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

struct ReferenceRow: View {
    let ref: Reference
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(ref.nom).font(.subheadline.weight(.semibold))
                if !ref.type.isEmpty { Text(ref.type).font(.caption).foregroundStyle(.secondary) }
            }
            if !ref.contexte.isEmpty { Text(ref.contexte).font(.footnote).foregroundStyle(.secondary) }
        }
    }
}

struct DefinitionRow: View {
    let def: Definition
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(def.terme).font(.subheadline.weight(.semibold))
            Text(def.definition).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct ActionRow: View {
    let action: ActionItem
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle").font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.quoi)
                let extra = [action.qui, action.quand].filter { !$0.isEmpty }.joined(separator: " · ")
                if !extra.isEmpty { Text(extra).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Feuille de partage iOS (fichiers ou texte).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Message temporaire en bas de l'écran.
struct BannerView: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
