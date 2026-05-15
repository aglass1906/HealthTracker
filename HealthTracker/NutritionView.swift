//
//  NutritionView.swift
//  HealthTracker
//

import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import Supabase
#if canImport(VisionKit)
import Vision
import VisionKit
#endif

// MARK: - Image resize

extension UIImage {
    /// Max JPEG size before base64 upload (keep under typical Edge/gateway limits).
    static let ht_maxFoodLookupJPEGBytes = 2_400_000

    func ht_resized(maxDimension: CGFloat) -> UIImage {
        let w = size.width
        let h = size.height
        let scale = min(maxDimension / max(w, h), 1)
        guard scale < 1 else { return self }
        let nw = w * scale
        let nh = h * scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: nw, height: nh))
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: CGSize(width: nw, height: nh)))
        }
    }

    /// Resizes and recompresses until JPEG is under `maxBytes` (for `food-lookup` JSON body).
    func ht_jpegForFoodLookup(maxBytes: Int = UIImage.ht_maxFoodLookupJPEGBytes) -> Data? {
        var dim: CGFloat = 960
        var image = ht_resized(maxDimension: dim)
        var quality: CGFloat = 0.72
        for _ in 0 ..< 12 {
            guard let data = image.jpegData(compressionQuality: quality) else { return nil }
            if data.count <= maxBytes { return data }
            quality -= 0.08
            if quality < 0.28 {
                quality = 0.65
                dim *= 0.88
                image = ht_resized(maxDimension: max(dim, 320))
            }
        }
        return image.jpegData(compressionQuality: 0.22)
    }
}

// MARK: - Barcode scanner

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}

    final class Coordinator: NSObject, BarcodeScannerDelegate {
        let onCode: (String) -> Void
        let onCancel: () -> Void

        init(onCode: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onCode = onCode
            self.onCancel = onCancel
        }

        func didScan(code: String) {
            onCode(code)
        }

        func didCancel() {
            onCancel()
        }
    }
}

protocol BarcodeScannerDelegate: AnyObject {
    func didScan(code: String)
    func didCancel()
}

final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: BarcodeScannerDelegate?
    private var session: AVCaptureSession?
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var videoDevice: AVCaptureDevice?
    private var didEmitCode = false
    private let torchButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    private func setupCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async {
                    if ok { self?.startSession() } else { self?.delegate?.didCancel() }
                }
            }
        default:
            delegate?.didCancel()
        }

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.tintColor = .white
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        torchButton.setTitle("Light", for: .normal)
        torchButton.tintColor = .white
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        torchButton.isHidden = true
        view.addSubview(torchButton)
        NSLayoutConstraint.activate([
            torchButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            torchButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
        ])
    }

    @objc private func cancelTapped() {
        delegate?.didCancel()
    }

    @objc private func torchTapped() {
        guard let d = videoDevice, d.hasTorch else { return }
        do {
            try d.lockForConfiguration()
            d.torchMode = d.torchMode == .on ? .off : .on
            d.unlockForConfiguration()
            torchButton.setTitle(d.torchMode == .on ? "Light on" : "Light", for: .normal)
        } catch {}
    }

    private func startSession() {
        let session = AVCaptureSession()
        self.session = session
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        videoDevice = device
        torchButton.isHidden = !device.hasTorch

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128, .code39]

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmitCode,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let s = obj.stringValue else { return }
        didEmitCode = true
        session?.stopRunning()
        if let d = videoDevice, d.hasTorch, d.isTorchActive {
            try? d.lockForConfiguration()
            d.torchMode = .off
            d.unlockForConfiguration()
        }
        delegate?.didScan(code: s)
    }
}

// MARK: - Barcode: VisionKit DataScanner when supported, else AVFoundation

struct BarcodeScanningContainer: View {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        #if canImport(VisionKit)
        if #available(iOS 16.0, *), DataScannerViewController.isSupported {
            DataBarcodeScannerView(onCode: onCode, onCancel: onCancel)
                .ignoresSafeArea()
        } else {
            BarcodeScannerView(onCode: onCode, onCancel: onCancel)
                .ignoresSafeArea()
        }
        #else
        BarcodeScannerView(onCode: onCode, onCancel: onCancel)
            .ignoresSafeArea()
        #endif
    }
}

#if canImport(VisionKit)
@available(iOS 16.0, *)
struct DataBarcodeScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39])]
        let vc = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        context.coordinator.scanner = vc
        DispatchQueue.main.async {
            try? vc.startScanning()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let onCancel: () -> Void
        private var didEmit = false
        weak var scanner: DataScannerViewController?

        init(onCode: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onCode = onCode
            self.onCancel = onCancel
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            emit(from: item)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems { emit(from: item) }
        }

        private func emit(from item: RecognizedItem) {
            guard !didEmit else { return }
            guard case .barcode(let b) = item else { return }
            let raw = b.payloadStringValue ?? ""
            let digits = raw.filter(\.isNumber)
            guard digits.count >= 8 else { return }
            didEmit = true
            scanner?.stopScanning()
            onCode(raw)
        }
    }
}
#endif

// MARK: - Edit one line item (from meal list)

private struct LineItemEditTarget: Identifiable, Hashable {
    let log: NutritionLogRow
    let item: NutritionLogItemRow
    var id: UUID { item.id }
}

// MARK: - Main view

struct NutritionView: View {
    @StateObject private var nutritionManager = NutritionManager.shared
    @AppStorage("syncNutritionToHealthKit") private var syncNutritionToHealthKit = true
    @State private var selectedDate = Date()
    @State private var showingLogSheet = false
    @State private var showingManageFavorites = false
    @State private var showingGoalSettings = false
    @State private var editingLog: NutritionLogRow?
    @State private var editingLineItem: LineItemEditTarget?

