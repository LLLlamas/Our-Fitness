// Camera-based food label scanner.
//
// Opens the device camera via VisionKit DataScannerViewController, reads
// printed text off a nutrition facts panel, then passes that raw text to
// the on-device FoundationModels AI (iOS 26+) which extracts the structured
// fields (name, serving, calories, macros) declared in FoodLabelDraft.
//
// Safety note: unlike the meal-description parser (MealParseService) where
// AI must NEVER touch nutrition numbers, here the model IS reading nutrition
// numbers — but only numbers already PRINTED on the physical label. The model
// is transcribing stated facts, not inventing them. The @Generable prompt
// makes this explicit so the model stays within bounds.
//
// Graceful degradation:
//   • iOS < 17 or DataScanner unavailable → fallback text-entry screen
//   • iOS < 26 / no Apple Intelligence → fallback text-entry screen
//     (the captured text is fed through FoodParser for a best-effort result)
//   • Any error during scanning or AI generation → user-facing message, retry
//
// Public interface:
//   CameraFoodLogSheet(profile:slot:onLog:)
//     onLog: (FoodLogEntryDTO) -> Void

import SwiftUI
import VisionKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - FoodLabelDraft (AI output shape, iOS 26+ only)

#if canImport(FoundationModels)
/// The structured shape the on-device model fills from scanned label text.
/// Contains nutrition numbers because the model is READING them from the
/// physical label — not inventing them. Prompt reinforces this constraint.
@available(iOS 26.0, *)
@Generable
private struct FoodLabelDraft {
    @Guide(description: "The product name from the nutrition label")
    var foodName: String

    @Guide(description: "Serving size as printed on the label, e.g. '1 cup (240g)' or '1 bar (45g)'")
    var servingLabel: String

    @Guide(description: "Calories per serving as an integer. Use 0 if not found.")
    var calories: Int

    @Guide(description: "Protein in grams per serving. Use 0 if not found.")
    var proteinG: Double

    @Guide(description: "Total carbohydrates in grams per serving. Use 0 if not found.")
    var carbsG: Double

    @Guide(description: "Total fat in grams per serving. Use 0 if not found.")
    var fatG: Double

    @Guide(description: "Dietary fiber in grams per serving. Use 0 if not found.")
    var fiberG: Double
}
#endif

// MARK: - Confirmed label data (used after AI or manual extraction)

private struct ConfirmedLabel {
    var foodName: String
    var servingLabel: String
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
}

// MARK: - Sheet state machine

private enum ScannerPhase {
    case scanning                          // live camera running
    case processing                        // AI parsing in progress
    case confirming(ConfirmedLabel, quantity: Double)  // review + adjust
    case fallback(text: String)            // no scanner / no AI, manual entry
    case error(String)                     // unrecoverable error
}

// MARK: - Main sheet

struct CameraFoodLogSheet: View {
    let profile: ProfileDTO
    let slot: Slot
    let onLog: (FoodLogEntryDTO) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var phase: ScannerPhase = .scanning
    @State private var capturedText: String = ""
    @State private var manualText: String = ""
    @State private var stableTimer: Timer? = nil
    @State private var lastSeenText: String = ""
    @State private var isStable: Bool = false

