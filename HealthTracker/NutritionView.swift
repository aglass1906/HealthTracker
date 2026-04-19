//
//  NutritionView.swift
//  HealthTracker
//

import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
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
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Health")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Save calories & macros when you log a meal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: $syncNutritionToHealthKit)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Sync logged meals to Apple Health")
                }

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
                            .accessibilityLabel("Day for meal list")
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                macroChip("Cal", value: Int(t.calories.rounded()), unit: "kcal")
                                macroChip("P", value: Int(t.protein.rounded()), unit: "g")
                                macroChip("C", value: Int(t.carbs.rounded()), unit: "g")
                                macroChip("F", value: Int(t.fat.rounded()), unit: "g")
                                macroChip("Sugar", value: Int(t.sugar.rounded()), unit: "g")
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
                            Image(systemName: "star.circle")
                        }
                        .accessibilityLabel("Manage favorite foods")
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
            .sheet(isPresented: $showingLogSheet) {
                LogFoodSheet(syncToHealthKit: syncNutritionToHealthKit)
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
                await nutritionManager.loadLogs(from: selectedDayStart, to: selectedDayEnd)
            }
            .refreshable {
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
}

struct NutritionLogRowView: View {
    let log: NutritionLogRow
    var onEditMeal: () -> Void
    var onEditItem: (NutritionLogItemRow) -> Void

    @State private var thumbURL: URL?

    private var isMultiItem: Bool {
        (log.nutrition_log_items?.count ?? 0) > 1
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
            guard let path = log.photo_path, !path.isEmpty else {
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
            } else if log.photo_path != nil {
                thumbPlaceholder
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

    private var sourceIcon: String {
        switch log.source {
        case "barcode": return "barcode.viewfinder"
        case "photo": return "camera.fill"
        default: return "magnifyingglass"
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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @State private var mode: LogMode = .search
    @State private var searchText = ""
    @State private var candidates: [FoodCandidateDTO] = []
    @State private var notice: String?
    @State private var isLookingUp = false
    @State private var showingScanner = false
    @State private var selectedCandidate: FoodCandidateDTO?
    @State private var loggedAt = Date()
    @State private var photoJPEG: Data?
    @State private var pickedItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingCameraUnavailableAlert = false
    @State private var pendingSource = "manual"
    @State private var pendingBarcode: String?
    @State private var mealCategory: MealCategory = .lunch
    /// When true, `notice` text is shown in red (API/transport failure). When false, empty results use orange.
    @State private var lookupNoticeIsError = false
    @State private var favorites: [FoodCandidateDTO] = []
    @State private var showingManageFavorites = false
    /// Row indices into `candidates` (photo multi-select). Offsets are unique even when duplicate `FoodCandidateDTO.id` appears.
    @State private var selectedCandidateOffsets: Set<Int> = []
    @State private var showingMultiConfirm = false
    @State private var multiConfirmBases: [FoodCandidateDTO] = []
    /// Forces a fresh `ConfirmMultiFoodSheet` so `@State` quantities match `bases.count` (avoids index crash on reopen).
    @State private var multiConfirmSheetInstanceId = UUID()

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
        }
    }

    private func refreshFavorites() {
        favorites = NutritionFavoritesStore.load()
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
        }
    }

    private var searchSection: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Food name", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }
                Button("Search") { Task { await runSearch() } }
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isLookingUp)
            }
            .padding(.horizontal)
            if isLookingUp {
                ProgressView("Searching…")
                    .font(.caption)
            }
            lookupNoticeView
            candidateList
        }
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
                    Button {
                        pendingSource = mode == .barcode ? "barcode" : "manual"
                        pendingBarcode = mode == .barcode ? pendingBarcode : nil
                        selectedCandidate = c
                    } label: {
                        FoodCandidateRowContent(candidate: c)
                    }
                }
            }
        }
        .listStyle(.plain)
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
                Text(candidate.name)
                    .font(.body)
                    .foregroundStyle(.primary)
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

    var body: some View {
        NavigationStack {
            Group {
                if list.isEmpty {
                    ContentUnavailableView(
                        "No favorites",
                        systemImage: "star",
                        description: Text("Add foods from Confirm when logging, or from Edit on a logged item.")
                    )
                } else {
                    List {
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
            }
            .navigationTitle("Favorite foods")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { list = NutritionFavoritesStore.load() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ConfirmFoodSheet: View {
    let baseCandidate: FoodCandidateDTO
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

    init(
        baseCandidate: FoodCandidateDTO,
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
    }

    var body: some View {
        NavigationStack {
            Form {
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

    init(log: NutritionLogRow) {
        self.log = log
        _loggedAt = State(initialValue: log.logged_at)
        _mealCategory = State(initialValue: MealCategory(rawValue: log.meal_type ?? "") ?? .lunch)
        let first = log.nutrition_log_items?.first
        let g = first?.grams ?? first?.serving_amount ?? 100
        _gramsText = State(initialValue: String(format: "%.0f", max(g, 1)))
        _quantity = State(initialValue: max(first?.quantity ?? 1, 0.01))
        _notesText = State(initialValue: log.notes ?? "")
    }

    private var singleItem: NutritionLogItemRow? {
        guard let items = log.nutrition_log_items, items.count == 1 else { return nil }
        return items.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let item = singleItem {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.headline)
                            if let b = item.brand, !b.isEmpty {
                                Text(b)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if log.nutrition_log_items == nil || log.nutrition_log_items?.isEmpty == true {
                        Text("No food line items on this entry.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("This meal has several foods.")
                            Text("Use the pencil next to each food on the meal list to edit portions. Here you can change time, meal type, and notes.")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                if let item = singleItem {
                    Section {
                        NutritionFavoriteToggleRow(candidate: FoodCandidateDTO(fromLoggedItem: item))
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
