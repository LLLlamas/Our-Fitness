// Camera-based food label scanner.
//
// Two capture modes:
//   1. Live scan (DataScannerViewController) — hold phone over the label; auto-detects.
//   2. Photo mode (UIImagePickerController + Vision OCR) — snap or pick a photo; Vision
//      reads the text offline so the user doesn't need to hold steady.
//
// Both paths run the same AI / regex extraction pipeline, then land on a
// fully-editable confirmation screen: name, serving size, servings stepper, and
// every individual nutrient row (calories, fat, sat fat, cholesterol, sodium,
// carbs, fiber, sugars, added sugars, protein). All values are TextFields —
// nothing is locked after scanning.
//
// Safety: FoundationModels reads PRINTED numbers from the label — it does not
// invent macros. The @Generable prompt enforces this constraint.
//
// Graceful degradation:
//   • DataScanner unavailable → skip to fallback text-entry screen
//   • iOS < 26 / no Apple Intelligence → Vision OCR + regex extraction only
//   • Any error → user-facing message, retry available

import SwiftUI
import VisionKit
import Vision
import UIKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - FoodLabelDraft (AI output shape, iOS 26+ only)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct FoodLabelDraft {
    @Guide(description: "Product name from the label. If absent, write 'Unknown food'.")
    var foodName: String
    @Guide(description: "Serving size exactly as printed, e.g. '4 pieces (88g)'.")
    var servingLabel: String
    @Guide(description: "Calories per serving as an integer. 0 if not found.")
    var calories: Int
    @Guide(description: "Protein in grams per serving. 0 if not found.")
    var proteinG: Double
    @Guide(description: "Total carbohydrates in grams per serving. 0 if not found.")
    var carbsG: Double
    @Guide(description: "Total fat in grams per serving. 0 if not found.")
    var fatG: Double
    @Guide(description: "Saturated fat in grams per serving. 0 if not found.")
    var saturatedFatG: Double
    @Guide(description: "Dietary fiber in grams per serving. 0 if not found.")
    var fiberG: Double
    @Guide(description: "Total sugars in grams per serving. 0 if not found.")
    var totalSugarG: Double
    @Guide(description: "Added sugars in grams per serving. 0 if not found.")
    var addedSugarG: Double
    @Guide(description: "Sodium in milligrams per serving. 0 if not found.")
    var sodiumMg: Double
    @Guide(description: "Cholesterol in milligrams per serving. 0 if not found.")
    var cholesterolMg: Double
}
#endif

// MARK: - ConfirmedLabel

private struct ConfirmedLabel {
    var foodName: String
    var servingLabel: String
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var saturatedFatG: Double
    var fiberG: Double
    var totalSugarG: Double
    var addedSugarG: Double
    var sodiumMg: Double
    var cholesterolMg: Double
}

// MARK: - EditableDraft (all nutrient values as strings for inline TextFields)

private struct EditableDraft {
    var name: String
    var serving: String
    var calories: String
    var proteinG: String
    var carbsG: String
    var fatG: String
    var saturatedFatG: String
    var fiberG: String
    var totalSugarG: String
    var addedSugarG: String
    var sodiumMg: String
    var cholesterolMg: String

    init(from label: ConfirmedLabel) {
        name         = label.foodName
        serving      = label.servingLabel
        calories     = label.calories > 0 ? "\(label.calories)" : ""
        proteinG     = Self.fmt(label.proteinG)
        carbsG       = Self.fmt(label.carbsG)
        fatG         = Self.fmt(label.fatG)
        saturatedFatG = Self.fmt(label.saturatedFatG)
        fiberG       = Self.fmt(label.fiberG)
        totalSugarG  = Self.fmt(label.totalSugarG)
        addedSugarG  = Self.fmt(label.addedSugarG)
        sodiumMg     = label.sodiumMg > 0    ? "\(Int(label.sodiumMg))"    : ""
        cholesterolMg = label.cholesterolMg > 0 ? "\(Int(label.cholesterolMg))" : ""
    }