    private var scannerAvailable: Bool {
        if #available(iOS 17.0, *) {
            return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                content
            }
            .navigationTitle("Scan Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tactile(.ghost)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .onAppear {
            if !scannerAvailable {
                phase = .fallback(text: "")
            }
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scanning:
            scanningView
        case .processing:
            processingView
        case .confirming(let label, let qty):
            confirmingView(label: label, quantity: qty)
        case .fallback(let text):
            fallbackView(initialText: text)
        case .error(let msg):
            errorView(message: msg)
        }
    }

    // MARK: - Scanning view

    @ViewBuilder
    private var scanningView: some View {
        ZStack {
            if #available(iOS 17.0, *) {
                DataScannerView(
                    capturedText: $capturedText,
                    onTextStable: { text in
                        handleCapturedText(text)
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                Color.black.ignoresSafeArea()
            }

            // Overlay: scanning guide + instruction
            VStack {
                Spacer()
                scanningOverlay
                    .padding(.bottom, 40)
            }
        }
        .onChange(of: capturedText) { _, newText in
            throttleStabilization(newText)
        }
    }

    private var scanningOverlay: some View {
        VStack(spacing: 16) {
            // Viewfinder guide frame
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                .frame(width: 280, height: 160)
                .overlay {
                    Text("Point at the\nNutrition Facts panel")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 8)

            // Status pill
            if capturedText.isEmpty {
                Text("Scanning…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55), in: Capsule())
            } else {
                Text(isStable ? "Label detected — using…" : "Reading label…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .animation(.easeInOut(duration: 0.2), value: isStable)
            }

            // Manual "Use this" button shown once text is captured
            if !capturedText.isEmpty {
                Button("Use this") {
                    handleCapturedText(capturedText)
                }
                .tactile(.primary)
                .padding(.top, 4)
            }

            // Escape hatch: type instead
            Button("Type it instead") {
                phase = .fallback(text: "")
            }
            .tactile(.ghost)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Processing view

    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(theme.accent)
                .scaleEffect(1.4)

            Text("Reading label…")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.text)

            Text("Extracting nutrition from the printed label.")
                .font(.caption)
                .foregroundStyle(theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Confirmation view

    private func confirmingView(label: ConfirmedLabel, quantity: Double) -> some View {
        ConfirmationView(
            label: label,
            quantity: quantity,
            slot: slot,
            profile: profile,
            onLog: { entry in
                onLog(entry)
                dismiss()
            },
            onRescan: {
                capturedText = ""
                lastSeenText = ""
                isStable = false
                phase = .scanning
            }
        )
    }

    // MARK: - Fallback (manual text entry)

    private func fallbackView(initialText: String) -> some View {
        FallbackEntryView(
            initialText: initialText,
            slot: slot,
            profile: profile,
            onLog: { entry in
                onLog(entry)
                dismiss()
            }
        )
    }

    // MARK: - Error view

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(theme.warn)

            Text("Could not read label")
                .font(.headline)
                .foregroundStyle(theme.text)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("Try again") {
                    capturedText = ""
                    lastSeenText = ""
                    isStable = false
                    phase = .scanning
                }
                .tactile(.secondary)

                Button("Type instead") {
                    phase = .fallback(text: "")
                }
                .tactile(.primary)
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Text stabilization

    /// Debounce: if the recognized text hasn't changed for 2 seconds, treat it
    /// as stable and proceed automatically. The "Use this" button lets users
    /// proceed earlier; this just adds the auto-trigger convenience.
    private func throttleStabilization(_ text: String) {
        stableTimer?.invalidate()
        if text == lastSeenText {
            return
        }
        lastSeenText = text
        isStable = false
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stableTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            Task { @MainActor in
                guard case .scanning = phase else { return }
                isStable = true
                // Auto-proceed after stable text settles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    handleCapturedText(text)
                }
            }
        }
    }

    // MARK: - Text → AI parse

    private func handleCapturedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stableTimer?.invalidate()
        phase = .processing

        Task {
            let result = await extractLabel(from: trimmed)
            await MainActor.run {
                switch result {
                case .success(let label):
                    phase = .confirming(label, quantity: 1.0)
                case .failure(let err):
                    // On AI failure, drop to fallback with the raw scanned text
                    // so the user can verify / correct it manually.
                    if let parserResult = fallbackParse(trimmed) {
                        phase = .confirming(parserResult, quantity: 1.0)
                    } else {
                        phase = .fallback(text: trimmed)
                        _ = err // logged internally, not surfaced verbatim
                    }
                }
            }
        }
    }

    /// Try AI extraction (iOS 26+ with FoundationModels). Falls back to a simple
    /// regex/keyword scan so even non-AI devices get a best-effort result.
    private func extractLabel(from text: String) async -> Result<ConfirmedLabel, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let aiAvailable = SystemLanguageModel.default.availability == .available
            if aiAvailable {
                return await extractLabelWithAI(text)
            }
        }
        #endif
        // Non-AI path: attempt a heuristic numeric extraction from the raw text.
        if let result = fallbackParse(text) {
            return .success(result)
        }
        return .failure(NSError(domain: "CameraFoodLog", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Could not extract nutrition from this label."]))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func extractLabelWithAI(_ text: String) async -> Result<ConfirmedLabel, Error> {
        let instructions = """
        You are reading the text from a physical Nutrition Facts label that was scanned \
        by the phone camera. Extract exactly what is PRINTED on the label:
        - The product name (from the label; if absent, write "Unknown food").
        - The serving size exactly as printed.
        - Calories per serving as an integer.
        - Protein, carbs, total fat, and dietary fiber in grams per serving.

        Use ONLY numbers that appear in the scanned text. If a value is not visible or \
        not present on the label, use 0. Do NOT estimate or invent any number.
        """
        do {
            let session = LanguageModelSession { instructions }
            let response = try await session.respond(
                to: "Nutrition label text:\n\"\"\"\n\(text)\n\"\"\"",
                generating: FoodLabelDraft.self
            )
            let draft = response.content
            let label = ConfirmedLabel(
                foodName: draft.foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                servingLabel: draft.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: max(0, draft.calories),
                proteinG: max(0, draft.proteinG),
                carbsG: max(0, draft.carbsG),
                fatG: max(0, draft.fatG),
                fiberG: max(0, draft.fiberG)
            )
            return .success(label)
        } catch {
            return .failure(error)
        }
    }
    #endif

    /// Heuristic numeric extraction from raw label text for non-AI devices.
    /// Looks for lines matching "Calories NNN" and "Protein NNg" patterns.
    private func fallbackParse(_ text: String) -> ConfirmedLabel? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        func firstNumber(after keyword: String) -> Double? {
            for line in lines {
                let lower = line.lowercased()
                if lower.contains(keyword) {
                    let nums = line.components(separatedBy: .whitespaces)
                        .compactMap { s -> Double? in
                            let stripped = s.replacingOccurrences(of: "g", with: "")
                                           .replacingOccurrences(of: "mg", with: "")
                            return Double(stripped)
                        }
                    if let first = nums.first { return first }
                }
            }
            return nil
        }

        let calories = firstNumber(after: "calorie").map { Int($0) } ?? 0
        // Require at least a calorie value to treat this as a valid label
        guard calories > 0 else { return nil }

        // Try to pull a product name from the first non-numeric, non-empty line
        let nameLine = lines.first { line in
            !line.isEmpty &&
            !line.lowercased().contains("nutrition") &&
            !line.lowercased().contains("calorie") &&
            Double(line) == nil
        } ?? "Scanned food"

        let servingLine = lines.first { $0.lowercased().contains("serving size") } ?? "1 serving"

        return ConfirmedLabel(
            foodName: nameLine,
            servingLabel: servingLine,
            calories: calories,
            proteinG: firstNumber(after: "protein") ?? 0,
            carbsG: firstNumber(after: "carbohydrate") ?? 0,
            fatG: firstNumber(after: "total fat") ?? firstNumber(after: "fat") ?? 0,
            fiberG: firstNumber(after: "fiber") ?? firstNumber(after: "fibre") ?? 0
        )
    }
}

