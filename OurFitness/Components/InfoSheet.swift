// Shared chrome for the app's ⓘ info sheets.
//
// Every info sheet was the same thing: a ScrollView, an oversized lowercase
// title, an all-caps subtitle, then a stack of all-caps sections holding boxed
// rows and dot bullets — copy-pasted with its own private `infoSection` /
// `calcRow` / `infoRow` / `bullet` / `researchRow` helpers in each file. This
// file is that chrome, once.
//
// It deliberately carries NO copy of its own: every string, number and citation
// stays at the call site. Where two sheets worded the same idea differently,
// both wordings survive verbatim and only the box they sit in is shared.
//
// The knobs (`titleSize`, `dragIndicator`, `InfoRow.Emphasis`, `labelWraps`,
// `Bullet.Marker`, `InfoHeroStat.valueSize`) exist only because the originals
// genuinely differed there — they are not speculative options.

import SwiftUI

// MARK: - Scaffold

/// Scrolling info sheet: hero title + all-caps subtitle, medium/large detents,
/// themed background. Pass the sections as the content.
public struct InfoSheetScaffold<Content: View>: View {
    public let title: String
    public let subtitle: String
    /// 42 everywhere except the Heart-health sheet, whose title is long (38).
    public let titleSize: CGFloat
    /// Some sheets show the grabber, some don't. `false` == no modifier applied.
    public let dragIndicator: Bool
    /// Most ⓘ sheets open at medium and can be dragged up. A few are long
    /// enough that opening at medium reads as truncated — those pass `[.large]`.
    public let detents: Set<PresentationDetent>
    public let content: () -> Content

    @Environment(\.theme) private var theme

    public init(
        title: String,
        subtitle: String,
        titleSize: CGFloat = 42,
        dragIndicator: Bool = false,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleSize = titleSize
        self.dragIndicator = dragIndicator
        self.detents = detents
        self.content = content
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: titleSize, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents(detents)
        .presentationDragIndicator(dragIndicator ? .visible : .automatic)
        .presentationBackground(theme.bg)
    }
}

// MARK: - Section

/// All-caps tracked section heading + its content.
public struct InfoSection<Content: View>: View {
    public let title: String
    public let content: () -> Content

    @Environment(\.theme) private var theme

    public init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption).tracking(2)
                .foregroundStyle(theme.dim)
            content()
        }
    }
}

// MARK: - Body copy

/// Dimmed callout paragraph that wraps rather than truncates.
public struct InfoBody: View {
    public let text: String
    @Environment(\.theme) private var theme

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).font(.callout).foregroundStyle(theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Small print at the foot of a sheet — sources, caveats, methodology.
public struct InfoFootnote: View {
    public let text: String
    @Environment(\.theme) private var theme

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Boxed rows

/// Two stacked lines in a bordered box: one body line and one monospaced accent
/// line. `emphasis` picks which is which — both orderings already shipped (the
/// Move breakdown rows lead with the body line, the Steps rows lead with the
/// accent line), so both are preserved.
public struct InfoRow: View {
    public enum Emphasis { case detail, label }

    public let label: String
    public let detail: String
    public let emphasis: Emphasis

    @Environment(\.theme) private var theme

    public init(label: String, detail: String, emphasis: Emphasis = .detail) {
        self.label = label
        self.detail = detail
        self.emphasis = emphasis
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch emphasis {
            case .detail:
                plainLine(label)
                accentLine(detail)
            case .label:
                accentLine(label)
                plainLine(detail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func plainLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.text)
    }

    @ViewBuilder
    private func accentLine(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(theme.accent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Side-by-side calculation row in a bordered box: label on the left, a
/// monospaced accent figure on the right. `labelWraps` lets a long label grow
/// to two lines (the calorie breakdown needs it; the water math doesn't).
public struct InfoCalcRow: View {
    public let label: String
    public let detail: String
    public let labelWraps: Bool

    @Environment(\.theme) private var theme

    public init(label: String, detail: String, labelWraps: Bool = false) {
        self.label = label
        self.detail = detail
        self.labelWraps = labelWraps
    }

    public var body: some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: labelWraps)
            Spacer(minLength: 8)
            Text(detail).font(.system(.callout, design: .monospaced)).foregroundStyle(theme.accent)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

/// Icon + name/detail on the left, a big monospaced figure + unit on the right.
/// The per-item stat row used by the Move column sheets.
public struct InfoMetricRow: View {
    public let icon: String
    public let name: String
    public let detail: String
    public let value: String
    public let unit: String

    @Environment(\.theme) private var theme

    public init(icon: String, name: String, detail: String = "", value: String, unit: String = "cal") {
        self.icon = icon
        self.name = name
        self.detail = detail
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.dim)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Right-aligned hero total: tiny tracked label over a large accent figure.
public struct InfoHeroStat: View {
    public let label: String
    public let value: String
    /// 28 for the section totals; the Training sheet's total shipped at 24.
    public let valueSize: CGFloat

    @Environment(\.theme) private var theme

    public init(label: String, value: String, valueSize: CGFloat = 28) {
        self.label = label
        self.value = value
        self.valueSize = valueSize
    }

    public var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(theme.dim)
                Text(value)
                    .font(.system(size: valueSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Bullets

/// A dimmed callout line with a leading marker. `.dot` is the research/benefit
/// bullet used across the sheets; `.check` / `.cross` are the "what's counted"
/// in/out pair.
public struct Bullet: View {
    public enum Marker { case dot, check, cross }

    public let text: String
    public let marker: Marker

    @Environment(\.theme) private var theme

    public init(_ text: String, marker: Marker = .dot) {
        self.text = text
        self.marker = marker
    }

    public var body: some View {
        HStack(alignment: .top, spacing: marker == .dot ? 8 : 6) {
            markerGlyph
            Text(text).font(.callout).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var markerGlyph: some View {
        switch marker {
        case .dot:
            Text("·").foregroundStyle(theme.accent).font(.callout)
        case .check:
            Text("✓").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.ok)
        case .cross:
            Text("✗").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.dim)
        }
    }
}
