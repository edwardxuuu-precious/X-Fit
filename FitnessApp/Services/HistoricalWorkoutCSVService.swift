import Foundation
import SwiftData

struct HistoricalCSVPreview {
    let sessions: Int
    let exercises: Int
    let sets: Int
    let duplicateSessions: Int
}

struct HistoricalCSVImportSummary {
    let importedSessions: Int
    let skippedSessions: Int
    let createdExercises: Int
    let importedSets: Int
}

private struct HistoricalCSVRow {
    let line: Int
    let sessionID: String
    let date: Date
    let workout: String
    let durationMinutes: Int
    let workoutNotes: String
    let exercise: String
    let muscleGroup: String
    let equipment: String
    let setNumber: Int
    let weight: Double
    let volumeUnit: ExerciseVolumeUnit?
    let reps: Int
    let rir: Int?
    let startedAt: Date?
    let restDurationSeconds: Int?
    let exerciseNotes: String
}

enum HistoricalWorkoutCSVError: LocalizedError {
    case unreadableText
    case emptyFile
    case missingColumns([String])
    case invalidValue(line: Int, field: String)

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            return "CSV 不是可识别的 UTF-8 文本。"
        case .emptyFile:
            return "CSV 没有可导入的训练记录。"
        case let .missingColumns(columns):
            return "CSV 缺少字段：\(columns.joined(separator: ", "))"
        case let .invalidValue(line, field):
            return "CSV 第 \(line) 行的 \(field) 无法识别。"
        }
    }
}

@MainActor
enum HistoricalWorkoutCSVService {
    static let requiredColumns = [
        "session_id",
        "date",
        "workout",
        "exercise",
        "set",
        "weight_kg",
        "reps"
    ]

    static func preview(_ data: Data, in context: ModelContext) throws -> HistoricalCSVPreview {
        let rows = try decode(data)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let existing = Set(sessions.map(\.importIdentifier).filter { !$0.isEmpty })
        let existingSessionIDs = Set(sessions.map { $0.id.uuidString.lowercased() })
        let grouped = Dictionary(grouping: rows, by: \.sessionID)
        let duplicateCount = grouped.keys.filter {
            existing.contains(importIdentifier(for: $0))
                || existingSessionIDs.contains($0.lowercased())
        }.count
        return HistoricalCSVPreview(
            sessions: grouped.count,
            exercises: Set(rows.map { "\($0.sessionID)|\($0.exercise.lowercased())" }).count,
            sets: rows.count,
            duplicateSessions: duplicateCount
        )
    }