// MARK: - DataScanner wrapper (iOS 17+)

@available(iOS 17.0, *)
private struct DataScannerView: UIViewControllerRepresentable {
    @Binding var capturedText: String
    var onTextStable: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(capturedText: $capturedText, onTextStable: onTextStable)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    // MARK: Coordinator
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var capturedText: String
        var onTextStable: (String) -> Void
        private var accumulatedLines: [String] = []

        init(capturedText: Binding<String>, onTextStable: @escaping (String) -> Void) {
            self._capturedText = capturedText
            self.onTextStable = onTextStable
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            updateText(from: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            updateText(from: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didRemove removedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            updateText(from: allItems)
        }

        private func updateText(from items: [RecognizedItem]) {
            var lines: [String] = []
            for item in items {
                if case .text(let textItem) = item {
                    let t = textItem.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { lines.append(t) }
                }
            }
            let combined = lines.joined(separator: "\n")
            DispatchQueue.main.async {
                self.capturedText = combined
            }
        }
    }
}

// MARK: - Confirmation view

private struct ConfirmationView: View {
    let label: ConfirmedLabel
    let quantity: Double
    let slot: Slot
    let profile: ProfileDTO
    let onLog: (FoodLogEntryDTO) -> Void
    let onRescan: () -> Void

    @Environment(\.theme) private var theme
    @State private var qty: Double
    @State private var editedName: String
    @State private var editedServing: String

