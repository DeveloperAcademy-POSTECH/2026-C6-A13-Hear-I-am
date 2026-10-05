import SwiftUI

/// A transient summary owned by the current experiment; nothing is written to disk.
struct SessionSummary: View {
    let session: StudySession
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LabCard {
                Text("\(session.status == .completed ? "완료" : "중단") · \(session.answeredCount)/\(session.plannedCount)회 응답").font(.headline)
                Text("결과는 이 화면에서만 확인할 수 있어요. 닫으면 사라져요.").font(.subheadline).foregroundStyle(.secondary)
                if session.context.isPreview { Label("미리보기 · 실제 진동 없음", systemImage: "eye").font(.caption).foregroundStyle(Theme.amber) }
                Text("\(session.context.placement) · \(session.context.activity) · 세기 \(Int(session.context.gain * 100))%").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(session.sets.enumerated()), id: \.offset) { index, set in
                let stats = session.statistics(block: index)
                LabCard {
                    HStack { CodeBadge(code: set.code); VStack(alignment: .leading) { Text(set.name).font(.headline); Text("v\(set.revision) · \(index + 1)번째 세트").font(.caption).foregroundStyle(.secondary) } }
                    HStack {
                        Metric(value: percent(stats.accuracy), label: "전체 정답률")
                        Metric(value: percent(stats.firstPlayAccuracy), label: "첫 재생 성공률")
                    }
                    Text("응답 \(stats.scored.count)회 · 정답 \(stats.correct)회 · 재재생 \(stats.replays)회").font(.subheadline)
                    Text("실패·중단 \(stats.failures)건 / 건너뜀 \(stats.skipped)회는 정답률에서 제외").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ForEach(Direction.allCases) { direction in
                        HStack { Text("\(direction.arrow) \(direction.title)"); Spacer(); Text(percent(stats.accuracy(for: direction))).monospacedDigit() }.font(.subheadline)
                    }
                    ConfusionTable(stats: stats)
                    if let rating = session.ratings.first(where: { $0.block == index }) {
                        Divider()
                        Text("편안함 \(rating.comfort)/5 · 확신 \(rating.confidence)/5 · 집중 부담 \(rating.effort)/5").font(.subheadline)
                        if !rating.note.isEmpty { Text(rating.note).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            Text("모르겠음은 오답으로 집계해요. 첫 재생 성공률은 전체 응답 중 재재생 없이 맞힌 비율이에요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ConfusionTable: View {
    let stats: StudyStatistics
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("혼동표 · 행은 정답, 열은 응답").font(.caption.bold())
            ScrollView(.horizontal) {
                Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow { Text("정답↓"); ForEach(Direction.allCases) { Text($0.title) }; Text("모름") }.foregroundStyle(.secondary)
                    ForEach(Direction.allCases) { expected in
                        GridRow {
                            Text(expected.title).foregroundStyle(.secondary)
                            ForEach(Direction.allCases) { answer in
                                Text("\(stats.confusion(expected: expected, answered: answer))").foregroundStyle(expected == answer ? Theme.accent : .primary)
                                    .accessibilityLabel("정답 \(expected.title), 응답 \(answer.title), \(stats.confusion(expected: expected, answered: answer))회")
                            }
                            Text("\(stats.confusion(expected: expected, answered: nil))").accessibilityLabel("정답 \(expected.title), 모르겠음 \(stats.confusion(expected: expected, answered: nil))회")
                        }
                    }
                }.font(.subheadline.monospacedDigit()).padding(.vertical, 4)
            }
        }
    }
}
