import Charts
import SwiftUI
import WayDetectCore

struct RecordsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            if store.sessions.isEmpty {
                ContentUnavailableView("저장한 기록이 없어요", systemImage: "chart.xyaxis.line", description: Text("측정 종료 후 ‘기록 저장’을 선택하세요."))
            }
            ForEach(store.sessions) { record in
                NavigationLink {
                    ResultsView(record: record).navigationTitle("측정 결과").navigationBarTitleDisplayMode(.inline)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.route.name).font(.headline)
                        Text(record.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        Text("\(record.outcome) · \(record.estimatedTotal) 추정 걸음").font(.subheadline)
                        if record.isDemo { Text("시뮬레이션").font(.caption).foregroundStyle(.orange) }
                    }
                }
            }.onDelete { offsets in let selected = offsets.map { store.sessions[$0] }; for record in selected { store.deleteSession(record) } }
            Section {
                NavigationLink("그래프 조작 예시") {
                    ResultsView(record: DemoRecord.make()).navigationTitle("그래프 예시").navigationBarTitleDisplayMode(.inline)
                }.accessibilityIdentifier("sample-results")
            }
        }.navigationTitle("기록")
    }
}

struct ResultsView: View {
    @EnvironmentObject private var store: AppStore
    let record: SessionRecord
    @State private var metric = 0
    @State private var spot = -1
    @State private var visibleSeconds = 20.0
    @State private var showSystem = true
    @State private var showEvents = true
    @State private var selectedTime: Double?
    @State private var scroll = 0.0
    @State private var exported: URL?
    private var filtered: [TraceSample] { record.samples.filter { spot == -1 || $0.spot == spot } }
    private var chartSamples: [TraceSample] {
        metric == 1 ? filtered.filter { $0.sensorValid && [.aiming, .walking, .arrival].contains($0.phase) } : filtered
    }
    private var selection: TraceSample? {
        guard let selectedTime else { return nil }; return chartSamples.min { abs($0.time - selectedTime) < abs($1.time - selectedTime) }
    }
    private var duration: Double { max(5, record.duration) }
    private var directionSegments: [UUID: Int] {
        var result: [UUID: Int] = [:], segment = 0
        var previous: TraceSample?
        for sample in chartSamples {
            if let previous, previous.revision != sample.revision || previous.spot != sample.spot
                || sample.time - previous.time > 0.5 || abs(sample.error - previous.error) > 180 { segment += 1 }
            result[sample.id] = segment; previous = sample
        }
        return result
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if record.isDemo { Label("시뮬레이션 · 실제 측정 아님", systemImage: "testtube.2").font(.subheadline.bold()).foregroundStyle(.orange) }
                Text(record.outcome).font(.title2.bold())
                HStack {
                    MetricTile(title: "실시간 추정", value: "\(record.estimatedTotal)걸음", symbol: "figure.walk")
                    MetricTile(title: "iOS 누적", value: "\(record.systemTotal)걸음", symbol: "iphone", color: .teal)
                }
                HStack {
                    MetricTile(title: "도착 스팟", value: "\(record.confirmedSpots)/\(record.route.spots.count)", symbol: "mappin.and.ellipse")
                    MetricTile(title: "측정 시간", value: record.duration.durationText, symbol: "clock")
                }
                Picker("그래프 종류", selection: $metric) {
                    Text("걸음").tag(0); Text("방향").tag(1); Text("움직임").tag(2)
                }.pickerStyle(.segmented).accessibilityIdentifier("chart-metric")
                Text(metric == 0 ? "세션 누적 걸음 비교" : metric == 1 ? "현재 정면에서 목표가 있는 방향" : "허리의 수직 움직임").font(.headline)
                if chartSamples.isEmpty {
                    ContentUnavailableView("표시할 표본이 없어요", systemImage: "waveform.path", description: Text("선택한 스팟에서 유효한 센서 기록이 없습니다."))
                } else {
                    chart.frame(height: 250).accessibilityIdentifier("measurement-chart")
                }
                if let s = selection {
                    Text("\(s.time.durationText) · 스팟 \(s.spot + 1) · 추정 \(s.estimatedTotal) / iOS \(s.systemTotal)걸음 · 목표 \(Angles.clock(s.error))시")
                        .font(.footnote).monospacedDigit().accessibilityIdentifier("chart-selection")
                } else { Text("좌우로 이동하고, 그래프를 눌러 시점을 선택하세요.").font(.footnote).foregroundStyle(.secondary) }
                DisclosureGroup("그래프 설정") {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("스팟", selection: $spot) {
                            Text("전체 스팟").tag(-1)
                            ForEach(Array(record.route.spots.enumerated()), id: \.offset) { i, s in Text("\(i + 1). \(s.name)").tag(i) }
                        }
                        Text("한 화면에 \(Int(min(duration, visibleSeconds)))초")
                        Slider(value: $visibleSeconds, in: 5...max(6, duration), step: 1).accessibilityLabel("그래프 표시 시간")
                        if metric == 0 { Toggle("iOS 걸음 겹쳐 보기", isOn: $showSystem) }
                        Toggle("스팟 기준선 표시", isOn: $showEvents)
                        Button("전체 구간 보기") { visibleSeconds = duration; scroll = 0 }.accessibilityIdentifier("chart-reset")
                    }.padding(.top, 12)
                }
                InfoNote(text: "추정 걸음은 허리 가속도 계산값입니다. iOS 걸음과 합산하거나 자동 교체하지 않습니다. 두 값의 차이만으로 어느 쪽이 정확한지 판단할 수 없습니다.")
                DisclosureGroup("이벤트 기록 \(record.events.count)개") {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(record.events) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(event.time.durationText) · \(event.kind) · 스팟 \(event.spot + 1)").font(.caption).foregroundStyle(.secondary)
                                Text(event.message).font(.subheadline)
                            }
                        }
                    }.padding(.top, 10)
                }
                HStack {
                    Button("JSON 내보내기") { exported = store.export(record, csv: false) }
                    Button("CSV 내보내기") { exported = store.export(record, csv: true) }
                }.buttonStyle(.bordered)
                if let exported { ShareLink("파일 공유", item: exported).buttonStyle(.borderedProminent) }
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground))
            .onChange(of: spot) { _, _ in scroll = filtered.first?.time ?? 0; selectedTime = nil }
            .onChange(of: metric) { _, _ in selectedTime = nil }
    }
    private var chart: some View {
        let segments = directionSegments
        return Chart {
            ForEach(chartSamples) { s in
                if metric == 0 {
                    LineMark(x: .value("초", s.time), y: .value("걸음", s.estimatedTotal), series: .value("종류", "실시간 추정"))
                        .foregroundStyle(by: .value("종류", "실시간 추정")).interpolationMethod(.stepEnd)
                    if showSystem {
                        LineMark(x: .value("초", s.time), y: .value("걸음", s.systemTotal), series: .value("종류", "iOS"))
                            .foregroundStyle(by: .value("종류", "iOS")).interpolationMethod(.stepEnd)
                    }
                } else if metric == 1 {
                    LineMark(x: .value("초", s.time), y: .value("목표 방향", s.error), series: .value("기준", "\(segments[s.id] ?? 0)"))
                        .foregroundStyle(.indigo)
                        .accessibilityLabel("\(s.time.durationText), 현재 정면에서 목표 방향")
                        .accessibilityValue("\(Angles.clock(s.error))시")
                } else {
                    LineMark(x: .value("초", s.time), y: .value("가속도 g", s.verticalAcceleration))
                        .foregroundStyle(.indigo)
                }
            }
            if showEvents {
                ForEach(record.events.filter { $0.kind == "12시 설정" && (spot == -1 || $0.spot == spot) }) { event in
                    RuleMark(x: .value("기준 설정", event.time)).foregroundStyle(.orange.opacity(0.5)).lineStyle(StrokeStyle(dash: [4, 4]))
                }
            }
            if let selectedTime { RuleMark(x: .value("선택", selectedTime)).foregroundStyle(.secondary) }
        }
        .chartForegroundStyleScale(["실시간 추정": Color.indigo, "iOS": Color.teal])
        .chartLegend(metric == 0 ? .visible : .hidden)
        .chartXScale(domain: 0...duration)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            if metric == 1 {
                AxisMarks(values: [-180.0, -90.0, 0.0, 90.0, 180.0]) { value in
                    AxisGridLine(); AxisTick()
                    AxisValueLabel { if let d = value.as(Double.self) { Text("\(Angles.clock(d))시") } }
                }
            } else { AxisMarks(position: .leading) }
        }
        .chartXAxisLabel("측정 시간 (초)")
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: min(duration, visibleSeconds))
        .chartScrollPosition(x: $scroll)
        .chartXSelection(value: $selectedTime)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
        }
    }
    private var yDomain: ClosedRange<Double> {
        if metric == 1 { return -180...180 }
        if metric == 2 {
            let limit = max(0.3, (filtered.map { abs($0.verticalAcceleration) }.max() ?? 0) * 1.1)
            return -limit...limit
        }
        return 0...max(5, Double(max(record.estimatedTotal, record.systemTotal)) + 1)
    }
}