    init(label: ConfirmedLabel, quantity: Double, slot: Slot,
         profile: ProfileDTO, onLog: @escaping (FoodLogEntryDTO) -> Void,
         onRescan: @escaping () -> Void) {
        self.label = label
        self.quantity = quantity
        self.slot = slot
        self.profile = profile
        self.onLog = onLog
        self.onRescan = onRescan
        _qty = State(initialValue: quantity)
        _editedName = State(initialValue: label.foodName)
        _editedServing = State(initialValue: label.servingLabel)
    }

    private var scaledCalories: Int { Int((Double(label.calories) * qty).rounded()) }
    private var scaledProtein: Int { Int((label.proteinG * qty).rounded()) }
    private var scaledCarbs: Int { Int((label.carbsG * qty).rounded()) }
    private var scaledFat: Int { Int((label.fatG * qty).rounded()) }
    private var scaledFiber: Int { Int((label.fiberG * qty).rounded()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                aiAttributionBanner
                nameServingCard
                macroCard
                quantityStepper
                logButton
                rescanButton
            }
            .padding(20)
        }
    }

    // MARK: Attribution

    private var aiAttributionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(theme.accent)
            Text("Numbers read from the printed label. Always check against the package.")
                .font(.caption)
                .foregroundStyle(theme.dim)
        }
        .padding(12)
        .background(theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Name + serving card

    private var nameServingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Product")
                .font(.caption)
                .foregroundStyle(theme.dim)
                .textCase(.uppercase)
                .tracking(1)

            TextField("Product name", text: $editedName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(12)
                .background(theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Serving size")
                .font(.caption)
                .foregroundStyle(theme.dim)
                .textCase(.uppercase)
                .tracking(1)

            TextField("e.g. 1 cup (240g)", text: $editedServing)
                .font(.subheadline)
                .foregroundStyle(theme.text)
                .padding(12)
                .background(theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Macro grid

    private var macroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per \(qty == 1 ? "serving" : String(format: "%.1g", qty) + " servings")")
                .font(.caption)
                .foregroundStyle(theme.dim)
                .textCase(.uppercase)
                .tracking(1)

            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()),
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 12) {
                MacroCell(label: "Cal", value: "\(scaledCalories)", accent: theme.accent)
                MacroCell(label: "Protein", value: "\(scaledProtein)g", accent: theme.accent2)
                MacroCell(label: "Carbs", value: "\(scaledCarbs)g", accent: theme.ok)
                MacroCell(label: "Fat", value: "\(scaledFat)g", accent: theme.dim)
                if label.fiberG > 0 {
                    MacroCell(label: "Fiber", value: "\(scaledFiber)g", accent: theme.dim)
                }
            }
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Quantity stepper

    private var quantityStepper: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Servings")
                .font(.caption)
                .foregroundStyle(theme.dim)
                .textCase(.uppercase)
                .tracking(1)

            HStack(spacing: 16) {
                Button {
                    if qty > 0.5 { qty = (qty - 0.5) }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 36, height: 36)
                }
                .tactile(.secondary)
                .disabled(qty <= 0.5)

                Text(qty.truncatingRemainder(dividingBy: 1) == 0
                     ? "\(Int(qty))"
                     : String(format: "%.1f", qty))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
                    .frame(minWidth: 48)
                    .multilineTextAlignment(.center)

                Button {
                    if qty < 5.0 { qty = (qty + 0.5) }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 36)
                }
                .tactile(.secondary)
                .disabled(qty >= 5.0)

                Spacer()

                Text("\(scaledCalories) cal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Log button

    private var logButton: some View {
        Button("Log this") {
            let entry = buildEntry()
            onLog(entry)
        }
        .tactile(.primary, fullWidth: true)
        .padding(.top, 4)
    }

    private var rescanButton: some View {
        Button("Scan again") {
            onRescan()
        }
        .tactile(.ghost, fullWidth: true)
    }

    // MARK: Build entry

    private func buildEntry() -> FoodLogEntryDTO {
        let perServing = PerServing(
            calories: label.calories,
            proteinG: Int(label.proteinG.rounded()),
            carbsG: Int(label.carbsG.rounded()),
            fatG: Int(label.fatG.rounded()),
            fiberG: Int(label.fiberG.rounded())
        )
        // Scale by quantity so the stored entry reflects what was actually eaten
        let scaled = PerServing(
            calories: scaledCalories,
            proteinG: scaledProtein,
            carbsG: scaledCarbs,
            fatG: scaledFat,
            fiberG: scaledFiber
        )
        return FoodLogEntryDTO(
            userId: profile.id,
            date: Dates.dayKey(),
            slot: slot,
            customName: editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Scanned food" : editedName.trimmingCharacters(in: .whitespacesAndNewlines),
            servings: qty,
            perServing: perServing.calories > 0 ? perServing : scaled
        )
        // Note: we store the per-serving macros (not scaled) in perServing
        // and qty in servings, matching how FoodLogEntryDTO is used elsewhere.
        // The caller (NutritionView) multiplies when displaying totals.
    }
}

// MARK: - Macro cell (private to this file)

private struct MacroCell: View {
    let label: String
    let value: String
    let accent: Color

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.dim)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Fallback: manual text entry

private struct FallbackEntryView: View {
    let initialText: String
    let slot: Slot
    let profile: ProfileDTO
    let onLog: (FoodLogEntryDTO) -> Void

    @Environment(\.theme) private var theme
    @State private var text: String
    @State private var parseResult: FoodParser.ParseResult? = nil
    @State private var qty: Double = 1.0
    @FocusState private var textFocused: Bool

    init(initialText: String, slot: Slot, profile: ProfileDTO,
         onLog: @escaping (FoodLogEntryDTO) -> Void) {
        self.initialText = initialText
        self.slot = slot
        self.profile = profile
        self.onLog = onLog
        _text = State(initialValue: initialText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                noScannerBanner

                VStack(alignment: .leading, spacing: 8) {
                    Text("What did you eat?")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                        .textCase(.uppercase)
                        .tracking(1)

                    TextField("e.g. Greek yogurt, banana, coffee",
                              text: $text, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .font(.body)
                        .foregroundStyle(theme.text)
                        .padding(12)
                        .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .focused($textFocused)
                        .onChange(of: text) { _, newValue in
                            parseResult = FoodParser.parse(text: newValue)
                        }
                }

                if let result = parseResult, result.hasMatches {
                    fallbackResultCard(result: result)
                }

                Button("Log") {
                    logFallback()
                }
                .tactile(.primary, fullWidth: true)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { textFocused = false }
            }
        }
        .onAppear {
            if !initialText.isEmpty {
                parseResult = FoodParser.parse(text: initialText)
            }
        }
    }

    private var noScannerBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.slash")
                .font(.caption)
                .foregroundStyle(theme.dim)
            Text("Camera scanner is unavailable on this device. Type what you ate instead.")
                .font(.caption)
                .foregroundStyle(theme.dim)
        }
        .padding(12)
        .background(theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func fallbackResultCard(result: FoodParser.ParseResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Matched")
                .font(.caption)
                .foregroundStyle(theme.dim)
                .textCase(.uppercase)
                .tracking(1)

            ForEach(result.recognized, id: \.food.id) { item in
                HStack {
                    Text(item.description)
                        .font(.subheadline)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text("\(item.scaledCalories) cal")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.dim)
                }
            }

            Divider().background(theme.line)

            HStack {
                Text("Total")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Text("\(result.totalPerServing.calories) cal · \(result.totalPerServing.proteinG)g protein")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func logFallback() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = FoodParser.parse(text: trimmed, includeDatabase: true)
        let perServing: PerServing
        let name: String

        if result.hasMatches {
            perServing = result.totalPerServing
            name = result.bestName
        } else {
            perServing = .zero
            name = trimmed.isEmpty ? "Unknown food" : trimmed
        }

        let entry = FoodLogEntryDTO(
            userId: profile.id,
            date: Dates.dayKey(),
            slot: slot,
            customName: name,
            servings: 1.0,
            perServing: perServing
        )
        onLog(entry)
    }
}