    static func importCSV(
        _ data: Data,
        into context: ModelContext
    ) throws -> HistoricalCSVImportSummary {
        let rows = try decode(data)
        let grouped = Dictionary(grouping: rows, by: \.sessionID)
        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let existingImportIDs = Set(existingSessions.map(\.importIdentifier).filter { !$0.isEmpty })
        let existingSessionIDs = Set(existingSessions.map { $0.id.uuidString.lowercased() })
        var exerciseModels = try context.fetch(FetchDescriptor<Exercise>())
        try validateExerciseIdentities(rows, against: exerciseModels)

        var importedSessions = 0
        var skippedSessions = 0
        var createdExercises = 0
        var importedSets = 0

        for sessionID in grouped.keys.sorted() {
            guard let sessionRows = grouped[sessionID], let first = sessionRows.first else { continue }
            let stableID = importIdentifier(for: sessionID)
            guard !existingImportIDs.contains(stableID),
                  !existingSessionIDs.contains(sessionID.lowercased()) else {
                skippedSessions += 1
                continue
            }

            let rowsByExercise = Dictionary(grouping: sessionRows, by: { $0.exercise.lowercased() })
            var exerciseInputs: [HistoricalExerciseInput] = []

            for key in rowsByExercise.keys.sorted() {
                guard let actionRows = rowsByExercise[key], let action = actionRows.first else { continue }
                let identities = Set(actionRows.map {
                    [
                        $0.muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        $0.equipment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        ($0.volumeUnit ?? .kilogram).rawValue
                    ].joined(separator: "|")
                })
                guard identities.count == 1 else {
                    throw HistoricalWorkoutCSVError.invalidValue(
                        line: action.line,
                        field: "exercise（同场同名动作的肌群、器械或计量单位不一致）"
                    )
                }
                let exercise: Exercise
                if let existing = exerciseModels.first(where: {
                    $0.name.caseInsensitiveCompare(action.exercise) == .orderedSame
                }) {
                    if let importedUnit = action.volumeUnit,
                       existing.volumeUnit != importedUnit {
                        throw HistoricalWorkoutCSVError.invalidValue(
                            line: action.line,
                            field: "volume_unit（与动作库现有单位冲突）"
                        )
                    }
                    let importedMuscleGroup = action.muscleGroup.isEmpty ? "其他" : action.muscleGroup
                    let importedEquipment = action.equipment.isEmpty ? "未记录" : action.equipment
                    guard ExerciseCatalogService.semanticallyCompatible(
                        existing,
                        muscleGroup: importedMuscleGroup,
                        equipment: importedEquipment,
                        volumeUnit: action.volumeUnit ?? .kilogram
                    ) else {
                        throw HistoricalWorkoutCSVError.invalidValue(
                            line: action.line,
                            field: "exercise（同名动作与动作库中的肌群、器械或计量单位冲突）"
                        )
                    }
                    exercise = existing
                } else {
                    let newExercise = Exercise(
                        name: action.exercise,
                        muscleGroup: action.muscleGroup.isEmpty ? "其他" : action.muscleGroup,
                        equipment: action.equipment.isEmpty ? "未记录" : action.equipment,
                        defaultRestSeconds: 90,
                        isBuiltIn: false,
                        notes: "",
                        volumeUnit: action.volumeUnit ?? .kilogram
                    )
                    ExerciseTerminologyService.stageCandidate(for: newExercise)
                    context.insert(newExercise)
                    exerciseModels.append(newExercise)
                    exercise = newExercise
                    createdExercises += 1
                }

                let orderedRows = actionRows.sorted { $0.setNumber < $1.setNumber }
                exerciseInputs.append(
                    HistoricalExerciseInput(
                        exerciseID: exercise.id,
                        sets: orderedRows.map {
                            HistoricalSetInput(
                                weight: $0.weight,
                                reps: $0.reps,
                                rir: $0.rir,
                                startedAt: $0.startedAt,
                                restDurationSeconds: $0.restDurationSeconds
                            )
                        },
                        performanceNotes: orderedRows
                            .map(\.exerciseNotes)
                            .first(where: { !$0.isEmpty }) ?? ""
                    )
                )
                importedSets += orderedRows.count
            }

            _ = try HistoricalWorkoutService.record(
                HistoricalWorkoutInput(
                    name: first.workout,
                    startedAt: first.date,
                    durationMinutes: first.durationMinutes,
                    notes: first.workoutNotes,
                    exercises: exerciseInputs,
                    importIdentifier: stableID
                ),
                in: context
            )
            importedSessions += 1
        }

        try context.save()
        return HistoricalCSVImportSummary(
            importedSessions: importedSessions,
            skippedSessions: skippedSessions,
            createdExercises: createdExercises,
            importedSets: importedSets
        )
    }