    private static func fmt(_ d: Double) -> String {
        guard d > 0 else { return "" }
        return d.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(d))"
            : String(format: "%.1f", d)
    }

    var caloriesInt: Int    { Int(calories)              ?? 0 }
    var proteinInt:  Int    { Int(Double(proteinG)  ?? 0) }
    var carbsInt:    Int    { Int(Double(carbsG)    ?? 0) }
    var fatInt:      Int    { Int(Double(fatG)      ?? 0) }
    var satFatInt:   Int    { Int(Double(saturatedFatG) ?? 0) }
    var fiberInt:    Int    { Int(Double(fiberG)    ?? 0) }
    var addedSugarInt: Int  { Int(Double(addedSugarG) ?? 0) }
    var sodiumInt:   Int    { Int(sodiumMg)          ?? 0 }

    func toPerServing() -> PerServing {
        PerServing(
            calories:     caloriesInt,
            proteinG:     proteinInt,
            carbsG:       carbsInt,
            fatG:         fatInt,
            fiberG:       fiberInt,
            sodiumMg:     sodiumInt,
            addedSugarG:  addedSugarInt,
            saturatedFatG: satFatInt
        )
    }

    func scaled(by qty: Double) -> PerServing {
        let s = toPerServing()
        return PerServing(
            calories:     Int((Double(s.calories)      * qty).rounded()),
            proteinG:     Int((Double(s.proteinG)      * qty).rounded()),
            carbsG:       Int((Double(s.carbsG)        * qty).rounded()),
            fatG:         Int((Double(s.fatG)          * qty).rounded()),
            fiberG:       Int((Double(s.fiberG)        * qty).rounded()),
            sodiumMg:     Int((Double(s.sodiumMg)      * qty).rounded()),
            addedSugarG:  Int((Double(s.addedSugarG)   * qty).rounded()),
            saturatedFatG: Int((Double(s.saturatedFatG) * qty).rounded())
        )
    }
}

// MARK: - Phase

private enum ScannerPhase {
    case scanning
    case capturingPhoto(source: UIImagePickerController.SourceType)
    case processing
    case confirming(ConfirmedLabel, quantity: Double)
    case fallback(text: String)
    case error(String)
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
    @State private var stableTimer: Timer? = nil
    @State private var lastSeenText: String = ""
    @State private var isStable: Bool = false