    private var selectedDayStart: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }

    private var selectedDayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: selectedDayStart) ?? selectedDayStart
    }

    private var selectableDateRange: ClosedRange<Date> {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let start = cal.date(byAdding: .year, value: -5, to: end) ?? end
        return start ... end
    }

    private var daySummaryTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let t = nutritionManager.loadedDayTotals
                    let pct = nutritionManager.macroPercentOfCalories(
                        calories: t.calories,
                        protein: t.protein,
                        carbs: t.carbs,
                        fat: t.fat
                    )
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(daySummaryTitle)
                                .font(.headline)
                            Spacer(minLength: 8)
                            DatePicker(
                                "Day",
                                selection: $selectedDate,
                                in: selectableDateRange,
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .id(selectedDate)
                            .accessibilityLabel("Day for meal list")
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                macroChip("Cal", value: Int(t.calories.rounded()), unit: "kcal")
                                macroChip("P", value: Int(t.protein.rounded()), unit: "g")
                                macroChip("C", value: Int(t.carbs.rounded()), unit: "g")
                                macroChip("F", value: Int(t.fat.rounded()), unit: "g")
                                macroChip("Sugar", value: Int(t.sugar.rounded()), unit: "g")
                                macroChip("Sodium", value: Int(t.sodium.rounded()), unit: "mg")
                            }
                        }
                        if let pp = pct.protein, let pc = pct.carbs, let pf = pct.fat {
                            Text(String(format: "Macro %% of kcal · P %.0f%% · C %.0f%% · F %.0f%%", pp, pc, pf))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Macro % of kcal · —")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Daily Goal") {
                    Button {
                        showingGoalSettings = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "target")
                                .font(.title3)
                                .foregroundStyle(.green)
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 3) {
                                if let goal = nutritionManager.activeGoal {
                                    Text(goal.goal_type.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(Int(goal.daily_calories.rounded())) kcal · P \(Int(goal.protein_g.rounded()))g · C \(Int(goal.carb_g.rounded()))g · F \(Int(goal.fat_g.rounded()))g")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Target · P \(macroTargetPercent(goal.protein_g, caloriesPerGram: 4, dailyCalories: goal.daily_calories)) · C \(macroTargetPercent(goal.carb_g, caloriesPerGram: 4, dailyCalories: goal.daily_calories)) · F \(macroTargetPercent(goal.fat_g, caloriesPerGram: 9, dailyCalories: goal.daily_calories))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("Sugar \(Int(goal.sugar_g.rounded()))g · Sodium \(Int(goal.sodium_mg.rounded()))mg")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Text("Set a nutrition goal")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Choose a preset or enter custom daily targets.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }

                Section("Goal Progress") {
                    if let goal = nutritionManager.activeGoal {
                        let totals = nutritionManager.loadedDayNutritionTotals
                        let progressItems = nutritionManager.progress(for: totals, goal: goal)

                        if nutritionManager.logs.isEmpty {
                            Text("No meals logged for this day yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(progressItems) { item in
                            NutritionProgressRow(item: item)
                        }
                    } else {
                        Button {
                            showingGoalSettings = true
                        } label: {
                            Label("Set a goal to track daily progress", systemImage: "target")
                        }
                    }
                }

                Section("Meals") {
                    if nutritionManager.logs.isEmpty {
                        Text("No meals logged for this day.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(nutritionManager.logs) { log in
                            NutritionLogRowView(
                                log: log,
                                onEditMeal: { editingLog = log },
                                onEditItem: { item in
                                    editingLineItem = LineItemEditTarget(log: log, item: item)
                                }
                            )
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                let id = nutritionManager.logs[i].id
                                Task { await nutritionManager.deleteLog(id: id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        Button {
                            showingManageFavorites = true
                        } label: {
                            Label("Favorites", systemImage: "star.circle")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline)
                        }
                        Button {
                            showingGoalSettings = true
                        } label: {
                            Image(systemName: "target")
                        }
                        .accessibilityLabel("Nutrition goal")
                        Button {
                            showingLogSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Log food")
                    }
                }
            }
            .sheet(isPresented: $showingManageFavorites) {
                ManageNutritionFavoritesSheet()
            }
            .sheet(isPresented: $showingGoalSettings) {
                NutritionGoalSettingsSheet(currentGoal: nutritionManager.activeGoal)
            }
            .sheet(isPresented: $showingLogSheet) {
                LogFoodSheet(syncToHealthKit: syncNutritionToHealthKit, initialDate: selectedDate)
            }
            .onChange(of: showingLogSheet) { _, isOpen in
                if !isOpen {
                    Task {
                        await nutritionManager.loadLogs(from: selectedDayStart, to: selectedDayEnd)
                    }
                }
            }
            .sheet(item: $editingLog) { log in
                EditNutritionLogSheet(log: log)
            }
            .sheet(item: $editingLineItem) { target in
                EditNutritionLineItemSheet(log: target.log, item: target.item)
            }
            .task(id: selectedDayStart) {
                await nutritionManager.loadActiveGoal()
                await nutritionManager.loadLogs(from: selectedDayStart, to: selectedDayEnd)
            }
            .refreshable {
                await nutritionManager.loadActiveGoal()
                await nutritionManager.loadLogs(from: selectedDayStart, to: selectedDayEnd)
            }
        }
    }

    private func macroChip(_ title: String, value: Int, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 52)
    }

    private func percentUsed(_ current: Double, _ target: Double) -> String {
        guard target > 0 else { return "--" }
        return "\(Int((100 * current / target).rounded()))%"
    }

    private func macroTargetPercent(_ grams: Double, caloriesPerGram: Double, dailyCalories: Double) -> String {
        guard dailyCalories > 0 else { return "--" }
        let percent = max(grams, 0) * caloriesPerGram / dailyCalories * 100
        return "\(Int(percent.rounded()))%"
    }
}

private struct NutritionProgressRow: View {
    let item: NutritionProgressItem

    private var tint: Color {
        if item.isOverTarget { return .red }
        if item.kind.isLimitOriented && item.progress >= 0.85 { return .orange }

        switch item.kind {
        case .calories: return .orange
        case .protein: return .blue
        case .carbs: return .green
        case .fat: return .purple
        case .sugar: return .pink
        case .sodium: return .teal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.kind.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(item.target > 0 ? valueText : "\(formatted(item.current)) \(item.unit)")
                    .font(.caption)
                    .foregroundStyle(item.isOverTarget ? .red : .secondary)
            }

            if item.target > 0 {
                ProgressView(value: item.clampedProgress)
                    .tint(tint)
            } else {
                Text("No target set")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if item.isOverTarget {
                Text("Over by \(formatted(item.current - item.target)) \(item.unit)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
    }

    private var valueText: String {
        let current = formatted(item.current)
        let target = formatted(item.target)
        return "\(current) / \(target) \(item.unit)"
    }

    private func formatted(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if abs(value.rounded() - value) < 0.05 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

private struct NutritionGoalSettingsSheet: View {
    let currentGoal: NutritionGoal?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @State private var goalType: NutritionGoalType
    @State private var dailyCalories: Double
    @State private var proteinG: Double
    @State private var carbG: Double
    @State private var fatG: Double
    @State private var sugarG: Double
    @State private var sodiumMg: Double
    @State private var fiberG: Double
    @State private var isSaving = false

    init(currentGoal: NutritionGoal?) {
        self.currentGoal = currentGoal
        let fallback = NutritionGoalPreset.values(for: .balanced)
        _goalType = State(initialValue: currentGoal?.goal_type ?? .balanced)
        _dailyCalories = State(initialValue: currentGoal?.daily_calories ?? fallback.dailyCalories)
        _proteinG = State(initialValue: currentGoal?.protein_g ?? fallback.proteinG)
        _carbG = State(initialValue: currentGoal?.carb_g ?? fallback.carbG)
        _fatG = State(initialValue: currentGoal?.fat_g ?? fallback.fatG)
        _sugarG = State(initialValue: currentGoal?.sugar_g ?? fallback.sugarG)
        _sodiumMg = State(initialValue: currentGoal?.sodium_mg ?? fallback.sodiumMg)
        _fiberG = State(initialValue: currentGoal?.fiber_g ?? fallback.fiberG ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    Picker("Goal", selection: $goalType) {
                        ForEach(NutritionGoalType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: goalType) { _, newValue in
                        applyPreset(newValue)
                    }
                }

                Section("Daily targets") {
                    numericTargetRow("Calories", value: $dailyCalories, unit: "kcal")
                    numericTargetRow("Protein", value: $proteinG, unit: "g", caloriesPerUnit: 4)
                    numericTargetRow("Carbs", value: $carbG, unit: "g", caloriesPerUnit: 4)
                    numericTargetRow("Fat", value: $fatG, unit: "g", caloriesPerUnit: 9)
                    numericTargetRow("Sugar", value: $sugarG, unit: "g", caloriesPerUnit: 4)
                    numericTargetRow("Sodium", value: $sodiumMg, unit: "mg")
                    numericTargetRow("Fiber", value: $fiberG, unit: "g", caloriesPerUnit: 2)
                }

                Section {
                    LabeledContent("Salt equivalent", value: String(format: "%.1f g", sodiumMg * 2.5 / 1000))
                    Text("Sodium is stored in milligrams. Salt equivalent is shown for reference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let message = nutritionManager.errorMessage, !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nutrition Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || AuthManager.shared.session == nil)
                }
            }
        }
    }

    private func numericTargetRow(
        _ title: String,
        value: Binding<Double>,
        unit: String,
        caloriesPerUnit: Double? = nil
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0 ... 1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            if let caloriesPerUnit {
                Text(percentOfCalories(value.wrappedValue, caloriesPerUnit: caloriesPerUnit))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            } else {
                Spacer()
                    .frame(width: 48)
            }
        }
    }

    private func percentOfCalories(_ value: Double, caloriesPerUnit: Double) -> String {
        guard dailyCalories > 0 else { return "0%" }
        let percent = (max(value, 0) * caloriesPerUnit / dailyCalories) * 100
        return "\(Int(percent.rounded()))%"
    }

    private func applyPreset(_ type: NutritionGoalType) {
        let values = NutritionGoalPreset.values(for: type)
        dailyCalories = values.dailyCalories
        proteinG = values.proteinG
        carbG = values.carbG
        fatG = values.fatG
        sugarG = values.sugarG
        sodiumMg = values.sodiumMg
        fiberG = values.fiberG ?? 0
    }

    private func save() async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        isSaving = true
        defer { isSaving = false }

        let goal = NutritionGoal(
            id: currentGoal?.id ?? UUID(),
            user_id: userId,
            goal_type: goalType,
            daily_calories: max(dailyCalories, 0),
            protein_g: max(proteinG, 0),
            carb_g: max(carbG, 0),
            fat_g: max(fatG, 0),
            sugar_g: max(sugarG, 0),
            sodium_mg: max(sodiumMg, 0),
            fiber_g: fiberG > 0 ? fiberG : nil,
            is_active: true
        )

        if await nutritionManager.saveGoal(goal) {
            dismiss()
        }
    }
}

struct NutritionLogRowView: View {
    let log: NutritionLogRow
    var onEditMeal: () -> Void
    var onEditItem: (NutritionLogItemRow) -> Void

    @State private var thumbURL: URL?

    private var isMultiItem: Bool {
        (log.nutrition_log_items?.count ?? 0) > 1
    }

    private var photoPath: String? {
        guard let path = log.photo_path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return path
    }

    private var productImageURL: URL? {
        log.nutrition_log_items?
            .compactMap(\.image_url)
            .compactMap { URL(string: $0) }
            .first
    }

    var body: some View {
        let content = HStack(alignment: .top, spacing: 12) {
            mealThumb
            VStack(alignment: .leading, spacing: 6) {
                if isMultiItem {
                    Button(action: onEditMeal) {
                        HStack {
                            Text(log.logged_at.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let mt = log.meal_type, !mt.isEmpty {
                                Text(mt)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.14))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Label("Meal", systemImage: "pencil.circle")
                                .font(.caption)
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Text(log.logged_at.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let mt = log.meal_type, !mt.isEmpty {
                            Text(mt)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.14))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Image(systemName: sourceIcon)
                            .foregroundStyle(.secondary)
                    }
                }
                if let n = log.notes, !n.isEmpty {
                    Text(n)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let items = log.nutrition_log_items {
                    let groups = groupedLogItems(items)
                    ForEach(groups, id: \.key) { group in
                        if let comboName = group.key {
                            ComboGroupRow(
                                name: comboName,
                                items: group.items,
                                isMultiItem: isMultiItem,
                                onEditItem: onEditItem,
                                formatQty: formatQty
                            )
                        } else {
                            ForEach(group.items) { item in
                                logItemRow(item)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)

        Group {
            if isMultiItem {
                content
            } else {
                Button(action: onEditMeal) {
                    content
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: log.photo_path) {
            guard let path = photoPath else {
                thumbURL = nil
                return
            }
            thumbURL = await NutritionManager.shared.mealPhotoSignedURL(path: path)
        }
    }

    private var mealThumb: some View {
        Group {
            if let url = thumbURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure, .empty:
                        thumbPlaceholder
                    @unknown default:
                        thumbPlaceholder
                    }
                }
            } else if photoPath != nil {
                thumbPlaceholder
            } else if let url = productImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure, .empty:
                        thumbPlaceholder
                    @unknown default:
                        thumbPlaceholder
                    }
                }
            } else {
                Color.clear.frame(width: 52, height: 52)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var thumbPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
    }

    private func formatQty(_ q: Double) -> String {
        q.rounded(.toNearestOrAwayFromZero) == q ? String(format: "%.0f", q) : String(format: "%.1f", q)
    }

    private func logItemRow(_ item: NutritionLogItemRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.name)
                        .font(.body)
                    if let b = item.brand, !b.isEmpty {
                        Text("· \(b)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let q = item.quantity, q > 0, abs(q - 1) > 0.001 {
                        Text("×\(formatQty(q))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text("P \(Int(item.protein_g))g · C \(Int(item.carb_g))g · F \(Int(item.fat_g))g")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Text("\(Int(item.calories.rounded())) kcal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isMultiItem {
                Button {
                    onEditItem(item)
                } label: {
                    Image(systemName: "pencil.line")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit \(item.name)")
            }
        }
    }

    private func groupedLogItems(_ items: [NutritionLogItemRow]) -> [(key: String?, items: [NutritionLogItemRow])] {
        var result: [(key: String?, items: [NutritionLogItemRow])] = []
        var nameToIndex: [String: Int] = [:]
        for item in items {
            if let name = item.combo_name, !name.isEmpty {
                if let idx = nameToIndex[name] {
                    result[idx].items.append(item)
                } else {
                    nameToIndex[name] = result.count
                    result.append((key: name, items: [item]))
                }
            } else {
                result.append((key: nil, items: [item]))
            }
        }
        return result
    }

    private var sourceIcon: String {
        switch log.source {
        case "barcode": return "barcode.viewfinder"
        case "photo": return "camera.fill"
        default: return "magnifyingglass"
        }
    }
}

// MARK: - Combo history group row

private struct ComboGroupRow: View {
    let name: String
    let items: [NutritionLogItemRow]
    let isMultiItem: Bool
    let onEditItem: (NutritionLogItemRow) -> Void
    let formatQty: (Double) -> String

    @State private var expanded = false

    private var totalKcal: Double { items.reduce(0) { $0 + $1.calories } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "fork.knife.circle.fill")
                        .foregroundStyle(Color.orange)
                        .font(.caption)
                    Text(name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Text("\(Int(totalKcal.rounded())) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(items) { item in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.name)
                                    .font(.body)
                                if let b = item.brand, !b.isEmpty {
                                    Text("· \(b)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let q = item.quantity, q > 0, abs(q - 1) > 0.001 {
                                    Text("×\(formatQty(q))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Text("P \(Int(item.protein_g))g · C \(Int(item.carb_g))g · F \(Int(item.fat_g))g")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 4)
                        Text("\(Int(item.calories.rounded())) kcal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if isMultiItem {
                            Button {
                                onEditItem(item)
                            } label: {
                                Image(systemName: "pencil.line")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 36, minHeight: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(item.name)")
                        }
                    }
                    .padding(.leading, 18)
                }
            }
        }
    }
}

// MARK: - Log food flow

private enum LogMode: String, CaseIterable, Identifiable {
    case search = "Search"
    case barcode = "Barcode"
    case photo = "Photo"
    var id: String { rawValue }
}

struct LogFoodSheet: View {
    let syncToHealthKit: Bool
    let initialDate: Date
    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @State private var mode: LogMode = .search
    @State private var searchText = ""
    @State private var candidates: [FoodCandidateDTO] = []
    @State private var notice: String?
    @State private var isLookingUp = false
    @State private var showingScanner = false
    @State private var selectedCandidate: FoodCandidateDTO?
    @State private var loggedAt: Date

    init(syncToHealthKit: Bool, initialDate: Date = Date()) {
        self.syncToHealthKit = syncToHealthKit
        self.initialDate = initialDate
        let cal = Calendar.current
        var comps = cal.dateComponents([.hour, .minute, .second], from: Date())
        let dayComps = cal.dateComponents([.year, .month, .day], from: initialDate)
        comps.year = dayComps.year
        comps.month = dayComps.month
        comps.day = dayComps.day
        _loggedAt = State(initialValue: cal.date(from: comps) ?? initialDate)
    }
    @State private var photoJPEG: Data?
    @State private var pickedItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingCameraUnavailableAlert = false
    @State private var pendingSource = "manual"
    @State private var pendingBarcode: String?
    @State private var mealCategory: MealCategory = MealCategory.defaultForCurrentTime()
    /// When true, `notice` text is shown in red (API/transport failure). When false, empty results use orange.
    @State private var lookupNoticeIsError = false
    @State private var favorites: [FoodCandidateDTO] = []
    @State private var comboFavorites: [ComboFavorite] = []
    @State private var showingManageFavorites = false
    /// Row indices into `candidates` (photo multi-select). Offsets are unique even when duplicate `FoodCandidateDTO.id` appears.
    @State private var selectedCandidateOffsets: Set<Int> = []
    @State private var showingMultiConfirm = false
    @State private var multiConfirmBases: [FoodCandidateDTO] = []
    /// Forces a fresh `ConfirmMultiFoodSheet` so `@State` quantities match `bases.count` (avoids index crash on reopen).
    @State private var multiConfirmSheetInstanceId = UUID()
    @State private var comboPending: [ComboItem] = []
    @State private var comboPendingName: String = ""
    @State private var showComboConfirm = false
    @State private var comboConfirmInstanceId = UUID()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    ForEach(LogMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: mode) { _, _ in
                    selectedCandidateOffsets.removeAll()
                }

                DatePicker("Time", selection: $loggedAt, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .id(loggedAt)
                    .padding(.horizontal)

                Picker("Meal", selection: $mealCategory) {
                    ForEach(MealCategory.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

                favoritesSection

                switch mode {
                case .search:
                    searchSection
                case .barcode:
                    barcodeSection
                case .photo:
                    photoSection
                }
            }
            .navigationTitle("Log food")
            .onAppear { refreshFavorites() }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Camera not available", isPresented: $showingCameraUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The Simulator has no camera. Use “Choose photo” or run the app on a physical iPhone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingManageFavorites) {
                ManageNutritionFavoritesSheet()
                    .onDisappear { refreshFavorites() }
            }
            .sheet(isPresented: $showingScanner) {
                ZStack(alignment: .topTrailing) {
                    BarcodeScanningContainer(
                        onCode: { code in
                            showingScanner = false
                            Task { await runBarcode(code) }
                        },
                        onCancel: { showingScanner = false }
                    )
                    Button("Cancel") {
                        showingScanner = false
                    }
                    .padding()
                    .tint(.white)
                    .shadow(radius: 2)
                }
            }
            .sheet(isPresented: $showingCamera) {
                ImagePickerRepresentable(imageData: $photoJPEG)
                    .ignoresSafeArea()
            }
            .sheet(item: $selectedCandidate) { c in
                ConfirmFoodSheet(
                    baseCandidate: c,
                    otherCandidates: candidates.filter { $0.id != c.id },
                    loggedAt: $loggedAt,
                    mealCategory: $mealCategory,
                    syncToHealthKit: syncToHealthKit,
                    source: pendingSource,
                    barcodeRaw: pendingBarcode,
                    photoJPEG: pendingSource == "photo" ? photoJPEG : nil,
                    onFavoritesChanged: { refreshFavorites() },
                    onDone: {
                        selectedCandidate = nil
                        refreshFavorites()
                        dismiss()
                    }
                )
            }
            .sheet(isPresented: $showingMultiConfirm) {
                ConfirmMultiFoodSheet(
                    bases: multiConfirmBases,
                    loggedAt: $loggedAt,
                    mealCategory: $mealCategory,
                    syncToHealthKit: syncToHealthKit,
                    photoJPEG: photoJPEG,
                    onFavoritesChanged: { refreshFavorites() },
                    onDone: {
                        showingMultiConfirm = false
                        selectedCandidateOffsets.removeAll()
                        candidates = []
                        photoJPEG = nil
                        pickedItem = nil
                        refreshFavorites()
                        dismiss()
                    },
                    onBack: { showingMultiConfirm = false }
                )
                .id(multiConfirmSheetInstanceId)
            }
            .sheet(isPresented: $showComboConfirm) {
                ConfirmComboSheet(
                    baseItems: comboPending,
                    initialName: comboPendingName,
                    loggedAt: $loggedAt,
                    mealCategory: $mealCategory,
                    syncToHealthKit: syncToHealthKit,
                    onFavoritesChanged: { refreshFavorites() },
                    onDone: {
                        showComboConfirm = false
                        comboPending = []
                        comboPendingName = ""
                        refreshFavorites()
                        dismiss()
                    },
                    onBack: { showComboConfirm = false }
                )
                .id(comboConfirmInstanceId)
            }
        }
    }

    private func refreshFavorites() {
        favorites = NutritionFavoritesStore.load()
        comboFavorites = ComboFavoritesStore.load()
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Favorites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Manage") {
                    showingManageFavorites = true
                }
                .font(.caption)
            }
            .padding(.horizontal)
            if favorites.isEmpty {
                Text("Use Confirm to add or remove favorites (star), or add from an edited logged food. Tap Manage to see or delete saved favorites.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(favorites) { fav in
                            Button {
                                pendingSource = "manual"
                                pendingBarcode = nil
                                selectedCandidate = fav
                            } label: {
                                Text(fav.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            if !comboFavorites.isEmpty {
                HStack {
                    Text("Recipes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(comboFavorites) { combo in
                            Button {
                                comboPending = combo.items
                                comboPendingName = combo.name
                                comboConfirmInstanceId = UUID()
                                showComboConfirm = true
                            } label: {
                                Text(combo.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var searchSection: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Food name", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit {
                        searchFocused = false
                        Task { await runSearch() }
                    }
                Button("Search") {
                    searchFocused = false
                    Task { await runSearch() }
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isLookingUp)
            }
            .padding(.horizontal)
            if isLookingUp {
                ProgressView("Searching…")
                    .font(.caption)
            }
            lookupNoticeView
            if !comboPending.isEmpty {
                comboTray
            }
            candidateList
        }
    }

    private var comboTray: some View {
        let totalKcal = comboPending.reduce(0.0) { $0 + $1.candidate.calories * $1.quantity }
        return HStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .foregroundStyle(Color.orange)
            Text("\(comboPending.count) item\(comboPending.count == 1 ? "" : "s") · \(Int(totalKcal)) kcal")
                .font(.subheadline)
            Spacer()
            Button("Review Combo →") {
                comboPendingName = ""
                comboConfirmInstanceId = UUID()
                showComboConfirm = true
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(Color.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private var barcodeSection: some View {
        VStack(spacing: 16) {
            Button {
                showingScanner = true
            } label: {
                Label("Scan barcode", systemImage: "barcode.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            if isLookingUp {
                ProgressView("Looking up barcode…")
                    .font(.caption)
            }
            lookupNoticeView
            candidateList
        }
    }

    private var photoSection: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label("Choose photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .onChange(of: pickedItem) { _, new in
                Task {
                    guard let new else { return }
                    if let data = try? await new.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        photoJPEG = ui.ht_jpegForFoodLookup()
                    }
                }
            }
            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showingCamera = true
                } else {
                    showingCameraUnavailableAlert = true
                }
            } label: {
                Label("Take photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            if let jpeg = photoJPEG, let previewImage = UIImage(data: jpeg) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meal photo")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                    HStack {
                        Text(
                            "~\(String(format: "%.1f", Double(jpeg.count) / 1_048_576)) MB · ready to analyze"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("Change photo") {
                            photoJPEG = nil
                            pickedItem = nil
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                    }
                }
                .padding(.horizontal)
            }

            Button {
                Task { await runPhoto() }
            } label: {
                if isLookingUp {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Analyze photo")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .disabled(photoJPEG == nil || isLookingUp)
            lookupNoticeView
            if mode == .photo, !selectedCandidateOffsets.isEmpty {
                Button {
                    multiConfirmBases = selectedCandidateOffsets.sorted().compactMap { idx in
                        guard candidates.indices.contains(idx) else { return nil }
                        return candidates[idx]
                    }
                    multiConfirmSheetInstanceId = UUID()
                    showingMultiConfirm = true
                } label: {
                    Text("Review \(selectedCandidateOffsets.count) food(s)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            candidateList
        }
    }

    @ViewBuilder
    private var lookupNoticeView: some View {
        if let notice, !notice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(notice)
                .font(.caption)
                .foregroundStyle(
                    lookupNoticeIsError
                        ? Color.red
                        : (candidates.isEmpty ? Color.orange : Color.secondary)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
    }

    private var candidateList: some View {
        List {
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, c in
                if mode == .photo {
                    Button {
                        if selectedCandidateOffsets.contains(index) {
                            selectedCandidateOffsets.remove(index)
                        } else {
                            selectedCandidateOffsets.insert(index)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selectedCandidateOffsets.contains(index) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedCandidateOffsets.contains(index) ? Color.accentColor : .secondary)
                                .font(.title3)
                            FoodCandidateRowContent(candidate: c)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        Button {
                            pendingSource = mode == .barcode ? "barcode" : "manual"
                            pendingBarcode = mode == .barcode ? pendingBarcode : nil
                            selectedCandidate = c
                        } label: {
                            FoodCandidateRowContent(candidate: c)
                        }
                        let inCombo = comboPending.contains(where: { $0.candidate.id == c.id })
                        Button {
                            if let idx = comboPending.firstIndex(where: { $0.candidate.id == c.id }) {
                                comboPending.remove(at: idx)
                            } else {
                                comboPending.append(ComboItem(candidate: c, quantity: 1))
                            }
                        } label: {
                            Image(systemName: inCombo ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(inCombo ? Color.accentColor : Color.secondary)
                                .font(.title3)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }
            }
        }
    }

    private func runSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isLookingUp = true
        notice = nil
        lookupNoticeIsError = false
        defer { isLookingUp = false }
        guard let res = await nutritionManager.lookupSearch(q) else {
            lookupNoticeIsError = true
            notice = nutritionManager.errorMessage ?? "Search failed."
            candidates = []
            return
        }
        lookupNoticeIsError = false
        candidates = res.candidates
        notice = res.notice
        selectedCandidateOffsets.removeAll()
        pendingSource = "manual"
        pendingBarcode = nil
    }

    private func runBarcode(_ code: String) async {
        isLookingUp = true
        notice = nil
        lookupNoticeIsError = false
        defer { isLookingUp = false }
        guard let res = await nutritionManager.lookupBarcode(code) else {
            lookupNoticeIsError = true
            notice = nutritionManager.errorMessage ?? "Barcode lookup failed."
            candidates = []
            return
        }
        lookupNoticeIsError = false
        candidates = res.candidates
        notice = res.notice
        selectedCandidateOffsets.removeAll()
        pendingSource = "barcode"
        pendingBarcode = code
    }

    private func runPhoto() async {
        guard let jpeg = photoJPEG else { return }
        isLookingUp = true
        notice = nil
        lookupNoticeIsError = false
        defer { isLookingUp = false }
        guard let res = await nutritionManager.lookupPhoto(imageJPEG: jpeg) else {
            lookupNoticeIsError = true
            notice = nutritionManager.errorMessage ?? "Photo analysis failed."
            candidates = []
            return
        }
        lookupNoticeIsError = false
        candidates = res.candidates
        notice = res.notice
        selectedCandidateOffsets.removeAll()
        pendingSource = "photo"
        pendingBarcode = nil
    }
}

private struct FoodCandidateRowContent: View {
    let candidate: FoodCandidateDTO

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let urlString = candidate.image_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        Color.secondary.opacity(0.15)
                    default:
                        EmptyView()
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(candidate.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let src = candidate.source {
                        Text(src == "usda" ? "USDA" : "OFF")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(src == "usda" ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                            .foregroundStyle(src == "usda" ? Color.blue : Color.green)
                            .clipShape(Capsule())
                    }
                }
                if let b = candidate.brand, !b.isEmpty {
                    Text(b)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let h = candidate.household_serving_text, !h.isEmpty {
                    Text(h)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(Int(candidate.calories.rounded())) kcal · P \(Int(candidate.protein_g))g · C \(Int(candidate.carb_g))g · F \(Int(candidate.fat_g))g")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

extension FoodCandidateDTO: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension FoodCandidateDTO: Equatable {
    static func == (lhs: FoodCandidateDTO, rhs: FoodCandidateDTO) -> Bool {
        lhs.id == rhs.id
    }
}

/// Calories, macros, fiber, sodium, and sugar — always listed (use 0 when the source did not provide a value).
private struct CoreNutritionRows: View {
    let calories: Double
    let proteinG: Double
    let carbG: Double
    let fatG: Double
    let fiberG: Double
    let sodiumMg: Double
    let sugarG: Double

    var body: some View {
        LabeledContent("Calories") { Text("\(Int(calories.rounded())) kcal") }
        LabeledContent("Protein") { Text("\(Int(proteinG.rounded())) g") }
        LabeledContent("Carbs") { Text("\(Int(carbG.rounded())) g") }
        LabeledContent("Fat") { Text("\(Int(fatG.rounded())) g") }
        LabeledContent("Fiber") { Text("\(Int(fiberG.rounded())) g") }
        LabeledContent("Sodium") { Text("\(Int(sodiumMg.rounded())) mg") }
        LabeledContent("Sugar") { Text("\(Int(sugarG.rounded())) g") }
    }
}

private struct NutritionFavoriteToggleRow: View {
    let candidate: FoodCandidateDTO
    var onChange: (() -> Void)?

    @State private var isFavorite = false

    init(candidate: FoodCandidateDTO, onChange: (() -> Void)? = nil) {
        self.candidate = candidate
        self.onChange = onChange
    }

    var body: some View {
        Button {
            NutritionFavoritesStore.toggle(candidate)
            isFavorite = NutritionFavoritesStore.contains(id: candidate.id)
            onChange?()
        } label: {
            Label(
                isFavorite ? "Remove from favorites" : "Add to favorites",
                systemImage: isFavorite ? "star.fill" : "star"
            )
        }
        .onAppear {
            isFavorite = NutritionFavoritesStore.contains(id: candidate.id)
        }
    }
}

private struct ManageNutritionFavoritesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var list: [FoodCandidateDTO] = []
    @State private var comboList: [ComboFavorite] = []
    @State private var editingCombo: ComboFavorite?

    var body: some View {
        NavigationStack {
            List {
                Section("Foods") {
                    if list.isEmpty {
                        Text("Tap the star when confirming a food to save it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(list) { fav in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fav.name)
                                if let b = fav.brand, !b.isEmpty {
                                    Text(b)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    NutritionFavoritesStore.remove(id: fav.id)
                                    list = NutritionFavoritesStore.load()
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                Section("Recipes") {
                    if comboList.isEmpty {
                        Text("Build a combo from multiple foods, name it, and save it as a recipe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(comboList) { combo in
                            Button { editingCombo = combo } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "fork.knife.circle.fill")
                                        .foregroundStyle(Color.orange)
                                        .font(.caption)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(combo.name)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        Text(combo.items.map(\.candidate.name).joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    ComboFavoritesStore.delete(combo.id)
                                    comboList = ComboFavoritesStore.load()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Favorites & Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                list = NutritionFavoritesStore.load()
                comboList = ComboFavoritesStore.load()
            }
            .sheet(item: $editingCombo) { combo in
                EditComboFavoriteSheet(combo: combo) {
                    comboList = ComboFavoritesStore.load()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Edit saved recipe

private struct EditComboFavoriteSheet: View {
    let combo: ComboFavorite
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var items: [ComboItem]

    init(combo: ComboFavorite, onSaved: @escaping () -> Void) {
        self.combo = combo
        self.onSaved = onSaved
        _name = State(initialValue: combo.name)
        _items = State(initialValue: combo.items)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife.circle.fill")
                            .foregroundStyle(Color.orange)
                        TextField("Recipe name", text: $name)
                            .font(.headline)
                    }
                }
                Section("Items — swipe to remove") {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.candidate.name)
                                        .font(.body)
                                    if let b = item.candidate.brand, !b.isEmpty {
                                        Text(b).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(Int(scaledCalories(at: index).rounded())) kcal")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text("P \(Int(scaledMacro(at: index, \.protein_g)))g · C \(Int(scaledMacro(at: index, \.carb_g)))g · F \(Int(scaledMacro(at: index, \.fat_g)))g")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Stepper(value: bindingQty(index), in: 0.25...20, step: 0.25) {
                                Text("Quantity: ×\(formatQty(items[index].quantity))")
                                    .font(.subheadline)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                items.remove(at: index)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    if items.isEmpty {
                        Text("All items removed — add at least one before saving.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !items.isEmpty {
                    Section("Total") {
                        CoreNutritionRows(
                            calories: items.indices.reduce(0) { $0 + scaledCalories(at: $1) },
                            proteinG: items.indices.reduce(0) { $0 + scaledMacro(at: $1, \.protein_g) },
                            carbG: items.indices.reduce(0) { $0 + scaledMacro(at: $1, \.carb_g) },
                            fatG: items.indices.reduce(0) { $0 + scaledMacro(at: $1, \.fat_g) },
                            fiberG: items.indices.reduce(0) { $0 + scaledMacro(at: $1, \.fiber_g, default: 0) },
                            sodiumMg: items.indices.reduce(0) { $0 + scaledMacro(at: $1, \.sodium_mg, default: 0) },
                            sugarG: items.indices.reduce(0) { $0 + scaledSugar(at: $1) }
                        )
                    }
                }
            }
            .navigationTitle("Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = combo
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.items = items
                        ComboFavoritesStore.upsert(updated)
                        onSaved()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || items.isEmpty)
                }
            }
        }
    }

    private func scaledCalories(at index: Int) -> Double {
        guard items.indices.contains(index) else { return 0 }
        return items[index].candidate.calories * items[index].quantity
    }

    private func scaledMacro(at index: Int, _ kp: KeyPath<FoodCandidateDTO, Double>) -> Double {
        guard items.indices.contains(index) else { return 0 }
        return items[index].candidate[keyPath: kp] * items[index].quantity
    }

    private func scaledMacro(at index: Int, _ kp: KeyPath<FoodCandidateDTO, Double?>, default d: Double) -> Double {
        guard items.indices.contains(index) else { return d }
        return (items[index].candidate[keyPath: kp] ?? d) * items[index].quantity
    }

    private func scaledSugar(at index: Int) -> Double {
        guard items.indices.contains(index) else { return 0 }
        return items[index].candidate.sugarGramsFromNutrients * items[index].quantity
    }

    private func bindingQty(_ index: Int) -> Binding<Double> {
        Binding(
            get: { index < items.count ? items[index].quantity : 1 },
            set: { newVal in
                guard items.indices.contains(index) else { return }
                items[index].quantity = newVal
            }
        )
    }

    private func formatQty(_ q: Double) -> String {
        abs(q.rounded() - q) < 0.001 ? String(format: "%.0f", q) : String(format: "%.2f", q)
    }
}

struct ConfirmFoodSheet: View {
    let baseCandidate: FoodCandidateDTO
    let otherCandidates: [FoodCandidateDTO]
    @Binding var loggedAt: Date
    @Binding var mealCategory: MealCategory
    let syncToHealthKit: Bool
    let source: String
    let barcodeRaw: String?
    let photoJPEG: Data?
    var onFavoritesChanged: (() -> Void)?
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @State private var isSaving = false
    @State private var quantity: Double = 1
    @State private var gramsText: String
    @State private var mealNotes: String = ""
    @State private var showReferenceNutrients = false
    @State private var displayImageUrl: String?
    @State private var imageLoadFailed = false

    init(
        baseCandidate: FoodCandidateDTO,
        otherCandidates: [FoodCandidateDTO] = [],
        loggedAt: Binding<Date>,
        mealCategory: Binding<MealCategory>,
        syncToHealthKit: Bool,
        source: String,
        barcodeRaw: String?,
        photoJPEG: Data?,
        onFavoritesChanged: (() -> Void)? = nil,
        onDone: @escaping () -> Void
    ) {
        self.baseCandidate = baseCandidate
        self.otherCandidates = otherCandidates
        _loggedAt = loggedAt
        _mealCategory = mealCategory
        self.syncToHealthKit = syncToHealthKit
        self.source = source
        self.barcodeRaw = barcodeRaw
        self.photoJPEG = photoJPEG
        self.onFavoritesChanged = onFavoritesChanged
        self.onDone = onDone
        let g = max(baseCandidate.grams ?? 100, 1)
        _gramsText = State(initialValue: String(format: "%.0f", g))
        _displayImageUrl = State(initialValue: baseCandidate.image_url)
    }

    @ViewBuilder
    private var imageSection: some View {
        if let urlString = displayImageUrl, !imageLoadFailed, let url = URL(string: urlString) {
            Section {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else if case .failure(_) = phase {
                        Color.clear.onAppear { imageLoadFailed = true }
                    } else {
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
            }
            .listRowInsets(EdgeInsets())
        }
        let alternatives = Array(otherCandidates.compactMap { $0.image_url }.prefix(8))
        if !alternatives.isEmpty && (displayImageUrl == nil || imageLoadFailed) {
            Section("No image — tap one to use") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(alternatives.indices, id: \.self) { i in
                            if let url = URL(string: alternatives[i]) {
                                Button {
                                    displayImageUrl = alternatives[i]
                                    imageLoadFailed = false
                                } label: {
                                    AsyncImage(url: url) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFill()
                                        } else if case .empty = phase {
                                            Color.secondary.opacity(0.15)
                                        }
                                    }
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                imageSection
                Section(header: Text(baseCandidate.name)) {
                    if let b = baseCandidate.brand, !b.isEmpty {
                        Text(b)
                            .foregroundStyle(.secondary)
                    }
                    if let h = baseCandidate.household_serving_text, !h.isEmpty {
                        Text(h)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $quantity, in: 0.25 ... 99, step: 0.25) {
                        Text("Quantity: \(formatQty(quantity))× label serving")
                    }
                    .onChange(of: quantity) { _, q in
                        let b = max(baseCandidate.grams ?? 100, 1)
                        gramsText = String(format: "%.0f", b * q)
                    }
                    TextField("Total grams", text: $gramsText)
                        .keyboardType(.decimalPad)
                    Text("Adjust quantity or grams; totals stay in sync when you use the stepper.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Section("Meal") {
                    Picker("Category", selection: $mealCategory) {
                        ForEach(MealCategory.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    TextField("Notes (optional)", text: $mealNotes, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                Section {
                    NutritionFavoriteToggleRow(candidate: baseCandidate, onChange: onFavoritesChanged)
                }
                Section("Nutrition (this portion)") {
                    let scaled = scaledCandidate
                    CoreNutritionRows(
                        calories: scaled.calories,
                        proteinG: scaled.protein_g,
                        carbG: scaled.carb_g,
                        fatG: scaled.fat_g,
                        fiberG: scaled.fiber_g ?? 0,
                        sodiumMg: scaled.sodium_mg ?? 0,
                        sugarG: scaled.sugarGramsFromNutrients
                    )
                }
                if let ex = scaledCandidate.nutrients_extra, !ex.isEmpty {
                    Section {
                        DisclosureGroup("More nutrients (reference)", isExpanded: $showReferenceNutrients) {
                            ForEach(ex.keys.sorted().filter { $0 != "sugars_g" }, id: \.self) { k in
                                LabeledContent(k) {
                                    Text(String(format: "%.1f", ex[k] ?? 0))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func formatQty(_ q: Double) -> String {
        abs(q.rounded() - q) < 0.001 ? String(format: "%.0f", q) : String(format: "%.2f", q)
    }

    private var scaledCandidate: FoodCandidateDTO {
        let baseG = max(baseCandidate.grams ?? 100, 1)
        let parsed = Double(gramsText.replacingOccurrences(of: ",", with: "."))
        let totalG = max(parsed ?? baseG * quantity, 1)
        return baseCandidate.scaled(gramsEaten: totalG)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let baseG = max(baseCandidate.grams ?? 100, 1)
        let parsed = Double(gramsText.replacingOccurrences(of: ",", with: "."))
        let totalG = max(parsed ?? baseG * quantity, 1)
        let qty = max(totalG / baseG, 0.01)
        let scaled = baseCandidate.scaled(gramsEaten: totalG)
        let line = NutritionManager.MealSaveLine(
            scaledTotals: scaled,
            quantity: qty,
            perUnitServingAmount: baseCandidate.serving_amount,
            perUnitServingUnit: baseCandidate.serving_unit
        )
        let notesTrim = mealNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = NutritionManager.MealSaveInput(
            source: source,
            mealType: mealCategory.rawValue,
            notes: notesTrim.isEmpty ? nil : notesTrim,
            barcodeRaw: barcodeRaw,
            photoJPEG: photoJPEG,
            loggedAt: loggedAt,
            items: [line]
        )
        let ok = await nutritionManager.saveMeal(input, syncToHealthKit: syncToHealthKit)
        if ok {
            dismiss()
            onDone()
        }
    }
}

// MARK: - Multi-item confirm (photo)

struct ConfirmMultiFoodSheet: View {
    let bases: [FoodCandidateDTO]
    @Binding var loggedAt: Date
    @Binding var mealCategory: MealCategory
    let syncToHealthKit: Bool
    let photoJPEG: Data?
    var onFavoritesChanged: (() -> Void)?
    var onDone: () -> Void
    var onBack: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @State private var quantities: [Double]
    @State private var mealNotes: String = ""
    @State private var isSaving = false

    init(
        bases: [FoodCandidateDTO],
        loggedAt: Binding<Date>,
        mealCategory: Binding<MealCategory>,
        syncToHealthKit: Bool,
        photoJPEG: Data?,
        onFavoritesChanged: (() -> Void)? = nil,
        onDone: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.bases = bases
        _loggedAt = loggedAt
        _mealCategory = mealCategory
        self.syncToHealthKit = syncToHealthKit
        self.photoJPEG = photoJPEG
        self.onFavoritesChanged = onFavoritesChanged
        self.onDone = onDone
        self.onBack = onBack
        _quantities = State(initialValue: Array(repeating: 1, count: bases.count))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    DatePicker("Time", selection: $loggedAt, displayedComponents: [.date, .hourAndMinute])
                    Picker("Category", selection: $mealCategory) {
                        ForEach(MealCategory.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    TextField("Notes (optional)", text: $mealNotes, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                ForEach(Array(bases.enumerated()), id: \.offset) { index, base in
                    Section {
                        if let b = base.brand, !b.isEmpty {
                            Text(b)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Stepper(value: bindingQty(index), in: 0.25 ... 99, step: 0.25) {
                            Text("Quantity: \(formatQty(qtySafeRead(at: index)))×")
                        }
                        let scaled = scaledLine(base: base, index: index)
                        CoreNutritionRows(
                            calories: scaled.calories,
                            proteinG: scaled.protein_g,
                            carbG: scaled.carb_g,
                            fatG: scaled.fat_g,
                            fiberG: scaled.fiber_g ?? 0,
                            sodiumMg: scaled.sodium_mg ?? 0,
                            sugarG: scaled.sugarGramsFromNutrients
                        )
                        NutritionFavoriteToggleRow(candidate: base, onChange: onFavoritesChanged)
                    } header: {
                        Text(base.name)
                    }
                }
                Section("Meal total") {
                    CoreNutritionRows(
                        calories: mealCalories,
                        proteinG: mealProtein,
                        carbG: mealCarbs,
                        fatG: mealFat,
                        fiberG: mealFiber,
                        sodiumMg: mealSodium,
                        sugarG: mealSugar
                    )
                }
            }
            .navigationTitle("Confirm foods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        dismiss()
                        onBack()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save meal") {
                        Task { await save() }
                    }
                    .disabled(isSaving || bases.isEmpty)
                }
            }
            .onAppear {
                if quantities.count != bases.count {
                    quantities = Array(repeating: 1, count: bases.count)
                }
            }
        }
    }

    private var mealCalories: Double {
        mealMacroSum(\.calories)
    }

    private var mealProtein: Double {
        mealMacroSum(\.protein_g)
    }

    private var mealCarbs: Double {
        mealMacroSum(\.carb_g)
    }

    private var mealFat: Double {
        mealMacroSum(\.fat_g)
    }

    private var mealFiber: Double {
        var t = 0.0
        for (i, base) in bases.enumerated() {
            t += scaledLine(base: base, index: i).fiber_g ?? 0
        }
        return t
    }

    private var mealSodium: Double {
        var t = 0.0
        for (i, base) in bases.enumerated() {
            t += scaledLine(base: base, index: i).sodium_mg ?? 0
        }
        return t
    }

    private var mealSugar: Double {
        var t = 0.0
        for (i, base) in bases.enumerated() {
            t += scaledLine(base: base, index: i).sugarGramsFromNutrients
        }
        return t
    }

    private func mealMacroSum(_ keyPath: KeyPath<FoodCandidateDTO, Double>) -> Double {
        var t = 0.0
        for (i, base) in bases.enumerated() {
            t += scaledLine(base: base, index: i)[keyPath: keyPath]
        }
        return t
    }

    private func bindingQty(_ index: Int) -> Binding<Double> {
        Binding(
            get: { qtySafeRead(at: index) },
            set: { newVal in
                while quantities.count <= index {
                    quantities.append(1)
                }
                guard quantities.indices.contains(index) else { return }
                quantities[index] = newVal
            }
        )
    }

    /// Read-only: never mutates state (safe during `body`).
    private func qtySafeRead(at index: Int) -> Double {
        guard index >= 0, index < bases.count, index < quantities.count else { return 1 }
        return quantities[index]
    }

    private func scaledLine(base: FoodCandidateDTO, index: Int) -> FoodCandidateDTO {
        let baseG = max(base.grams ?? 100, 1)
        let totalG = baseG * max(qtySafeRead(at: index), 0.01)
        return base.scaled(gramsEaten: totalG)
    }

    private func formatQty(_ q: Double) -> String {
        abs(q.rounded() - q) < 0.001 ? String(format: "%.0f", q) : String(format: "%.2f", q)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        if quantities.count != bases.count {
            quantities = Array(repeating: 1, count: bases.count)
        }
        var lines: [NutritionManager.MealSaveLine] = []
        for (i, base) in bases.enumerated() {
            let qv = max(i < quantities.count ? quantities[i] : 1, 0.01)
            let baseG = max(base.grams ?? 100, 1)
            let totalG = baseG * qv
            let scaled = base.scaled(gramsEaten: totalG)
            lines.append(
                NutritionManager.MealSaveLine(
                    scaledTotals: scaled,
                    quantity: qv,
                    perUnitServingAmount: base.serving_amount,
                    perUnitServingUnit: base.serving_unit
                )
            )
        }
        let notesTrim = mealNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = NutritionManager.MealSaveInput(
            source: "photo",
            mealType: mealCategory.rawValue,
            notes: notesTrim.isEmpty ? nil : notesTrim,
            barcodeRaw: nil,
            photoJPEG: photoJPEG,
            loggedAt: loggedAt,
            items: lines
        )
        let ok = await nutritionManager.saveMeal(input, syncToHealthKit: syncToHealthKit)
        if ok {
            dismiss()
            onDone()
        }
    }
}

// MARK: - Edit one saved line item

private struct EditNutritionLineItemSheet: View {
    let log: NutritionLogRow
    let item: NutritionLogItemRow

    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @AppStorage("syncNutritionToHealthKit") private var syncNutritionToHealthKit = true
    @State private var gramsText: String
    @State private var quantity: Double
    @State private var isSaving = false

    init(log: NutritionLogRow, item: NutritionLogItemRow) {
        self.log = log
        self.item = item
        let g = item.grams ?? item.serving_amount
        _gramsText = State(initialValue: String(format: "%.0f", max(g, 1)))
        _quantity = State(initialValue: max(item.quantity ?? 1, 0.01))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)
                        if let b = item.brand, !b.isEmpty {
                            Text(b)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    NutritionFavoriteToggleRow(candidate: FoodCandidateDTO(fromLoggedItem: item))
                }
                Section("Portion") {
                    Stepper(value: $quantity, in: 0.25 ... 99, step: 0.25) {
                        Text("Quantity: \(formatQty(quantity))×")
                    }
                    .onChange(of: quantity) { _, q in
                        let per = max((item.grams ?? item.serving_amount) / max(item.quantity ?? 1, 0.01), 1)
                        gramsText = String(format: "%.0f", per * q)
                    }
                    TextField("Total grams", text: $gramsText)
                        .keyboardType(.decimalPad)
                }
                Section("Nutrition (scaled)") {
                    let p = scaledPreviewLineItem
                    CoreNutritionRows(
                        calories: p.calories,
                        proteinG: p.protein,
                        carbG: p.carbs,
                        fatG: p.fat,
                        fiberG: p.fiber,
                        sodiumMg: p.sodium,
                        sugarG: p.sugar
                    )
                }
                if let err = nutritionManager.errorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Text(
                        syncNutritionToHealthKit
                            ? "Saves to your account and updates Apple Health totals for this meal."
                            : "Apple Health sync is off; only your account is updated."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var scaledPreviewLineItem: (calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, sodium: Double, sugar: Double) {
        let oldG = max(item.grams ?? item.serving_amount, 1)
        let parsed = Double(gramsText.replacingOccurrences(of: ",", with: "."))
        let newG = max(parsed ?? oldG, 1)
        let factor = newG / oldG
        return (
            item.calories * factor,
            item.protein_g * factor,
            item.carb_g * factor,
            item.fat_g * factor,
            (item.fiber_g ?? 0) * factor,
            (item.sodium_mg ?? 0) * factor,
            item.sugarGramsFromNutrients * factor
        )
    }

    private func formatQty(_ q: Double) -> String {
        abs(q.rounded() - q) < 0.001 ? String(format: "%.0f", q) : String(format: "%.2f", q)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let parsed = Double(gramsText.replacingOccurrences(of: ",", with: "."))
        let newG = max(parsed ?? 1, 1)
        let newQty = max(quantity, 0.01)
        let ok = await nutritionManager.updateLogLineItem(
            log: log,
            itemId: item.id,
            newGrams: newG,
            newQuantity: newQty,
            syncToHealthKit: syncNutritionToHealthKit
        )
        if ok {
            dismiss()
        }
    }
}

// MARK: - Edit logged meal

private struct EditNutritionLogSheet: View {
    let log: NutritionLogRow
    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @AppStorage("syncNutritionToHealthKit") private var syncNutritionToHealthKit = true
    @State private var loggedAt: Date
    @State private var mealCategory: MealCategory
    @State private var gramsText: String
    @State private var quantity: Double
    @State private var notesText: String
    @State private var isSaving = false
    @State private var recipeNameText: String = ""
    @State private var recipeSaved = false
    @State private var editingItem: NutritionLogItemRow?

    init(log: NutritionLogRow) {
        self.log = log
        _loggedAt = State(initialValue: log.logged_at)
        _mealCategory = State(initialValue: MealCategory(rawValue: log.meal_type ?? "") ?? .lunch)
        let first = log.nutrition_log_items?.first
        let g = first?.grams ?? first?.serving_amount ?? 100
        _gramsText = State(initialValue: String(format: "%.0f", max(g, 1)))
        _quantity = State(initialValue: max(first?.quantity ?? 1, 0.01))
        _notesText = State(initialValue: log.notes ?? "")
        let existingComboName = log.nutrition_log_items?.compactMap(\.combo_name).first ?? ""
        _recipeNameText = State(initialValue: existingComboName)
    }

    private var singleItem: NutritionLogItemRow? {
        guard let items = log.nutrition_log_items, items.count == 1 else { return nil }
        return items.first
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item = singleItem {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.headline)
                            if let b = item.brand, !b.isEmpty {
                                Text(b)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        NutritionFavoriteToggleRow(candidate: FoodCandidateDTO(fromLoggedItem: item))
                    }
                } else if let items = log.nutrition_log_items, !items.isEmpty {
                    let existingComboName = items.compactMap(\.combo_name).first
                    if let comboName = existingComboName, !comboName.isEmpty {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "fork.knife.circle.fill")
                                    .foregroundStyle(Color.orange)
                                Text(comboName)
                                    .font(.headline)
                            }
                        }
                    }
                    Section("Foods — tap to edit portions") {
                        ForEach(items) { item in
                            Button { editingItem = item } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .foregroundStyle(.primary)
                                        if let b = item.brand, !b.isEmpty {
                                            Text(b).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let q = item.quantity, abs(q - 1) > 0.001 {
                                            Text("×\(q.rounded(.toNearestOrAwayFromZero) == q ? String(format: "%.0f", q) : String(format: "%.1f", q))")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    Text("\(Int(item.calories.rounded())) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    Section("Save as recipe favorite") {
                        if recipeSaved {
                            Label("Saved to recipes!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                        } else {
                            HStack {
                                TextField("Recipe name", text: $recipeNameText)
                                Button("Save") {
                                    let name = recipeNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !name.isEmpty else { return }
                                    let comboItems = items.map { item in
                                        ComboItem(candidate: FoodCandidateDTO(fromLoggedItem: item), quantity: 1)
                                    }
                                    ComboFavoritesStore.upsert(ComboFavorite(name: name, items: comboItems))
                                    recipeSaved = true
                                }
                                .disabled(recipeNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("No food line items on this entry.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("When") {
                    DatePicker("Time", selection: $loggedAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Meal") {
                    Picker("Category", selection: $mealCategory) {
                        ForEach(MealCategory.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                }
                if singleItem != nil {
                    Section("Portion") {
                        Stepper(value: $quantity, in: 0.25 ... 99, step: 0.25) {
                            Text("Quantity: \(formatEditQty(quantity))×")
                        }
                        .onChange(of: quantity) { _, q in
                            guard let item = singleItem else { return }
                            let per = max((item.grams ?? item.serving_amount) / max(item.quantity ?? 1, 0.01), 1)
                            gramsText = String(format: "%.0f", per * q)
                        }
                        TextField("Total grams", text: $gramsText)
                            .keyboardType(.decimalPad)
                    }
                    if let p = singleItemScaledPreview {
                        Section("Nutrition (scaled)") {
                            CoreNutritionRows(
                                calories: p.calories,
                                proteinG: p.protein,
                                carbG: p.carbs,
                                fatG: p.fat,
                                fiberG: p.fiber,
                                sodiumMg: p.sodium,
                                sugarG: p.sugar
                            )
                        }
                    }
                }
                if let err = nutritionManager.errorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("Notes") {
                    TextField("Meal notes", text: $notesText, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
                Section {
                    Text(
                        syncNutritionToHealthKit
                            ? "Edits sync to Apple Health for this meal (previous samples are replaced)."
                            : "Apple Health sync is off; only your account is updated."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingItem) { item in
                EditNutritionLineItemSheet(log: log, item: item)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var singleItemScaledPreview: (calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, sodium: Double, sugar: Double)? {
        guard let item = singleItem else { return nil }
        let oldG = max(item.grams ?? item.serving_amount, 1)
        let parsed = Double(gramsText.replacingOccurrences(of: ",", with: "."))
        let newG = max(parsed ?? oldG, 1)
        let factor = newG / oldG
        return (
            item.calories * factor,
            item.protein_g * factor,
            item.carb_g * factor,
            item.fat_g * factor,
            (item.fiber_g ?? 0) * factor,
            (item.sodium_mg ?? 0) * factor,
            item.sugarGramsFromNutrients * factor
        )
    }

    private func formatEditQty(_ q: Double) -> String {
        abs(q.rounded() - q) < 0.001 ? String(format: "%.0f", q) : String(format: "%.2f", q)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let newGrams: Double? = {
            guard singleItem != nil else { return nil }
            let parsed = Double(gramsText.replacingOccurrences(of: ",", with: "."))
            return max(parsed ?? 1, 1)
        }()
        let newQty: Double? = singleItem != nil ? max(quantity, 0.01) : nil
        let ok = await nutritionManager.updateLog(
            log,
            loggedAt: loggedAt,
            mealCategory: mealCategory,
            notes: notesText,
            newGramsForSingleItem: newGrams,
            newQuantityForSingleItem: newQty,
            syncToHealthKit: syncNutritionToHealthKit
        )
        if ok {
            dismiss()
        }
    }
}

// MARK: - Combo confirm sheet

struct ConfirmComboSheet: View {
    let baseItems: [ComboItem]
    let initialName: String
    @Binding var loggedAt: Date
    @Binding var mealCategory: MealCategory
    let syncToHealthKit: Bool
    var onFavoritesChanged: (() -> Void)?
    var onDone: () -> Void
    var onBack: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @State private var items: [ComboItem]
    @State private var comboName: String
    @State private var saveAsFavorite: Bool = false
    @State private var mealNotes: String = ""
    @State private var isSaving = false

    init(
        baseItems: [ComboItem],
        initialName: String = "",
        loggedAt: Binding<Date>,
        mealCategory: Binding<MealCategory>,
        syncToHealthKit: Bool,
        onFavoritesChanged: (() -> Void)? = nil,
        onDone: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.baseItems = baseItems
        self.initialName = initialName
        _loggedAt = loggedAt
        _mealCategory = mealCategory
        self.syncToHealthKit = syncToHealthKit
        self.onFavoritesChanged = onFavoritesChanged
        self.onDone = onDone
        self.onBack = onBack
        _items = State(initialValue: baseItems)
        _comboName = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Name (optional)", text: $comboName)
                    Toggle("Save as recipe favorite", isOn: $saveAsFavorite)
                        .disabled(comboName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Meal") {
                    DatePicker("Time", selection: $loggedAt, displayedComponents: [.date, .hourAndMinute])
                    Picker("Category", selection: $mealCategory) {
                        ForEach(MealCategory.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    TextField("Notes (optional)", text: $mealNotes, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Section {
                        if let b = item.candidate.brand, !b.isEmpty {
                            Text(b)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Stepper(value: bindingQty(index), in: 0.25 ... 99, step: 0.25) {
                            Text("Quantity: \(formatQty(items[index].quantity))×")
                        }
                        let scaled = scaledCandidate(at: index)
                        CoreNutritionRows(
                            calories: scaled.calories,
                            proteinG: scaled.protein_g,
                            carbG: scaled.carb_g,
                            fatG: scaled.fat_g,
                            fiberG: scaled.fiber_g ?? 0,
                            sodiumMg: scaled.sodium_mg ?? 0,
                            sugarG: scaled.sugarGramsFromNutrients
                        )
                    } header: {
                        Text(item.candidate.name)
                    }
                }
                Section("Total") {
                    CoreNutritionRows(
                        calories: totalCalories,
                        proteinG: totalProtein,
                        carbG: totalCarbs,
                        fatG: totalFat,
                        fiberG: totalFiber,
                        sodiumMg: totalSodium,
                        sugarG: totalSugar
                    )
                }
            }
            .navigationTitle("Confirm recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        dismiss()
                        onBack()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        Task { await save() }
                    }
                    .disabled(isSaving || items.isEmpty)
                }
            }
        }
    }

    private func bindingQty(_ index: Int) -> Binding<Double> {
        Binding(
            get: { index < items.count ? items[index].quantity : 1 },
            set: { newVal in
                guard items.indices.contains(index) else { return }
                items[index].quantity = newVal
            }
        )
    }

    private func scaledCandidate(at index: Int) -> FoodCandidateDTO {
        guard items.indices.contains(index) else { return baseItems[0].candidate }
        let item = items[index]
        let baseG = max(item.candidate.grams ?? 100, 1)
        return item.candidate.scaled(gramsEaten: baseG * max(item.quantity, 0.01))
    }

    private var totalCalories: Double { items.indices.reduce(0) { $0 + scaledCandidate(at: $1).calories } }
    private var totalProtein: Double { items.indices.reduce(0) { $0 + scaledCandidate(at: $1).protein_g } }
    private var totalCarbs: Double { items.indices.reduce(0) { $0 + scaledCandidate(at: $1).carb_g } }
    private var totalFat: Double { items.indices.reduce(0) { $0 + scaledCandidate(at: $1).fat_g } }
    private var totalFiber: Double { items.indices.reduce(0) { $0 + (scaledCandidate(at: $1).fiber_g ?? 0) } }
    private var totalSodium: Double { items.indices.reduce(0) { $0 + (scaledCandidate(at: $1).sodium_mg ?? 0) } }
    private var totalSugar: Double { items.indices.reduce(0) { $0 + scaledCandidate(at: $1).sugarGramsFromNutrients } }

    private func formatQty(_ q: Double) -> String {
        abs(q.rounded() - q) < 0.001 ? String(format: "%.0f", q) : String(format: "%.2f", q)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let nameTrim = comboName.trimmingCharacters(in: .whitespacesAndNewlines)
        let comboTag: String? = nameTrim.isEmpty ? nil : nameTrim
        if saveAsFavorite, let tag = comboTag {
            let savedItems = items.map { item -> ComboItem in
                let baseG = max(item.candidate.grams ?? 100, 1)
                let scaled = item.candidate.scaled(gramsEaten: baseG * max(item.quantity, 0.01))
                return ComboItem(candidate: scaled, quantity: 1)
            }
            ComboFavoritesStore.upsert(ComboFavorite(name: tag, items: savedItems))
            onFavoritesChanged?()
        }
        var lines: [NutritionManager.MealSaveLine] = []
        for item in items {
            let baseG = max(item.candidate.grams ?? 100, 1)
            let qv = max(item.quantity, 0.01)
            let totalG = baseG * qv
            let scaled = item.candidate.scaled(gramsEaten: totalG)
            var line = NutritionManager.MealSaveLine(
                scaledTotals: scaled,
                quantity: qv,
                perUnitServingAmount: item.candidate.serving_amount,
                perUnitServingUnit: item.candidate.serving_unit
            )
            line.comboName = comboTag
            lines.append(line)
        }
        let notesTrim = mealNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = NutritionManager.MealSaveInput(
            source: "manual",
            mealType: mealCategory.rawValue,
            notes: notesTrim.isEmpty ? nil : notesTrim,
            barcodeRaw: nil,
            photoJPEG: nil,
            loggedAt: loggedAt,
            items: lines
        )
        let ok = await nutritionManager.saveMeal(input, syncToHealthKit: syncToHealthKit)
        if ok {
            dismiss()
            onDone()
        }
    }
}

// MARK: - Camera picker

struct ImagePickerRepresentable: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        // Simulator (and some Mac Catalyst setups) have no camera; `.camera` throws "Source type 1 not available".
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            p.sourceType = .camera
        } else if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            p.sourceType = .photoLibrary
        }
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerRepresentable
        init(_ parent: ImagePickerRepresentable) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = info[.originalImage] as? UIImage {
                parent.imageData = img.ht_jpegForFoodLookup()
            }
            parent.dismiss()
        }
    }
}
