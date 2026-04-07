//
//  NutritionView.swift
//  HealthTracker
//

import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

// MARK: - Image resize

extension UIImage {
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
    }

    @objc private func cancelTapped() {
        delegate?.didCancel()
    }

    private func startSession() {
        let session = AVCaptureSession()
        self.session = session
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

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
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let s = obj.stringValue else { return }
        session?.stopRunning()
        delegate?.didScan(code: s)
    }
}

// MARK: - Main view

struct NutritionView: View {
    @StateObject private var nutritionManager = NutritionManager.shared
    @AppStorage("syncNutritionToHealthKit") private var syncNutritionToHealthKit = true
    @State private var showingLogSheet = false
    @State private var editingLog: NutritionLogRow?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let t = nutritionManager.todayTotals
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today")
                            .font(.headline)
                        HStack {
                            macroChip("Cal", value: Int(t.calories.rounded()), unit: "kcal")
                            macroChip("P", value: Int(t.protein.rounded()), unit: "g")
                            macroChip("C", value: Int(t.carbs.rounded()), unit: "g")
                            macroChip("F", value: Int(t.fat.rounded()), unit: "g")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Meals") {
                    if nutritionManager.logs.isEmpty {
                        Text("No meals logged today.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(nutritionManager.logs) { log in
                            Button {
                                editingLog = log
                            } label: {
                                NutritionLogRowView(log: log)
                            }
                            .buttonStyle(.plain)
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
                    Button {
                        showingLogSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Toggle("Health", isOn: $syncNutritionToHealthKit)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("Sync nutrition to Apple Health")
                }
            }
            .sheet(isPresented: $showingLogSheet) {
                LogFoodSheet(syncToHealthKit: syncNutritionToHealthKit)
            }
            .sheet(item: $editingLog) { log in
                EditNutritionLogSheet(log: log)
            }
            .task {
                let cal = Calendar.current
                let start = cal.startOfDay(for: Date())
                let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
                await nutritionManager.loadLogs(from: start, to: end)
            }
            .refreshable {
                let cal = Calendar.current
                let start = cal.startOfDay(for: Date())
                let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
                await nutritionManager.loadLogs(from: start, to: end)
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
        .frame(maxWidth: .infinity)
    }
}

struct NutritionLogRowView: View {
    let log: NutritionLogRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if let items = log.nutrition_log_items {
                ForEach(items) { item in
                    HStack {
                        Text(item.name)
                            .font(.body)
                        if let b = item.brand, !b.isEmpty {
                            Text("· \(b)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(item.calories.rounded())) kcal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
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
    @State private var gramsText = "100"
    @State private var loggedAt = Date()
    @State private var photoJPEG: Data?
    @State private var pickedItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var pendingSource = "manual"
    @State private var pendingBarcode: String?
    @State private var mealCategory: MealCategory = .lunch

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

                DatePicker("Time", selection: $loggedAt, displayedComponents: [.date, .hourAndMinute])
                    .padding(.horizontal)

                Picker("Meal", selection: $mealCategory) {
                    ForEach(MealCategory.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingScanner) {
                ZStack {
                    BarcodeScannerView(
                        onCode: { code in
                            showingScanner = false
                            Task { await runBarcode(code) }
                        },
                        onCancel: { showingScanner = false }
                    )
                    .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showingCamera) {
                ImagePickerRepresentable(imageData: $photoJPEG)
                    .ignoresSafeArea()
            }
            .sheet(item: $selectedCandidate) { c in
                ConfirmFoodSheet(
                    candidate: c,
                    gramsText: $gramsText,
                    loggedAt: $loggedAt,
                    mealCategory: $mealCategory,
                    syncToHealthKit: syncToHealthKit,
                    source: pendingSource,
                    barcodeRaw: pendingBarcode,
                    photoJPEG: pendingSource == "photo" ? photoJPEG : nil,
                    onDone: {
                        selectedCandidate = nil
                        dismiss()
                    }
                )
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
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
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
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
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
                    if let data = try? await new.loadTransferable(type: Data.self) {
                        if let ui = UIImage(data: data) {
                            photoJPEG = ui.ht_resized(maxDimension: 800).jpegData(compressionQuality: 0.7)
                        }
                    }
                }
            }
            Button {
                showingCamera = true
            } label: {
                Label("Take photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }
            .padding(.horizontal)
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
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            candidateList
        }
    }

    private var candidateList: some View {
        List(candidates) { c in
            Button {
                gramsText = String(format: "%.0f", c.grams ?? 100)
                pendingSource = mode == .barcode ? "barcode" : (mode == .photo ? "photo" : "manual")
                selectedCandidate = c
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let b = c.brand, !b.isEmpty {
                        Text(b)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Int(c.calories.rounded())) kcal · P \(Int(c.protein_g))g · C \(Int(c.carb_g))g · F \(Int(c.fat_g))g")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
        defer { isLookingUp = false }
        guard let res = await nutritionManager.lookupSearch(q) else {
            notice = nutritionManager.errorMessage
            candidates = []
            return
        }
        candidates = res.candidates
        notice = res.notice
        pendingSource = "manual"
        pendingBarcode = nil
    }

    private func runBarcode(_ code: String) async {
        isLookingUp = true
        notice = nil
        defer { isLookingUp = false }
        guard let res = await nutritionManager.lookupBarcode(code) else {
            notice = nutritionManager.errorMessage
            candidates = []
            return
        }
        candidates = res.candidates
        notice = res.notice
        pendingSource = "barcode"
        pendingBarcode = code
    }

    private func runPhoto() async {
        guard let jpeg = photoJPEG else { return }
        isLookingUp = true
        notice = nil
        defer { isLookingUp = false }
        guard let res = await nutritionManager.lookupPhoto(imageJPEG: jpeg) else {
            notice = nutritionManager.errorMessage
            candidates = []
            return
        }
        candidates = res.candidates
        notice = res.notice
        pendingSource = "photo"
        pendingBarcode = nil
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

struct ConfirmFoodSheet: View {
    let candidate: FoodCandidateDTO
    @Binding var gramsText: String
    @Binding var loggedAt: Date
    @Binding var mealCategory: MealCategory
    let syncToHealthKit: Bool
    let source: String
    let barcodeRaw: String?
    let photoJPEG: Data?
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(candidate.name)) {
                    if let b = candidate.brand, !b.isEmpty {
                        Text(b)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Grams (basis for scaling)", text: $gramsText)
                        .keyboardType(.decimalPad)
                }
                Section("Meal") {
                    Picker("Category", selection: $mealCategory) {
                        ForEach(MealCategory.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                }
                Section("Nutrition (scaled)") {
                    let scaled = scaledCandidate
                    LabeledContent("Calories") { Text("\(Int(scaled.calories.rounded())) kcal") }
                    LabeledContent("Protein") { Text("\(Int(scaled.protein_g.rounded())) g") }
                    LabeledContent("Carbs") { Text("\(Int(scaled.carb_g.rounded())) g") }
                    LabeledContent("Fat") { Text("\(Int(scaled.fat_g.rounded())) g") }
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

    private var scaledCandidate: FoodCandidateDTO {
        let g = Double(gramsText.replacingOccurrences(of: ",", with: ".")) ?? 100
        return candidate.scaled(gramsEaten: max(g, 1))
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let input = NutritionManager.MealSaveInput(
            source: source,
            mealType: mealCategory.rawValue,
            barcodeRaw: barcodeRaw,
            photoJPEG: photoJPEG,
            loggedAt: loggedAt,
            candidate: scaledCandidate
        )
        let ok = await nutritionManager.saveMeal(input, syncToHealthKit: syncToHealthKit)
        if ok {
            dismiss()
            onDone()
        }
    }
}

// MARK: - Edit logged meal

private struct EditNutritionLogSheet: View {
    let log: NutritionLogRow
    @Environment(\.dismiss) private var dismiss
    @StateObject private var nutritionManager = NutritionManager.shared
    @State private var loggedAt: Date
    @State private var mealCategory: MealCategory
    @State private var gramsText: String
    @State private var isSaving = false

    init(log: NutritionLogRow) {
        self.log = log
        _loggedAt = State(initialValue: log.logged_at)
        _mealCategory = State(initialValue: MealCategory(rawValue: log.meal_type ?? "") ?? .lunch)
        let first = log.nutrition_log_items?.first
        let g = first?.grams ?? first?.serving_amount ?? 100
        _gramsText = State(initialValue: String(format: "%.0f", max(g, 1)))
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
                        Text(
                            "This entry has multiple foods. You can change the time and meal type only."
                        )
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
                        TextField("Grams", text: $gramsText)
                            .keyboardType(.decimalPad)
                    }
                    if let p = scaledPreview {
                        Section("Nutrition (scaled)") {
                            LabeledContent("Calories") { Text("\(Int(p.calories.rounded())) kcal") }
                            LabeledContent("Protein") { Text("\(Int(p.protein.rounded())) g") }
                            LabeledContent("Carbs") { Text("\(Int(p.carbs.rounded())) g") }
                            LabeledContent("Fat") { Text("\(Int(p.fat.rounded())) g") }
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
                Section {
                    Text(
                        "Edits are saved to your account. Apple Health is not updated when you edit an entry."
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

    private var scaledPreview: (calories: Double, protein: Double, carbs: Double, fat: Double)? {
        guard let item = singleItem else { return nil }
        let oldG = max(item.grams ?? item.serving_amount, 1)
        let parsed = Double(gramsText.replacingOccurrences(of: ",", with: "."))
        let newG = max(parsed ?? oldG, 1)
        let factor = newG / oldG
        return (
            item.calories * factor,
            item.protein_g * factor,
            item.carb_g * factor,
            item.fat_g * factor
        )
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let newGrams: Double? = {
            guard let item = singleItem else { return nil }
            let oldG = max(item.grams ?? item.serving_amount, 1)
            let parsed = Double(gramsText.replacingOccurrences(of: ",", with: "."))
            return max(parsed ?? oldG, 1)
        }()
        let ok = await nutritionManager.updateLog(
            log,
            loggedAt: loggedAt,
            mealCategory: mealCategory,
            newGramsForSingleItem: newGrams
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
        p.sourceType = .camera
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
                parent.imageData = img.ht_resized(maxDimension: 800).jpegData(compressionQuality: 0.7)
            }
            parent.dismiss()
        }
    }
}