    private var scannerAvailable: Bool {
        if #available(iOS 17.0, *) {
            return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        }
        return false
    }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

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
                    Button("Cancel") { dismiss() }.tactile(.ghost)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .onAppear {
            if !scannerAvailable { phase = .fallback(text: "") }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scanning:
            scanningView
        case .capturingPhoto(let source):
            ImagePickerView(
                sourceType: source,
                onCapture: { image in
                    phase = .processing
                    Task { await processImage(image) }
                },
                onCancel: { phase = .scanning }
            )
            .ignoresSafeArea()
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
                    onTextStable: { text in handleCapturedText(text) }
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                Color.black.ignoresSafeArea()
            }
            VStack {
                Spacer()
                scanningOverlay.padding(.bottom, 40)
            }
        }
        .onChange(of: capturedText) { _, newText in throttleStabilization(newText) }
    }

    private var scanningOverlay: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                .frame(width: 280, height: 160)
                .overlay {
                    VStack(spacing: 6) {
                        Text("Point at Nutrition Facts")
                            .font(.caption).foregroundStyle(Color.white.opacity(0.85))
                        if !capturedText.isEmpty {
                            Text(isStable ? "Label detected" : "Reading…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .animation(.easeInOut(duration: 0.2), value: isStable)
                        }
                    }
                }

            if !capturedText.isEmpty {
                Button("Use this ›") { handleCapturedText(capturedText) }
                    .tactile(.primary)
            }

            HStack(spacing: 10) {
                if cameraAvailable {
                    Button {
                        phase = .capturingPhoto(source: .camera)
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .tactile(.secondary)
                }
                Button {
                    phase = .capturingPhoto(source: .photoLibrary)
                } label: {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.system(size: 13, weight: .medium))
                }
                .tactile(.secondary)
            }

            Button("Type it instead") { phase = .fallback(text: "") }
                .tactile(.ghost)
        }
        .padding(.horizontal, 24)
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
                .font(.system(size: 17, weight: .medium)).foregroundStyle(theme.text)
            Text("Extracting nutrition from the printed label.")
                .font(.caption).foregroundStyle(theme.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Subview routing

    private func confirmingView(label: ConfirmedLabel, quantity: Double) -> some View {
        ConfirmationView(
            label: label, quantity: quantity, slot: slot, profile: profile,
            onLog: { entry in onLog(entry); dismiss() },
            onRescan: {
                capturedText = ""; lastSeenText = ""; isStable = false
                phase = .scanning
            }
        )
    }

    private func fallbackView(initialText: String) -> some View {
        FallbackEntryView(
            initialText: initialText, slot: slot, profile: profile,
            onLog: { entry in onLog(entry); dismiss() }
        )
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44)).foregroundStyle(theme.warn)
            Text("Could not read label")
                .font(.headline).foregroundStyle(theme.text)
            Text(message)
                .font(.subheadline).foregroundStyle(theme.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("Try again") {
                    capturedText = ""; lastSeenText = ""; isStable = false
                    phase = .scanning
                }
                .tactile(.secondary)
                Button("Type instead") { phase = .fallback(text: "") }
                    .tactile(.primary)
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Photo → Vision OCR

    private func processImage(_ image: UIImage) async {
        let text = await recognizeText(in: image)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await MainActor.run { phase = .fallback(text: "") }
        } else {
            handleCapturedText(trimmed)
        }
    }

    private func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            let observations = request.results ?? []
            // VN uses flipped Y: higher minY = higher on screen → sort descending for reading order.
            let sorted = observations.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            return sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    // MARK: - Text stabilization (live scanner debounce)

    private func throttleStabilization(_ text: String) {
        stableTimer?.invalidate()
        guard text != lastSeenText else { return }
        lastSeenText = text
        isStable = false
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stableTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            Task { @MainActor in
                guard case .scanning = phase else { return }
                isStable = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    handleCapturedText(text)
                }
            }
        }
    }

    // MARK: - Text → parse → confirm

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
                case .failure:
                    if let parsed = fallbackParse(trimmed) {
                        phase = .confirming(parsed, quantity: 1.0)
                    } else {
                        phase = .fallback(text: trimmed)
                    }
                }
            }
        }
    }

    private func extractLabel(from text: String) async -> Result<ConfirmedLabel, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if SystemLanguageModel.default.availability == .available {
                return await extractLabelWithAI(text)
            }
        }
        #endif
        if let parsed = fallbackParse(text) { return .success(parsed) }
        return .failure(NSError(domain: "CameraFoodLog", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Could not extract nutrition from this label."]))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func extractLabelWithAI(_ text: String) async -> Result<ConfirmedLabel, Error> {
        let instructions = """
        You are reading text scanned from a physical Nutrition Facts label. Extract exactly \
        what is PRINTED on the label. Use 0 for any value that is absent or illegible. \
        Do NOT estimate or invent any number. The product name is often NOT on the Nutrition \
        Facts panel itself — if absent, use "Unknown food".
        """
        do {
            let session = LanguageModelSession { instructions }
            let response = try await session.respond(
                to: "Label text:\n\"\"\"\n\(text)\n\"\"\"",
                generating: FoodLabelDraft.self
            )
            let d = response.content
            return .success(ConfirmedLabel(
                foodName:      d.foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                servingLabel:  d.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                calories:      max(0, d.calories),
                proteinG:      max(0, d.proteinG),
                carbsG:        max(0, d.carbsG),
                fatG:          max(0, d.fatG),
                saturatedFatG: max(0, d.saturatedFatG),
                fiberG:        max(0, d.fiberG),
                totalSugarG:   max(0, d.totalSugarG),
                addedSugarG:   max(0, d.addedSugarG),
                sodiumMg:      max(0, d.sodiumMg),
                cholesterolMg: max(0, d.cholesterolMg)
            ))
        } catch {
            return .failure(error)
        }
    }
    #endif

    /// Heuristic numeric extraction for non-AI devices.
    private func fallbackParse(_ text: String) -> ConfirmedLabel? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        func firstNum(after keyword: String) -> Double? {
            for line in lines {
                guard line.lowercased().contains(keyword) else { continue }
                let nums = line.components(separatedBy: .whitespaces).compactMap { tok -> Double? in
                    var s = tok
                    for sfx in ["g", "mg", "mcg", "kcal", "%", "<"] { s = s.replacingOccurrences(of: sfx, with: "") }
                    return Double(s)
                }
                if let n = nums.first { return n }
            }
            return nil
        }

        let calories = firstNum(after: "calorie").map { Int($0) } ?? 0
        guard calories > 0 else { return nil }

        let serving = lines.first { $0.lowercased().contains("serving size") } ?? "1 serving"
        let name = lines.first { line in
            !line.isEmpty &&
            !line.lowercased().contains("nutrition") &&
            !line.lowercased().contains("calorie") &&
            !line.lowercased().contains("serving") &&
            Double(line) == nil
        } ?? "Scanned food"

        return ConfirmedLabel(
            foodName:      name,
            servingLabel:  serving,
            calories:      calories,
            proteinG:      firstNum(after: "protein")          ?? 0,
            carbsG:        firstNum(after: "total carb")       ?? firstNum(after: "carbohydrate") ?? 0,
            fatG:          firstNum(after: "total fat")        ?? firstNum(after: " fat") ?? 0,
            saturatedFatG: firstNum(after: "saturated fat")    ?? 0,
            fiberG:        firstNum(after: "dietary fiber")    ?? firstNum(after: "fiber") ?? 0,
            totalSugarG:   firstNum(after: "total sugar")      ?? firstNum(after: "sugars") ?? 0,
            addedSugarG:   firstNum(after: "added sugar")      ?? 0,
            sodiumMg:      firstNum(after: "sodium")           ?? 0,
            cholesterolMg: firstNum(after: "cholesterol")      ?? 0
        )
    }
}