    /// Validate the complete file before the first insert/save. This makes an
    /// identity conflict fail atomically instead of importing earlier sessions
    /// and discovering the conflict later in the file.
    private static func validateExerciseIdentities(
        _ rows: [HistoricalCSVRow],
        against exercises: [Exercise]
    ) throws {
        let rowsByName = Dictionary(grouping: rows) {
            $0.exercise.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        for actionRows in rowsByName.values {
            guard let first = actionRows.first else { continue }
            let identities = Set(actionRows.map { row in
                let muscleGroup = row.muscleGroup.isEmpty ? "其他" : row.muscleGroup
                let equipment = row.equipment.isEmpty ? "未记录" : row.equipment
                return [
                    muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    equipment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    (row.volumeUnit ?? .kilogram).rawValue
                ].joined(separator: "|")
            })
            guard identities.count == 1 else {
                throw HistoricalWorkoutCSVError.invalidValue(
                    line: first.line,
                    field: "exercise（文件内同名动作的肌群、器械或计量单位不一致）"
                )
            }

            guard let existing = exercises.first(where: {
                $0.name.caseInsensitiveCompare(first.exercise) == .orderedSame
            }) else { continue }
            let muscleGroup = first.muscleGroup.isEmpty ? "其他" : first.muscleGroup
            let equipment = first.equipment.isEmpty ? "未记录" : first.equipment
            guard ExerciseCatalogService.semanticallyCompatible(
                existing,
                muscleGroup: muscleGroup,
                equipment: equipment,
                volumeUnit: first.volumeUnit ?? .kilogram
            ) else {
                throw HistoricalWorkoutCSVError.invalidValue(
                    line: first.line,
                    field: "exercise（同名动作与动作库中的肌群、器械或计量单位冲突）"
                )
            }
        }
    }

    private static func decode(_ data: Data) throws -> [HistoricalCSVRow] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw HistoricalWorkoutCSVError.unreadableText
        }
        let table = parseCSV(text)
        guard let rawHeaders = table.first, table.count > 1 else {
            throw HistoricalWorkoutCSVError.emptyFile
        }
        let headers = rawHeaders.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let indexByHeader = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($0.element, $0.offset) })
        let missing = requiredColumns.filter { indexByHeader[$0] == nil }
        guard missing.isEmpty else {
            throw HistoricalWorkoutCSVError.missingColumns(missing)
        }

        func value(_ name: String, from columns: [String]) -> String {
            guard let index = indexByHeader[name], columns.indices.contains(index) else { return "" }
            return columns[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result: [HistoricalCSVRow] = []
        for (offset, columns) in table.dropFirst().enumerated() {
            let line = offset + 2
            guard columns.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }
            let completed = value("completed", from: columns).lowercased()
            if ["false", "0", "no"].contains(completed) {
                continue
            }
            let sessionID = value("session_id", from: columns)
            let workout = value("workout", from: columns)
            let exercise = value("exercise", from: columns)
            guard !sessionID.isEmpty else { throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "session_id") }
            guard let date = parseDate(value("date", from: columns)) else {
                throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "date")
            }
            guard !workout.isEmpty else { throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "workout") }
            guard !exercise.isEmpty else { throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "exercise") }
            guard let setNumber = Int(value("set", from: columns)), setNumber > 0 else {
                throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "set")
            }
            guard let weight = Double(value("weight_kg", from: columns)), weight >= 0 else {
                throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "weight_kg")
            }
            let volumeUnitText = value("volume_unit", from: columns)
            let volumeUnit = volumeUnitText.isEmpty
                ? nil
                : ExerciseVolumeUnit(rawValue: volumeUnitText)
            if !volumeUnitText.isEmpty, volumeUnit == nil {
                throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "volume_unit")
            }
            guard let reps = Int(value("reps", from: columns)), reps > 0 else {
                throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "reps")
            }
            let rirText = value("rir", from: columns)
            let rir = rirText.isEmpty ? nil : Int(rirText)
            if let rir, !(0...10).contains(rir) {
                throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "rir")
            }
            let setStartedAtText = value("set_started_at", from: columns)
            let setStartedAt = setStartedAtText.isEmpty ? nil : parseDate(setStartedAtText)
            if !setStartedAtText.isEmpty, setStartedAt == nil {
                throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "set_started_at")
            }
            let restText = value("rest_seconds", from: columns)
            let restDurationSeconds = restText.isEmpty ? nil : Int(restText)
            if !restText.isEmpty,
               restDurationSeconds == nil
                || !(0...RestDurationInput.maximumSeconds).contains(restDurationSeconds!) {
                throw HistoricalWorkoutCSVError.invalidValue(line: line, field: "rest_seconds")
            }

            result.append(
                HistoricalCSVRow(
                    line: line,
                    sessionID: sessionID,
                    date: date,
                    workout: workout,
                    durationMinutes: Int(value("duration_minutes", from: columns)) ?? 60,
                    workoutNotes: value("workout_notes", from: columns),
                    exercise: exercise,
                    muscleGroup: value("muscle_group", from: columns),
                    equipment: value("equipment", from: columns),
                    setNumber: setNumber,
                    weight: weight,
                    volumeUnit: volumeUnit,
                    reps: reps,
                    rir: rir,
                    startedAt: setStartedAt,
                    restDurationSeconds: restDurationSeconds,
                    exerciseNotes: value("exercise_notes", from: columns)
                )
            )
        }

        guard !result.isEmpty else { throw HistoricalWorkoutCSVError.emptyFile }
        return result
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }

        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func importIdentifier(for sessionID: String) -> String {
        "history-csv:\(sessionID)"
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\n", !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" || inQuotes {
                field.append(character)
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
