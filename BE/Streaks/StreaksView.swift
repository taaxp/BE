import SwiftUI
import BECore

/// Streaks: your overall streak, level, daily quests, habits and badges.
struct StreaksView: View {
    @Environment(AppModel.self) private var model
    @State private var addingHabit = false

    var body: some View {
        let streak = model.state.streak(today: model.day)
        let level = model.state.level

        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.gridSpacing) {
                    HStack(spacing: Theme.gridSpacing) {
                        streakCard(streak)
                        levelCard(level)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    QuestsWidget().widgetCard()

                    habitsCard

                    badgesCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Streaks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.state.restDays.contains(model.day) ? "Undo rest day" : "Rest day") { model.toggleRestDay() }
                }
            }
            .sheet(isPresented: $addingHabit) { AddHabitView() }
        }
    }

    private func streakCard(_ s: StreakStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 34))
                .foregroundStyle(s.state == .secured ? .orange : .orange.opacity(0.45))
                .symbolEffect(.bounce, value: s.current)
            Text("\(s.current)").font(.metric(.largeTitle)).contentTransition(.numericText())
            Text("day streak").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("Best \(s.best) · \(model.state.freezes) freeze\(model.state.freezes == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
            if model.state.restDays.contains(model.day) {
                Text("Rest day: your streak is safe.").font(.caption).foregroundStyle(.green)
            }
        }
        .widgetCard()
        .accessibilityElement(children: .combine)
    }

    private func levelCard(_ l: Level) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Circle().stroke(.yellow.opacity(0.2), lineWidth: 6)
                Circle().trim(from: 0, to: l.fraction).stroke(.yellow, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(l.number)").font(.metric(.headline))
            }
            .frame(width: 44, height: 44)
            Text(l.name).font(.title3.weight(.semibold))
            Text("\(l.progressXP) / \(l.levelXP) XP").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(model.state.totalXP) XP all time").font(.caption).foregroundStyle(.secondary)
        }
        .widgetCard()
        .accessibilityElement(children: .combine)
    }

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetHeader(title: "Habits", symbol: "checklist", tint: .blue)
                Spacer()
                Button { addingHabit = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .accessibilityLabel("Add habit")
            }
            if model.state.habits.isEmpty {
                Text("Add a habit to start building streaks.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(model.state.habits) { habit in
                HabitRow(habit: habit)
                if habit.id != model.state.habits.last?.id { Divider() }
            }
        }
        .widgetCard()
    }

    private var badgesCard: some View {
        let earned = Set(model.state.earnedBadges)
        return VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Badges", symbol: "rosette", tint: .purple)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 14) {
                ForEach(BadgeCatalogue.all.map { $0.badge }) { b in
                    let has = earned.contains(b.id)
                    VStack(spacing: 6) {
                        Image(systemName: b.symbol)
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .background(has ? Color.purple.opacity(0.15) : Color(.tertiarySystemFill), in: .circle)
                            .foregroundStyle(has ? .purple : .secondary)
                        Text(b.title).font(.caption2.weight(.medium)).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .opacity(has ? 1 : 0.55)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(b.title), \(has ? "earned" : "locked"). \(b.detail)")
                }
            }
        }
        .widgetCard()
    }
}

struct HabitRow: View {
    @Environment(AppModel.self) private var model
    let habit: Habit

    var body: some View {
        let done = model.state.isHabitDone(habit, on: model.day)
        let streak = model.state.habitStreak(habit, today: model.day)
        let scheduled = habit.isScheduled(on: model.day)
        HStack(spacing: 12) {
            Image(systemName: habit.symbol).frame(width: 28).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name).font(.body)
                HStack(spacing: 6) {
                    Label("\(streak.current)", systemImage: "flame.fill").foregroundStyle(.orange)
                    if case .automatic = habit.completion { Text("Auto from Apple Health") }
                    if !scheduled { Text("Not today") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.toggleHabit(habit)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!scheduled || isAuto)
            .sensoryFeedback(.success, trigger: done)
            .accessibilityLabel(done ? "Done" : "Mark done")
        }
        .contextMenu {
            Button("Remove habit", systemImage: "trash", role: .destructive) { model.removeHabit(habit) }
        }
    }

    private var isAuto: Bool {
        if case .automatic = habit.completion { true } else { false }
    }
}

struct AddHabitView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var weekdays: Set<Int> = Set(1...7)

    private let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Suggestions") {
                    ForEach(Habit.suggestions.filter { s in !model.state.habits.contains { $0.name == s.name } }) { s in
                        Button {
                            model.addHabit(Habit(name: s.name, symbol: s.symbol, completion: s.completion, isActivity: s.isActivity))
                            dismiss()
                        } label: {
                            Label(s.name, systemImage: s.symbol)
                        }
                    }
                }
                Section("Your own") {
                    TextField("e.g. Read for 10 minutes", text: $name)
                    HStack {
                        ForEach(1...7, id: \.self) { d in
                            let on = weekdays.contains(d)
                            Button(dayLetters[d - 1]) {
                                if on { weekdays.remove(d) } else { weekdays.insert(d) }
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? .blue : .gray)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Button("Add habit") {
                        model.addHabit(Habit(name: name, symbol: "checkmark.circle", completion: .manual, weekdays: weekdays))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || weekdays.isEmpty)
                }
            }
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}