// MARK: - ImagePickerView

private struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void
        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onCapture(img) } else { onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}

// MARK: - DataScannerView (iOS 17+)

@available(iOS 17.0, *)
private struct DataScannerView: UIViewControllerRepresentable {
    @Binding var capturedText: String
    var onTextStable: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(capturedText: $capturedText, onTextStable: onTextStable) }

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

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var capturedText: String
        var onTextStable: (String) -> Void

        init(capturedText: Binding<String>, onTextStable: @escaping (String) -> Void) {
            self._capturedText = capturedText
            self.onTextStable = onTextStable
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { update(allItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) { update(allItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) { update(allItems) }

        private func update(_ items: [RecognizedItem]) {
            let lines = items.compactMap { item -> String? in
                guard case .text(let t) = item else { return nil }
                let s = t.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }
            let combined = lines.joined(separator: "\n")
            DispatchQueue.main.async { self.capturedText = combined }
        }
    }
}

// MARK: - ConfirmationView

private struct ConfirmationView: View {
    let label: ConfirmedLabel
    let quantity: Double
    let slot: Slot
    let profile: ProfileDTO
    let onLog: (FoodLogEntryDTO) -> Void
    let onRescan: () -> Void

    @Environment(\.theme) private var theme
    @State private var qty: Double
    @State private var draft: EditableDraft
    @FocusState private var focused: String?

    init(label: ConfirmedLabel, quantity: Double, slot: Slot,
         profile: ProfileDTO,
         onLog: @escaping (FoodLogEntryDTO) -> Void,
         onRescan: @escaping () -> Void) {
        self.label = label; self.quantity = quantity
        self.slot = slot; self.profile = profile
        self.onLog = onLog; self.onRescan = onRescan
        _qty   = State(initialValue: quantity)
        _draft = State(initialValue: EditableDraft(from: label))
    }

    private var scaledKcal: Int { Int((Double(draft.caloriesInt) * qty).rounded()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                banner
                nameServingCard
                servingsCard
                nutritionFactsEditor
                Button("Log this") { onLog(buildEntry()) }
                    .tactile(.primary, fullWidth: true)
                Button("Scan again") { onRescan() }
                    .tactile(.ghost, fullWidth: true)
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }

    // MARK: Subviews

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.caption).foregroundStyle(theme.accent)
            Text("Numbers read from the printed label. Tap any value to correct it.")
                .font(.caption).foregroundStyle(theme.dim)
        }
        .padding(12)
        .background(theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var nameServingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Name")
            TextField("Product name", text: $draft.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(12)
                .background(theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($focused, equals: "name")
            sectionLabel("Serving size")
            TextField("e.g. 4 pieces (88g)", text: $draft.serving)
                .font(.subheadline).foregroundStyle(theme.text)
                .padding(12)
                .background(theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($focused, equals: "serving")
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var servingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Servings")
            HStack(spacing: 16) {
                Button { if qty > 0.5 { qty -= 0.5 } } label: {
                    Image(systemName: "minus").frame(width: 36, height: 36)
                }
                .tactile(.secondary).disabled(qty <= 0.5)

                Text(qty.truncatingRemainder(dividingBy: 1) == 0
                     ? "\(Int(qty))" : String(format: "%.1f", qty))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
                    .frame(minWidth: 48).multilineTextAlignment(.center)

                Button { if qty < 10.0 { qty += 0.5 } } label: {
                    Image(systemName: "plus").frame(width: 36, height: 36)
                }
                .tactile(.secondary).disabled(qty >= 10.0)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(scaledKcal) cal")
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .contentTransition(.numericText())
                    if qty != 1 {
                        Text("(\(draft.caloriesInt) per serving)")
                            .font(.system(size: 11)).foregroundStyle(theme.dim)
                    }
                }
            }
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var nutritionFactsEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition Facts")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 2)
            Text("Per serving · tap any value to edit")
                .font(.system(size: 10)).tracking(1)
                .foregroundStyle(theme.dim)
                .padding(.horizontal, 16).padding(.bottom, 10)

            Divider().background(theme.line).padding(.horizontal, 16)

            // Calories row — prominent
            HStack {
                Text("Calories")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                Spacer()
                TextField("0", text: $draft.calories)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    .focused($focused, equals: "calories")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().background(theme.line).padding(.horizontal, 16)

            Group {
                nutrientRow("Total Fat",          $draft.fatG,          unit: "g",  indent: 0, field: "fat")
                nutrientRow("Saturated Fat",      $draft.saturatedFatG, unit: "g",  indent: 1, field: "satfat")
                nutrientRow("Cholesterol",        $draft.cholesterolMg, unit: "mg", indent: 0, field: "chol")
                nutrientRow("Sodium",             $draft.sodiumMg,      unit: "mg", indent: 0, field: "sodium")
                nutrientRow("Total Carbohydrate", $draft.carbsG,        unit: "g",  indent: 0, field: "carbs")
                nutrientRow("Dietary Fiber",      $draft.fiberG,        unit: "g",  indent: 1, field: "fiber")
                nutrientRow("Total Sugars",       $draft.totalSugarG,   unit: "g",  indent: 1, field: "sugar")
                nutrientRow("Added Sugars",       $draft.addedSugarG,   unit: "g",  indent: 2, field: "addedsug")
                nutrientRow("Protein",            $draft.proteinG,      unit: "g",  indent: 0, field: "protein")
            }

            // Cholesterol note — not stored in PerServing
            Text("† Cholesterol is shown for reference; not stored in the nutrition log.")
                .font(.system(size: 9)).foregroundStyle(theme.dim)
                .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10)).tracking(1.5).foregroundStyle(theme.dim)
    }

    @ViewBuilder
    private func nutrientRow(_ name: String, _ binding: Binding<String>,
                             unit: String, indent: Int, field: String) -> some View {
        HStack(alignment: .center) {
            if indent > 0 { Color.clear.frame(width: CGFloat(indent) * 16, height: 1) }
            Text(name)
                .font(indent == 0
                      ? .system(size: 14, weight: .medium)
                      : .system(size: 13))
                .foregroundStyle(indent == 0 ? theme.text : theme.dim)
            Spacer()
            HStack(spacing: 3) {
                TextField("0", text: binding)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 52)
                    .focused($focused, equals: field)
                Text(unit)
                    .font(.system(size: 12)).foregroundStyle(theme.dim)
                    .frame(width: 24, alignment: .leading)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        Divider().background(theme.line).padding(.horizontal, 16)
    }

    // MARK: Build entry

    private func buildEntry() -> FoodLogEntryDTO {
        FoodLogEntryDTO(
            userId: profile.id,
            date: Dates.dayKey(),
            slot: slot,
            customName: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Scanned food"
                : draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            servings: qty,
            perServing: draft.toPerServing()
        )
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
        self.slot = slot; self.profile = profile; self.onLog = onLog
        _text = State(initialValue: initialText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.slash").font(.caption).foregroundStyle(theme.dim)
                    Text("Camera scanner unavailable. Type what you ate instead.")
                        .font(.caption).foregroundStyle(theme.dim)
                }
                .padding(12)
                .background(theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("What did you eat?")
                        .font(.system(size: 10)).tracking(1.5).foregroundStyle(theme.dim)
                    TextField("e.g. Greek yogurt, banana, coffee",
                              text: $text, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .font(.body).foregroundStyle(theme.text)
                        .padding(12)
                        .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .focused($textFocused)
                        .onChange(of: text) { _, v in parseResult = FoodParser.parse(text: v) }
                }

                if let result = parseResult, result.hasMatches {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Matched")
                            .font(.system(size: 10)).tracking(1.5).foregroundStyle(theme.dim)
                        ForEach(result.recognized, id: \.food.id) { item in
                            HStack {
                                Text(item.description).font(.subheadline).foregroundStyle(theme.text)
                                Spacer()
                                Text("\(item.scaledCalories) cal")
                                    .font(.caption.monospacedDigit()).foregroundStyle(theme.dim)
                            }
                        }
                        Divider().background(theme.line)
                        HStack {
                            Text("Total").font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                            Spacer()
                            Text("\(result.totalPerServing.calories) cal · \(result.totalPerServing.proteinG)g protein")
                                .font(.caption.monospacedDigit()).foregroundStyle(theme.accent)
                        }
                    }
                    .padding(16)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button("Log") { logFallback() }
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
            if !initialText.isEmpty { parseResult = FoodParser.parse(text: initialText) }
        }
    }

    private func logFallback() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = FoodParser.parse(text: trimmed, includeDatabase: true)
        let entry = FoodLogEntryDTO(
            userId: profile.id,
            date: Dates.dayKey(),
            slot: slot,
            customName: result.hasMatches ? result.bestName : (trimmed.isEmpty ? "Unknown food" : trimmed),
            servings: 1.0,
            perServing: result.hasMatches ? result.totalPerServing : .zero
        )
        onLog(entry)
    }
}
