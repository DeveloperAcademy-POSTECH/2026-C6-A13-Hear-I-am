import SwiftUI
import RoomPlan
import ARKit
import UIKit
import Combine

private struct StagePoint: Equatable {
    var x: Double
    var y: Double
}

private enum StageEdge: String, CaseIterable, Hashable {
    case front
    case left
    case right
    case back

    var label: String {
        switch self {
        case .front: "앞"
        case .left: "좌"
        case .right: "우"
        case .back: "뒤"
        }
    }

    var icon: String {
        switch self {
        case .front: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .back: "arrow.up"
        }
    }
}

struct LegacyStageView: View {
    @State private var stageWidth = 8.0
    @State private var stageDepth = 6.0
    @State private var startPoint: StagePoint?
    @State private var isScanning = false
    @State private var scanSuggestion: CGSize?
    @State private var scanError: String?
    @State private var dangerZoneWidth = 1.0
    @State private var dangerEdges = Set(StageEdge.allCases)

    private let background = Color(red: 0.055, green: 0.075, blue: 0.105)
    private let panel = Color(red: 0.10, green: 0.13, blue: 0.17)
    private let accent = Color(red: 0.41, green: 0.91, blue: 0.76)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if geometry.size.width >= 700 {
                    tabletLayout
                } else {
                    phoneLayout
                }
            }
        }
        .background(background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $isScanning) {
            RoomScannerView { result in
                isScanning = false
                switch result {
                case .success(let size): scanSuggestion = size
                case .failure(let message): scanError = message
                }
            }
        }
        .alert("스캔 결과", isPresented: Binding(
            get: { scanSuggestion != nil },
            set: { if !$0 { scanSuggestion = nil } }
        )) {
            Button("무대 크기에 적용") {
                if let size = scanSuggestion {
                    stageWidth = Double(size.width)
                    stageDepth = Double(size.height)
                    startPoint = nil
                }
                scanSuggestion = nil
            }
            Button("취소", role: .cancel) { scanSuggestion = nil }
        } message: {
            if let size = scanSuggestion {
                Text(String(format: "감지한 바닥의 범위는 약 %.1f × %.1f m입니다. 무대 경계와 일치하는지 확인한 뒤 적용하세요.", size.width, size.height))
            }
        }
        .alert("스캔을 완료하지 못했습니다", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        )) {
            Button("확인") { scanError = nil }
        } message: { Text(scanError ?? "") }
    }

    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            stageCard
            safetyCard
            positionCard
            dimensionsCard
            scanCard
        }
        .padding(20)
        .padding(.bottom, 24)
    }

    private var tabletLayout: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            HStack(alignment: .top, spacing: 24) {
                stageCard
                    .frame(maxWidth: .infinity)
                VStack(spacing: 20) {
                    safetyCard
                    positionCard
                    dimensionsCard
                    scanCard
                }
                .frame(width: 340)
            }
        }
        .frame(maxWidth: 1180)
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STAGEVISION  ·  MVP")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(accent)
            Text("무대 위 시작 위치")
                .font(.system(size: 32, weight: .bold))
            Text("무대 크기를 정하고, 평면도에서 무용수의 시작 지점을 선택하세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("무대 평면도", systemImage: "square.grid.3x3.fill")
                    .font(.headline)
                Spacer()
                Text("1칸 = 1m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("무대 뒤쪽")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            StageGrid(
                width: stageWidth,
                depth: stageDepth,
                dangerZoneWidth: dangerZoneWidth,
                dangerEdges: dangerEdges,
                point: $startPoint,
                accent: accent
            )
                .aspectRatio(stageWidth / stageDepth, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("무대 평면도, 너비 \(stageWidth.formatted())미터, 깊이 \(stageDepth.formatted())미터. \(dangerSummary)")
            Text("관객석 · 무대 앞쪽")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Circle().fill(.orange).frame(width: 10, height: 10)
                Text("주황색: \(dangerSummary)")
                    .font(.caption.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("가장자리 위험 구역", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 8) {
                Text("위험 구역 폭")
                    .font(.subheadline.weight(.semibold))
                Picker("위험 구역 폭", selection: $dangerZoneWidth) {
                    Text("1.0m").tag(1.0)
                    Text("1.5m").tag(1.5)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("적용할 가장자리")
                    .font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(StageEdge.allCases, id: \.self) { edge in
                        let isSelected = dangerEdges.contains(edge)
                        Button {
                            if isSelected {
                                dangerEdges.remove(edge)
                            } else {
                                dangerEdges.insert(edge)
                            }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Label(edge.label, systemImage: edge.icon)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    isSelected ? Color.orange.opacity(0.9) : Color.white.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .foregroundStyle(isSelected ? background : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("무대 \(edge.label)쪽 위험 구역")
                        .accessibilityValue(isSelected ? "적용" : "미적용")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private var positionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.dance")
                    .foregroundStyle(accent)
                Text("무용수 시작 위치")
                    .font(.headline)
                Spacer()
                if startPoint != nil {
                    Button("지우기") { startPoint = nil }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            if let startPoint {
                Text(String(format: "왼쪽에서 %.1f m · 무대 앞에서 %.1f m", startPoint.x, startPoint.y))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.updatesFrequently)
                let matchedEdges = dangerEdgesContaining(startPoint)
                if !matchedEdges.isEmpty {
                    Label("주의: 시작 위치가 \(edgeNames(matchedEdges))쪽 \(dangerWidthText)m 위험 구역에 있습니다.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            } else {
                Text("평면도를 터치해 시작 위치를 표시하세요.")
                    .foregroundStyle(.secondary)
            }
            Text("이 표시는 수동으로 지정한 위치입니다. 이동 후 위치를 자동 추적하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private var dangerSummary: String {
        guard !dangerEdges.isEmpty else { return "선택된 위험 가장자리 없음" }
        return "\(edgeNames(StageEdge.allCases.filter(dangerEdges.contains)))쪽 가장자리 \(dangerWidthText)m 위험 구역"
    }

    private var dangerWidthText: String {
        String(format: "%.1f", dangerZoneWidth)
    }

    private func edgeNames(_ edges: [StageEdge]) -> String {
        edges.map(\.label).joined(separator: "·")
    }

    private func dangerEdgesContaining(_ point: StagePoint) -> [StageEdge] {
        StageEdge.allCases.filter { edge in
            guard dangerEdges.contains(edge) else { return false }
            return switch edge {
            case .front: point.y <= dangerZoneWidth
            case .left: point.x <= dangerZoneWidth
            case .right: point.x >= stageWidth - dangerZoneWidth
            case .back: point.y >= stageDepth - dangerZoneWidth
            }
        }
    }

    private var dimensionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("무대 크기", systemImage: "ruler")
                .font(.headline)
            Text("무대 앞을 아래쪽으로 놓고 입력하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            dimensionRow("너비", value: $stageWidth)
            dimensionRow("깊이", value: $stageDepth)
            Button {
                swap(&stageWidth, &stageDepth)
                startPoint = nil
            } label: {
                Label("너비와 깊이 바꾸기", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(accent)
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private func dimensionRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Button {
                value.wrappedValue = max(2, ((value.wrappedValue - 0.1) * 10).rounded() / 10)
                startPoint = nil
            } label: { Image(systemName: "minus.circle.fill") }
                .accessibilityLabel("\(label) 0.1미터 줄이기")
            Text(String(format: "%.1f m", value.wrappedValue))
                .monospacedDigit()
                .frame(width: 70)
            Button {
                value.wrappedValue = min(30, ((value.wrappedValue + 0.1) * 10).rounded() / 10)
                startPoint = nil
            } label: { Image(systemName: "plus.circle.fill") }
                .accessibilityLabel("\(label) 0.1미터 늘리기")
        }
        .font(.body.weight(.medium))
        .buttonStyle(.plain)
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("LiDAR로 크기 가져오기", systemImage: "camera.viewfinder")
                .font(.headline)
            Text("LiDAR를 지원하는 iPhone 또는 iPad에서 바닥을 스캔해 크기를 제안합니다. 열린 무대에서는 감지가 불완전할 수 있으므로 실제 무대 경계를 확인하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                isScanning = true
            } label: {
                Label("무대 스캔 시작", systemImage: "viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(background)
            }
            .disabled(!RoomCaptureSession.isSupported)
            if !RoomCaptureSession.isSupported {
                Text("이 기기에서는 RoomPlan을 사용할 수 없습니다. 위에서 무대 크기를 직접 입력하세요.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct StageGrid: View {
    let width: Double
    let depth: Double
    let dangerZoneWidth: Double
    let dangerEdges: Set<StageEdge>
    @Binding var point: StagePoint?
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.07, green: 0.21, blue: 0.23))
                Canvas { context, canvasSize in
                    let horizontalDanger = min(canvasSize.width, canvasSize.width * dangerZoneWidth / width)
                    let verticalDanger = min(canvasSize.height, canvasSize.height * dangerZoneWidth / depth)
                    let dangerColor = Color.orange.opacity(0.72)

                    if dangerEdges.contains(.left) {
                        context.fill(Path(CGRect(x: 0, y: 0, width: horizontalDanger, height: canvasSize.height)), with: .color(dangerColor))
                    }
                    if dangerEdges.contains(.right) {
                        context.fill(Path(CGRect(x: canvasSize.width - horizontalDanger, y: 0, width: horizontalDanger, height: canvasSize.height)), with: .color(dangerColor))
                    }
                    if dangerEdges.contains(.back) {
                        context.fill(Path(CGRect(x: 0, y: 0, width: canvasSize.width, height: verticalDanger)), with: .color(dangerColor))
                    }
                    if dangerEdges.contains(.front) {
                        context.fill(Path(CGRect(x: 0, y: canvasSize.height - verticalDanger, width: canvasSize.width, height: verticalDanger)), with: .color(dangerColor))
                    }

                    var grid = Path()
                    for meter in 0...Int(width) {
                        let x = canvasSize.width * CGFloat(Double(meter) / width)
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    }
                    for meter in 0...Int(depth) {
                        let y = canvasSize.height * CGFloat(Double(meter) / depth)
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.22)), lineWidth: 1)
                }
                if let point {
                    Circle()
                        .fill(accent)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(color: accent.opacity(0.7), radius: 9)
                        .position(x: size.width * point.x / width,
                                  y: size.height * (1 - point.y / depth))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                point = StagePoint(
                    x: min(width, max(0, Double(location.x / size.width) * width)),
                    y: min(depth, max(0, (1 - Double(location.y / size.height)) * depth))
                )
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}

enum ScanResult {
    case success(CGSize)
    case failure(String)
}

private enum ProjectedLineKind {
    case grid
    case boundary
}

private struct ProjectedGridSegment {
    let start: CGPoint
    let end: CGPoint
    let kind: ProjectedLineKind
}

private struct RoomScannerView: View {
    let onFinish: (ScanResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = RoomScannerController()

    var body: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureContainer(controller: controller)
                .ignoresSafeArea()
            LiveStageGridOverlay(controller: controller)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Circle().fill(.mint).frame(width: 8, height: 8)
                    Text("1m 격자")
                    Circle().fill(.orange).frame(width: 8, height: 8)
                    Text("감지된 바닥 외곽")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                Text(controller.status)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("취소") {
                        controller.cancel()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    Button("스캔 완료") { controller.finish() }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.isProcessing)
                }
            }
            .padding(20)
        }
        .onAppear { controller.onResult = onFinish }
    }
}

private struct LiveStageGridOverlay: View {
    @ObservedObject var controller: RoomScannerController

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, _ in
                for segment in controller.projectedGridSegments {
                    var path = Path()
                    path.move(to: segment.start)
                    path.addLine(to: segment.end)
                    switch segment.kind {
                    case .grid:
                        context.stroke(path, with: .color(.mint.opacity(0.9)), lineWidth: 1.5)
                    case .boundary:
                        context.stroke(path, with: .color(.orange), lineWidth: 4)
                    }
                }
            }
            .onAppear {
                controller.updateViewportSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                controller.updateViewportSize(newSize)
            }
        }
    }
}

@MainActor
final class RoomScannerController: NSObject, ObservableObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    @Published var status = "바닥을 천천히 비추면 1m 좌표 격자가 나타납니다."
    @Published var isProcessing = false
    @Published fileprivate var projectedGridSegments: [ProjectedGridSegment] = []
    var onResult: ((ScanResult) -> Void)?
    weak var captureView: RoomCaptureView?
    private var latestFloor: CapturedRoom.Surface?
    private var viewportSize: CGSize = .zero
    private var displayLink: CADisplayLink?

    override init() { super.init() }
    required init?(coder: NSCoder) { super.init() }
    func encode(with coder: NSCoder) {}

    func start(_ view: RoomCaptureView) {
        captureView = view
        view.delegate = self
        view.captureSession.delegate = self
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        let displayLink = CADisplayLink(target: self, selector: #selector(refreshGridForCurrentFrame))
        displayLink.preferredFramesPerSecond = 20
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func updateViewportSize(_ size: CGSize) {
        viewportSize = size
        refreshProjectedGrid()
    }

    func finish() {
        isProcessing = true
        status = "스캔 결과를 처리하는 중입니다…"
        displayLink?.invalidate()
        displayLink = nil
        captureView?.captureSession.stop()
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        captureView?.captureSession.stop()
        onResult = nil
    }

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        updateLiveFloor(from: room)
    }

    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
        updateLiveFloor(from: room)
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            onResult?(.failure(error.localizedDescription))
            onResult = nil
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        displayLink?.invalidate()
        displayLink = nil
        if let error {
            onResult?(.failure(error.localizedDescription))
        } else if let floor = processedResult.floors.max(by: { floorArea($0) < floorArea($1) }) {
            let dimensions = [Double(floor.dimensions.x), Double(floor.dimensions.y), Double(floor.dimensions.z)]
                .sorted(by: >)
            let width = dimensions[0]
            let depth = dimensions[1]
            if width >= 1, depth >= 1 {
                onResult?(.success(CGSize(width: width, height: depth)))
            } else {
                onResult?(.failure("바닥의 크기를 확인할 수 없습니다. 직접 입력해 주세요."))
            }
        } else {
            onResult?(.failure("바닥을 감지하지 못했습니다. 직접 입력해 주세요."))
        }
        onResult = nil
    }

    private func floorArea(_ floor: CapturedRoom.Surface) -> Double {
        if floor.polygonCorners.count >= 3 {
            let polygon = floor.polygonCorners
            var twiceArea: Float = 0
            for index in polygon.indices {
                let next = polygon[(index + 1) % polygon.count]
                twiceArea += polygon[index].x * next.y - next.x * polygon[index].y
            }
            return Double(abs(twiceArea) / 2)
        }
        let dimensions = [Double(floor.dimensions.x), Double(floor.dimensions.y), Double(floor.dimensions.z)]
            .sorted(by: >)
        return dimensions[0] * dimensions[1]
    }

    private func updateLiveFloor(from room: CapturedRoom) {
        guard let floor = room.floors.max(by: { floorArea($0) < floorArea($1) }) else {
            return
        }
        latestFloor = floor
        status = floor.polygonCorners.count > 4
            ? "비정형 바닥 외곽과 1m 좌표 격자를 표시하고 있습니다."
            : "바닥 위에 1m 좌표 격자를 표시하고 있습니다."
        refreshProjectedGrid()
    }

    @objc private func refreshGridForCurrentFrame() {
        refreshProjectedGrid()
    }

    private func refreshProjectedGrid() {
        guard
            viewportSize.width > 0,
            viewportSize.height > 0,
            let floor = latestFloor,
            let frame = captureView?.captureSession.arSession.currentFrame
        else {
            projectedGridSegments = []
            return
        }

        let polygon = localPolygon(for: floor)
        guard polygon.count >= 3 else {
            projectedGridSegments = []
            return
        }

        let orientation = captureView?.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let camera = frame.camera
        var localSegments: [(SIMD2<Float>, SIMD2<Float>, ProjectedLineKind)] = []

        for index in polygon.indices {
            localSegments.append((polygon[index], polygon[(index + 1) % polygon.count], .boundary))
        }

        let minX = polygon.map(\.x).min() ?? 0
        let maxX = polygon.map(\.x).max() ?? 0
        let minY = polygon.map(\.y).min() ?? 0
        let maxY = polygon.map(\.y).max() ?? 0

        var x = minX + 1
        while x < maxX {
            let intersections = verticalIntersections(x: x, polygon: polygon)
            for pair in paired(intersections) {
                localSegments.append((SIMD2(x, pair.0), SIMD2(x, pair.1), .grid))
            }
            x += 1
        }

        var y = minY + 1
        while y < maxY {
            let intersections = horizontalIntersections(y: y, polygon: polygon)
            for pair in paired(intersections) {
                localSegments.append((SIMD2(pair.0, y), SIMD2(pair.1, y), .grid))
            }
            y += 1
        }

        projectedGridSegments = localSegments.compactMap { start, end, kind in
            guard
                let projectedStart = project(start, floor: floor, camera: camera, orientation: orientation),
                let projectedEnd = project(end, floor: floor, camera: camera, orientation: orientation)
            else { return nil }
            return ProjectedGridSegment(start: projectedStart, end: projectedEnd, kind: kind)
        }
    }

    private func localPolygon(for floor: CapturedRoom.Surface) -> [SIMD2<Float>] {
        let corners = floor.polygonCorners.map { SIMD2<Float>($0.x, $0.y) }
        if corners.count >= 3 { return corners }

        let halfWidth = floor.dimensions.x / 2
        let halfDepth = floor.dimensions.y / 2
        guard halfWidth > 0, halfDepth > 0 else { return [] }
        return [
            SIMD2(-halfWidth, -halfDepth),
            SIMD2(halfWidth, -halfDepth),
            SIMD2(halfWidth, halfDepth),
            SIMD2(-halfWidth, halfDepth)
        ]
    }

    private func project(
        _ localPoint: SIMD2<Float>,
        floor: CapturedRoom.Surface,
        camera: ARCamera,
        orientation: UIInterfaceOrientation
    ) -> CGPoint? {
        let world4 = floor.transform * SIMD4<Float>(localPoint.x, localPoint.y, 0, 1)
        let world = SIMD3<Float>(world4.x, world4.y, world4.z)
        let cameraPoint = camera.transform.inverse * SIMD4<Float>(world.x, world.y, world.z, 1)
        guard cameraPoint.z < 0 else { return nil }

        let projected = camera.projectPoint(world, orientation: orientation, viewportSize: viewportSize)
        guard projected.x.isFinite, projected.y.isFinite else { return nil }
        return projected
    }

    private func verticalIntersections(x: Float, polygon: [SIMD2<Float>]) -> [Float] {
        var values: [Float] = []
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            guard (a.x <= x && b.x > x) || (b.x <= x && a.x > x) else { continue }
            let ratio = (x - a.x) / (b.x - a.x)
            values.append(a.y + ratio * (b.y - a.y))
        }
        return values.sorted()
    }

    private func horizontalIntersections(y: Float, polygon: [SIMD2<Float>]) -> [Float] {
        var values: [Float] = []
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            guard (a.y <= y && b.y > y) || (b.y <= y && a.y > y) else { continue }
            let ratio = (y - a.y) / (b.y - a.y)
            values.append(a.x + ratio * (b.x - a.x))
        }
        return values.sorted()
    }

    private func paired(_ values: [Float]) -> [(Float, Float)] {
        stride(from: 0, to: values.count - 1, by: 2).map { (values[$0], values[$0 + 1]) }
    }
}

private struct RoomCaptureContainer: UIViewRepresentable {
    let controller: RoomScannerController

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        controller.start(view)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
