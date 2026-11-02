import Foundation
import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class ExternalExerciseCatalogTests: XCTestCase {
    func testExplanationResolvesOnlyExplicitSourceAndKeepsPersonalIdentityUnchanged() throws {
        let context = try makeContext()
        let entry = try sourceEntry("0025")
        let owner = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        context.insert(owner); try context.save()
        let original = (owner.id, owner.name, owner.referenceURL, owner.updatedAt)
        XCTAssertNil(ExternalExerciseCatalogService.linkedEntry(reference: owner.referenceURL))
        XCTAssertTrue(ExternalExerciseCatalogService.explanationCandidates(name: owner.name, equipment: owner.equipment)
            .contains { $0.sourceID == entry.sourceID })
        XCTAssertEqual(ExternalExerciseCatalogService.linkedEntry(reference: ExternalExerciseCatalogService.referenceURL(for: entry))?.sourceID, entry.sourceID)
        XCTAssertNil(ExternalExerciseCatalogService.linkedEntry(reference: "https://example.com/?exercise=0025"))
        XCTAssertEqual(owner.id, original.0)
        XCTAssertEqual(owner.name, original.1)
        XCTAssertEqual(owner.referenceURL, original.2)
        XCTAssertEqual(owner.updatedAt, original.3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    func testOnlyReviewedDemonstrationsExposePerAssetAttribution() throws {
        for id in ["0025", "0289", "0314", "0047", "0334", "0603", "0405"] {
            let demo = try XCTUnwrap(ExternalExerciseCatalogService.demonstration(for: sourceEntry(id)))
            XCTAssertEqual(demo.sourceID, id)
            XCTAssertEqual(demo.videoURL.scheme, "https")
            XCTAssertEqual(demo.videoURL.host, "wger.de")
            XCTAssertEqual(demo.author, "Goulart")
            XCTAssertEqual(demo.licenseURL.absoluteString, "https://creativecommons.org/licenses/by-sa/4.0/")
            XCTAssertTrue(demo.sourceURL.path.hasPrefix("/api/v2/video/"))
        }
        XCTAssertNil(ExternalExerciseCatalogService.demonstration(for: try sourceEntry("0748")),
                     "史密斯卧推不能冒用杠铃卧推演示")
    }
    func testSupportedSingleDumbbellReverseLungeIsDiscoverableButNotExactWithoutSourceLink() throws {
        let context = try makeContext()
        let entry = try sourceEntry("0381")
        let owner = Exercise(name: "反向箭步蹲", muscleGroup: "腿部", equipment: "哑铃",
                             notes: "本人单手30kg、另一手扶架；每侧10次", volumeUnit: .kilogram,
                             terminologyCanonicalID: "owner.supported.reverse-lunge",
                             terminologyDecision: .accepted)
        owner.terminologyStandardNameZH = "本人已确认扶架后撤"
        context.insert(owner)
        try context.save()
        let before = (owner.id, owner.name, owner.notes, owner.equipment,
                      owner.updatedAt, owner.approvedCanonicalID, owner.terminologyStandardNameZH)

        let match = try XCTUnwrap(ExternalExerciseCatalogService.matches(for: entry, among: [owner]).first)
        XCTAssertFalse(match.isExact, "双哑铃来源不能仅凭泛称把单哑铃扶架变式标为精确匹配")
        let catalog = try ExternalExerciseCatalogService.catalogResult.get()
        XCTAssertTrue(ExternalExerciseCatalogService.search(catalog.entries, query: owner.name)
            .contains { $0.sourceID == entry.sourceID }, "降为候选后仍保留原泛称搜索")
        XCTAssertTrue(ExternalExerciseCatalogService.searchTerms(for: owner).contains(entry.nameEN))
        XCTAssertEqual(owner.id, before.0)
        XCTAssertEqual(owner.name, before.1)
        XCTAssertEqual(owner.notes, before.2)
        XCTAssertEqual(owner.equipment, before.3)
        XCTAssertEqual(owner.updatedAt, before.4)
        XCTAssertEqual(owner.approvedCanonicalID, before.5)
        XCTAssertEqual(owner.terminologyStandardNameZH, before.6)
        XCTAssertEqual(owner.volumeUnit, .kilogram)
        XCTAssertFalse(context.hasChanges)

        let linked = Exercise(name: "本人已从0381加入并重命名", muscleGroup: "本人腿部",
                              equipment: "本人器械", notes: "保留本人单位",
                              referenceURL: ExternalExerciseCatalogService.referenceURL(for: entry),
                              volumeUnit: .count)
        context.insert(linked)
        try context.save()
        XCTAssertTrue(try XCTUnwrap(ExternalExerciseCatalogService.matches(for: entry, among: [linked]).first).isExact,
                      "既有显式来源链接继续复用，不撤销本人已选来源")
        XCTAssertEqual(linked.volumeUnit, .count)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 2)
        XCTAssertFalse(context.hasChanges)
    }

    func testClarifiedRaiseKeepsHistoricalSidePullAsCandidateAndBallPressDistinct() throws {
        let raise = try sourceEntry("0376")
        XCTAssertTrue(raise.nameZH.contains("站姿侧平举"))
        XCTAssertFalse(raise.needsReview, "完整步骤已明确站姿及向两侧抬臂，不因Raise泛称强造冲突")
        let owner = Exercise(name: "Dumbbell Side Pull", muscleGroup: "肩部", equipment: "哑铃",
                             notes: "本人已确认侧平举，姿势未进一步确认")
        let matches = ExternalExerciseCatalogService.matches(for: raise, among: [owner])
        XCTAssertEqual(matches.count, 1)
        XCTAssertFalse(matches[0].isExact, "来源定义变清楚不能替本人补确认站姿或批准身份")
        let ball = try sourceEntry("1621")
        XCTAssertTrue(ball.nameZH.contains("健身球"))
        XCTAssertTrue(ball.nameZH.contains("坐姿"))
        XCTAssertTrue(ball.nameZH.contains("中立握"))
        let standing = Exercise(name: "站姿哑铃肩推", muscleGroup: "肩部", equipment: "哑铃")
        XCTAssertFalse(ExternalExerciseCatalogService.matches(for: ball, among: [standing]).contains(where: \.isExact))
        XCTAssertEqual(owner.name, "Dumbbell Side Pull")
        XCTAssertNil(owner.approvedCanonicalID)
    }

    func testReviewedHistoricalCandidatesDoNotApproveIdentityOrRewriteOwnerDefinitions() throws {
        let context = try makeContext()
        let owners = [
            Exercise(name: "双滑轮高位下拉", muscleGroup: "背部", equipment: "双滑轮器械", notes: "本人设置未确认"),
            Exercise(name: "颈后下拉", muscleGroup: "背部", equipment: "器械",
                     terminologyCanonicalID: "behind_neck_lat_pulldown", terminologyDecision: .accepted),
            Exercise(name: "坐姿推胸机", muscleGroup: "胸部", equipment: "器械"),
            Exercise(name: "器械推胸", muscleGroup: "胸部", equipment: "器械")
        ]
        for owner in owners { context.insert(owner) }
        try context.save()
        let before = owners.map { ($0.id, $0.name, $0.equipment, $0.updatedAt, $0.approvedCanonicalID) }
        for id in ["0818", "0205", "0576", "0577"] {
            let entry = try sourceEntry(id)
            XCTAssertEqual(entry.needsReview, ["0818", "0205"].contains(id),
                           "推胸定义已核清，握法/Rear冲突继续可见；历史身份均仍为候选：\(id)")
            let matches = ExternalExerciseCatalogService.matches(for: entry, among: owners)
            XCTAssertFalse(matches.isEmpty, id)
            XCTAssertFalse(matches.contains(where: \.isExact), id)
        }
        for (index, owner) in owners.enumerated() {
            XCTAssertEqual(owner.id, before[index].0)
            XCTAssertEqual(owner.name, before[index].1)
            XCTAssertEqual(owner.equipment, before[index].2)
            XCTAssertEqual(owner.updatedAt, before[index].3)
            XCTAssertEqual(owner.approvedCanonicalID, before[index].4)
        }
        XCTAssertFalse(context.hasChanges)
    }

    func testCrossCheckedDefinitionsDoNotAutomaticallyApprovePersonalIdentity() throws {
        let context = try makeContext()
        for id in ["0088", "0473", "0576", "0577", "0655", "0656", "0807", "1371", "2142", "3665",
                   "0063", "0638", "0760", "2300", "3418", "1396"] {
            let entry = try sourceEntry(id)
            XCTAssertFalse(entry.needsReview, id)
            for label in [entry.nameZH, entry.nameEN] {
                let owner = Exercise(name: label, muscleGroup: "本人定义", equipment: entry.equipment,
                                     notes: "本人姿势、机型和计重口径尚未确认", volumeUnit: .count)
                context.insert(owner)
                try context.save()
                let before = (owner.id, owner.name, owner.equipment, owner.notes, owner.updatedAt)
                let matches = ExternalExerciseCatalogService.matches(for: entry, among: [owner])
                XCTAssertEqual(matches.count, 1, id)
                XCTAssertFalse(matches[0].isExact, "定义清楚不批准本人身份：\(id)")
                XCTAssertEqual(owner.id, before.0)
                XCTAssertEqual(owner.name, before.1)
                XCTAssertEqual(owner.equipment, before.2)
                XCTAssertEqual(owner.notes, before.3)
                XCTAssertEqual(owner.updatedAt, before.4)
                XCTAssertEqual(owner.volumeUnit, .count)
                XCTAssertNil(owner.approvedCanonicalID)
                XCTAssertFalse(context.hasChanges)
            }
        }
        let sphinx = try sourceEntry("1362")
        XCTAssertTrue(sphinx.needsReview, "关键髋支撑未知不能当作型号之类的非关键缺项清除")
        XCTAssertTrue(sphinx.reviewNote.contains("髋"))
    }

    func testFollowUpCorrectionsKeepPreviousChineseLabelsSearchable() throws {
        let catalog = try ExternalExerciseCatalogService.catalogResult.get()
        let previousLabels = [
            ("0063", "杠铃窄站距深蹲（待核对）"),
            ("0384", "哑铃反握牧师凳弯举"),
            ("0451", "EZ曲杆反握弯举"),
            ("0572", "杠杆器械辅助反握引体向上"),
            ("0638", "手腕自辅助单臂反握引体向上（待核对）"),
            ("0746", "史密斯背后耸肩"),
            ("1355", "单臂抵墙动作（One Arm Against Wall）"),
            ("1396", "史密斯抬脚尖"),
            ("1415", "哑铃坐姿单臂中立握腕弯举"),
            ("0365", "哑铃凳上中立握腕弯举"),
            ("0366", "哑铃凳上单臂中立握腕弯举"),
            ("1431", "站垫辅助反握引体向上（待核对）"),
            ("1680", "哑铃站姿单臂弯举（倚上斜凳）"),
            ("3287", "肘撑臂屈伸（Elbow Dips，待核对）")
        ]
        for (id, previousLabel) in previousLabels {
            let found = ExternalExerciseCatalogService.search(catalog.entries, query: previousLabel)
            XCTAssertTrue(found.contains { $0.sourceID == id },
                          "改名不能使用户按原名称找不到同一来源：\(id)")
            if ["0365", "0366"].contains(id) {
                let entry = try XCTUnwrap(found.first { $0.sourceID == id })
                let owner = Exercise(name: previousLabel, muscleGroup: "本人定义", equipment: entry.equipment,
                                     notes: "本人已确认名称与计量保持", volumeUnit: .count)
                let match = try XCTUnwrap(ExternalExerciseCatalogService.matches(for: entry, among: [owner]).first)
                XCTAssertTrue(entry.needsReview, "去掉中立握过度翻译不等于腕/肘运动已核实")
                XCTAssertFalse(match.isExact, "旧译名只保留检索，不能批准本人身份")
                XCTAssertEqual(owner.name, previousLabel)
                XCTAssertEqual(owner.volumeUnit, .count)
                XCTAssertNil(owner.approvedCanonicalID)
            }
        }
    }

    func testUnresolvedSourceReviewCannotBecomeExactFromNameAndEquipmentAlone() throws {
        let catalog = try ExternalExerciseCatalogService.catalogResult.get()
        let unresolved = catalog.entries.filter(\.needsReview)
        XCTAssertFalse(unresolved.isEmpty)
        for entry in unresolved {
            // A reference label is not proof of the owner's actual variant.
            let owner = Exercise(name: entry.nameEN, muscleGroup: "本人肌群", equipment: entry.equipment)
            let matches = ExternalExerciseCatalogService.matches(for: entry, among: [owner])
            XCTAssertEqual(matches.count, 1, entry.sourceID)
            XCTAssertFalse(matches[0].isExact, entry.sourceID)
            XCTAssertNil(owner.approvedCanonicalID)
        }
        let mislabeled = try sourceEntry("0574")
        XCTAssertEqual(mislabeled.equipmentEN, "barbell", "固定原字段不能被Lever标题覆盖")
        XCTAssertEqual(mislabeled.stepsEN[1], "Hold the barbell with an overhand grip, hands slightly wider than shoulder-width apart.")
        XCTAssertTrue(mislabeled.needsReview)
    }

    func testBundledCatalogPreservesAllSourceIDsChineseNamesAndLicenseWithoutMedia() throws {
        let catalog = try ExternalExerciseCatalogService.load()
        XCTAssertEqual(catalog.commit, ExternalExerciseCatalogService.expectedCommit)
        XCTAssertEqual(catalog.entries.count, 1_324)
        XCTAssertEqual(Set(catalog.entries.map(\.sourceID)).count, 1_324)
        XCTAssertNotNil(catalog.sourceSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
        XCTAssertTrue(catalog.licenseText.contains("MIT License"))
        XCTAssertTrue(catalog.licenseText.contains("Hasan Emir"))
        for entry in catalog.entries {
            XCTAssertTrue(entry.nameZH.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, entry.sourceID)
            XCTAssertFalse(entry.nameEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, entry.sourceID)
            XCTAssertFalse(entry.stepsZH.isEmpty, entry.sourceID)
            XCTAssertFalse(entry.stepsEN.isEmpty, entry.sourceID)
        }

        // A shared source label does not grant permission to collapse distinct source records.
        let sourceDuplicates: [String: Set<String>] = [
            "barbell seated calf raise": ["0088", "1371"],
            "ez barbell spider curl": ["0454", "1628"],
            "lever chest press": ["0577", "0576"],
            "push-up (on stability ball)": ["0655", "0656"],
            "self assisted inverse leg curl": ["0697", "1766"],
            "smith reverse calf raises": ["0763", "1394"]
        ]
        for (name, ids) in sourceDuplicates {
            XCTAssertEqual(Set(catalog.entries.filter { $0.nameEN == name }.map(\.sourceID)), ids, name)
        }

        let resourceURL = try XCTUnwrap(Bundle.main.url(forResource: "ExternalExerciseCatalog", withExtension: "json"))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: resourceURL))
        assertNoMedia(in: raw)
    }

    func testBilingualSearchAndCombinedFiltersFindSmithBenchWithoutCreatingPersonalRecords() throws {
        let context = try makeContext()
        let catalog = try ExternalExerciseCatalogService.catalogResult.get()
        let smith = try sourceEntry("0748")
        for query in ["史密斯 卧推", "SMITH bench press", "0748"] {
            let found = ExternalExerciseCatalogService.search(catalog.entries, query: query)
            XCTAssertTrue(found.contains { $0.sourceID == smith.sourceID }, query)
        }
        let combined = ExternalExerciseCatalogService.search(catalog.entries, query: "smith bench",
            muscleGroup: smith.muscleGroup, equipment: smith.equipment)
        XCTAssertTrue(combined.contains { $0.sourceID == smith.sourceID })
        XCTAssertTrue(combined.allSatisfy { $0.muscleGroup == smith.muscleGroup && $0.equipment == smith.equipment })
        XCTAssertFalse(ExternalExerciseCatalogService.search(catalog.entries, query: "smith bench",
            muscleGroup: "不在目录的肌群", equipment: smith.equipment).contains { $0.sourceID == smith.sourceID })
        XCTAssertTrue(ExternalExerciseCatalogService.search(catalog.entries, query: "不存在的动作XYZ").isEmpty)
        XCTAssertEqual(ExternalExerciseCatalogService.search(catalog.entries, query: "  ").count, 1_324)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testSmithChineseEnglishMatchesReuseOwnerIdentityAndLeaveApprovalUntouched() throws {
        let context = try makeContext()
        let smith = try sourceEntry("0748")
        let chinese = Exercise(name: "史密斯卧推", muscleGroup: "本人胸部", equipment: "史密斯机",
            defaultRestSeconds: 123, notes: "每侧片重，不含杆", volumeUnit: .kilogram,
            terminologyCanonicalID: "owner.confirmed.smith", terminologyStandardNameZH: "本人已确认名称",
            terminologyDecision: .accepted)
        let english = Exercise(name: "Smith Bench Press", muscleGroup: "胸部", equipment: "smith machine")
        let archived = Exercise(name: "Smith Bench Press", muscleGroup: "胸部", equipment: "史密斯", isArchived: true)
        context.insert(chinese); context.insert(english); context.insert(archived)
        try context.save()
        let chineseUpdated = chinese.updatedAt
        let englishUpdated = english.updatedAt
        let matches = ExternalExerciseCatalogService.matches(for: smith, among: [chinese, english, archived])
        XCTAssertEqual(Set(matches.map(\.id)), Set([chinese.id, english.id]))
        XCTAssertTrue(matches.allSatisfy(\.isExact))
        XCTAssertTrue(ExternalExerciseCatalogService.matches(for: smith, among: [chinese], excludedIDs: [chinese.id]).isEmpty)
        XCTAssertEqual(chinese.approvedCanonicalID, "owner.confirmed.smith")
        XCTAssertEqual(chinese.terminologyStandardNameZH, "本人已确认名称")
        XCTAssertEqual(chinese.updatedAt, chineseUpdated)
        XCTAssertEqual(chinese.name, "史密斯卧推")
        XCTAssertEqual(chinese.muscleGroup, "本人胸部")
        XCTAssertEqual(chinese.defaultRestSeconds, 123)
        XCTAssertEqual(chinese.notes, "每侧片重，不含杆")
        XCTAssertEqual(chinese.referenceURL, "")
        XCTAssertNil(english.approvedCanonicalID)
        XCTAssertEqual(english.terminologyDecision, .pending)
        XCTAssertEqual(english.updatedAt, englishUpdated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 3)
        XCTAssertFalse(context.hasChanges)
    }

    func testAmbiguousEquipmentCandidateNamesAndReviewedSourceCannotApproveExactIdentity() throws {
        let context = try makeContext()
        let entry = fixtureEntry()
        let unknownEquipment = Exercise(name: entry.nameZH, muscleGroup: "胸部", equipment: "未记录")
        let customMachine = Exercise(name: entry.nameEN, muscleGroup: "胸部", equipment: "本人定制推胸机")
        let candidateAlias = Exercise(name: "史密斯推胸待核对", muscleGroup: "胸部", equipment: entry.equipment)
        let pendingStandard = Exercise(name: "本人原始动作", muscleGroup: "胸部", equipment: entry.equipment,
            terminologyCanonicalID: "unapproved.candidate", terminologyStandardNameZH: entry.nameZH,
            terminologyDecision: .pending)
        let otherSource = Exercise(name: entry.nameZH, muscleGroup: "胸部", equipment: entry.equipment,
            referenceURL: ExternalExerciseCatalogService.referenceURL(for: fixtureEntry(sourceID: "different-source")))
        let exercises = [unknownEquipment, customMachine, candidateAlias, pendingStandard, otherSource]
        for exercise in exercises { context.insert(exercise) }
        try context.save()
        let beforeDates = exercises.map(\.updatedAt)
        let matches = ExternalExerciseCatalogService.matches(for: entry, among: exercises)
        XCTAssertEqual(Set(matches.map(\.id)), Set(exercises.map(\.id)))
        XCTAssertTrue(matches.allSatisfy { !$0.isExact })
        let rawExact = Exercise(name: entry.nameZH, muscleGroup: "胸部", equipment: entry.equipment)
        let reviewed = fixtureEntry(reviewNote: "来源名称与步骤的角度冲突")
        XCTAssertFalse(try XCTUnwrap(ExternalExerciseCatalogService.matches(for: reviewed, among: [rawExact]).first).isExact)
        XCTAssertEqual(exercises.map(\.updatedAt), beforeDates)
        XCTAssertTrue(exercises.allSatisfy { $0.approvedCanonicalID == nil && $0.terminologyDecision == .pending })
        XCTAssertEqual(pendingStandard.terminologyCanonicalID, "unapproved.candidate")
        XCTAssertFalse(context.hasChanges)
    }

    func testGenericMachineLabelsCannotEstablishSpecificLeverMachineIdentity() throws {
        let entry = ExternalExerciseEntry(sourceID: "fixture-lever", nameZH: "杠杆器械平板推胸",
            nameEN: "lever chest press", equipment: "杠杆器械", equipmentEN: "leverage machine",
            muscleGroup: "胸部", target: "胸大肌", targetEN: "pectorals", secondaryMuscles: [],
            stepsZH: ["来源参考步骤"], stepsEN: ["Reference step"], aliases: [], candidateAliases: [], reviewNote: "")
        let genericChinese = Exercise(name: entry.nameZH, muscleGroup: "胸部", equipment: "器械")
        let genericEnglish = Exercise(name: entry.nameEN, muscleGroup: "胸部", equipment: "machine")
        let matches = ExternalExerciseCatalogService.matches(for: entry, among: [genericChinese, genericEnglish])
        XCTAssertEqual(matches.count, 2)
        XCTAssertTrue(matches.allSatisfy { !$0.isExact }, "泛称器械没有确认杠杆式阻力类型")
        XCTAssertNil(genericChinese.approvedCanonicalID)
        XCTAssertNil(genericEnglish.approvedCanonicalID)
    }

    func testExplicitCandidateStatusWinsEvenWhenRawEnglishNameMatchesSource() throws {
        let entry = try sourceEntry("0766")
        let owner = Exercise(name: "Smith shoulder press", muscleGroup: "肩部", equipment: "史密斯机")
        let match = try XCTUnwrap(ExternalExerciseCatalogService.matches(for: entry, among: [owner]).first)
        XCTAssertFalse(match.isExact, "未确认坐姿/站姿的原始名称不能因英文同名绕过候选边界")
        XCTAssertNil(owner.approvedCanonicalID)
        XCTAssertEqual(owner.name, "Smith shoulder press")
    }

    func testPersonalPickerGetsBilingualDiscoveryWithoutCanonicalApproval() throws {
        let smith = try sourceEntry("0748")
        let chinese = Exercise(name: "史密斯卧推", muscleGroup: "胸部", equipment: "史密斯机")
        let english = Exercise(name: "Smith Bench Press", muscleGroup: "胸部", equipment: "smith machine")
        XCTAssertTrue(ExerciseCatalogService.search([chinese], query: smith.nameEN).contains { $0.id == chinese.id })
        XCTAssertTrue(ExerciseCatalogService.search([english], query: smith.nameZH).contains { $0.id == english.id })
        XCTAssertNil(chinese.approvedCanonicalID)
        XCTAssertNil(english.approvedCanonicalID)
        XCTAssertNil(ExerciseCatalogService.exactNameMatch(named: smith.nameEN, in: [chinese]))
        XCTAssertEqual(chinese.referenceURL, "")
        XCTAssertEqual(english.referenceURL, "")
    }

    func testAddingRequiresExplicitUnitAndDoesNotWriteWhenUnitIsMissing() throws {
        let context = try makeContext()
        let entry = try sourceEntry("0748")
        XCTAssertThrowsError(try ExternalExerciseCatalogService.add(entry, name: entry.nameZH,
            unit: nil, exercises: [], in: context)) { error in
            guard let catalogError = error as? ExternalExerciseCatalogError,
                  case .unitRequired = catalogError else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testRepeatedAddRefetchesStaleListAndReusesRenamedSourceWithoutRewritingOwnerFields() throws {
        let context = try makeContext()
        let entry = try sourceEntry("0748")
        let original = try ExternalExerciseCatalogService.add(entry, name: entry.nameZH,
            unit: .kilogram, exercises: [], in: context)
        XCTAssertFalse(original.isBuiltIn)
        XCTAssertEqual(original.volumeUnit, .kilogram)
        XCTAssertEqual(ExternalExerciseCatalogService.sourceID(in: original.referenceURL), entry.sourceID)
        XCTAssertNil(original.approvedCanonicalID)
        let originalID = original.id
        original.name = "本人重新命名史密斯卧推"
        original.equipment = "本人史密斯器械"
        original.muscleGroup = "本人胸部标签"
        original.notes = "每侧片重，不含杆"
        original.defaultRestSeconds = 127
        original.terminologyCanonicalID = "owner.confirmed.identity"
        original.terminologyDecision = .accepted
        original.terminologyStandardNameZH = "本人已确认别名"
        try context.save()
        let savedUpdated = original.updatedAt
        let savedCreated = original.createdAt
        let repeated = try ExternalExerciseCatalogService.add(entry, name: "另一个新名称",
            unit: .kilogram, exercises: [], in: context)
        XCTAssertEqual(repeated.id, originalID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 1)
        XCTAssertEqual(repeated.name, "本人重新命名史密斯卧推")
        XCTAssertEqual(repeated.equipment, "本人史密斯器械")
        XCTAssertEqual(repeated.muscleGroup, "本人胸部标签")
        XCTAssertEqual(repeated.notes, "每侧片重，不含杆")
        XCTAssertEqual(repeated.defaultRestSeconds, 127)
        XCTAssertEqual(repeated.volumeUnit, .kilogram)
        XCTAssertEqual(repeated.approvedCanonicalID, "owner.confirmed.identity")
        XCTAssertEqual(repeated.terminologyStandardNameZH, "本人已确认别名")
        XCTAssertEqual(repeated.updatedAt, savedUpdated)
        XCTAssertEqual(repeated.createdAt, savedCreated)
        XCTAssertTrue(try XCTUnwrap(ExternalExerciseCatalogService.matches(for: entry, among: [repeated]).first).isExact)
        XCTAssertThrowsError(try ExternalExerciseCatalogService.add(entry, name: entry.nameZH,
            unit: .count, exercises: [], in: context)) { error in
            guard let catalogError = error as? ExternalExerciseCatalogError,
                  case .existingUnitConflict = catalogError else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(repeated.volumeUnit, .kilogram)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testUnknownSameNameAndArchivedSourceAreNotOverwrittenOrRestored() throws {
        let context = try makeContext()
        let entry = try sourceEntry("0748")
        let owner = Exercise(name: entry.nameZH, muscleGroup: "手臂", equipment: "未知自定义器械",
            defaultRestSeconds: 63, isArchived: true, notes: "保留本人定义",
            referenceURL: "https://example.com/owner-source", volumeUnit: .count)
        context.insert(owner); try context.save()
        let ownerUpdated = owner.updatedAt
        XCTAssertThrowsError(try ExternalExerciseCatalogService.add(entry, name: entry.nameZH,
            unit: .kilogram, exercises: [], in: context)) { error in
            guard let catalogError = error as? ExternalExerciseCatalogError,
                  case .nameConflict = catalogError else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(owner.name, entry.nameZH)
        XCTAssertEqual(owner.equipment, "未知自定义器械")
        XCTAssertEqual(owner.volumeUnit, .count)
        XCTAssertEqual(owner.notes, "保留本人定义")
        XCTAssertEqual(owner.referenceURL, "https://example.com/owner-source")
        XCTAssertEqual(owner.updatedAt, ownerUpdated)
        XCTAssertTrue(owner.isArchived)
        let archivedSource = try ExternalExerciseCatalogService.add(entry, name: "本人另建可区分变式",
            unit: .kilogram, exercises: [], in: context)
        archivedSource.isArchived = true
        try context.save()
        XCTAssertThrowsError(try ExternalExerciseCatalogService.add(entry, name: "再次选用此来源",
            unit: .kilogram, exercises: [], in: context)) { error in
            guard let catalogError = error as? ExternalExerciseCatalogError,
                  case .existingUnitConflict = catalogError else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertTrue(archivedSource.isArchived)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 2)
        XCTAssertFalse(context.hasChanges)
    }

    func testBrowsingMatchingAndAddingKeepCompletedHistoryUnknownRIRAndPerSideSemantics() throws {
        let context = try makeContext()
        let smith = try sourceEntry("0748")
        let date = Date(timeIntervalSince1970: 1_792_540_800)
        let owner = Exercise(name: "Smith Bench Press", muscleGroup: "胸部", equipment: "未记录",
            notes: "每侧片重，不含杆", volumeUnit: .kilogram)
        let session = WorkoutSession(templateName: "Notes Oct 23", plannedDate: date,
            startedAt: date, completedAt: date, status: .completed,
            notes: "实际完成来源", importIdentifier: "owner-48-row-import")
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: owner.id,
            exerciseName: "Smith Bench Press 原始快照", order: 0, targetSets: 2,
            minReps: 6, maxReps: 16, targetWeight: 45, restSeconds: 90,
            muscleGroup: "胸部", exerciseNotes: "每侧片重，不含杆",
            referenceURL: "https://example.com/historical-source", equipmentSnapshot: nil)
        let single = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: owner.id,
            setNumber: 1, targetWeight: 45, targetReps: 6, actualWeight: 45, actualReps: 6,
            isCompleted: true, completedAt: date, targetWeightSide: .single,
            targetRepsSide: .unknown, actualWeightSide: .single, actualRepsSide: .unknown)
        let legacyUnknown = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: owner.id,
            setNumber: 2, targetWeight: 20, targetReps: 16, actualWeight: 20, actualReps: 16,
            isCompleted: true, completedAt: date)
        legacyUnknown.actualWeightSideRaw = nil
        legacyUnknown.actualRepsSideRaw = nil
        context.insert(owner); context.insert(session); context.insert(snapshot)
        context.insert(single); context.insert(legacyUnknown); try context.save()
        let originalOwnerUpdated = owner.updatedAt
        let originalPlan = snapshot.plannedSetsJSON
        let originalLogIDs = Set([single.id, legacyUnknown.id])
        let catalog = try ExternalExerciseCatalogService.catalogResult.get()
        _ = ExternalExerciseCatalogService.search(catalog.entries, query: "Smith Bench")
        let match = try XCTUnwrap(ExternalExerciseCatalogService.matches(for: smith, among: [owner]).first)
        XCTAssertFalse(match.isExact, "未知器械不可由来源库推断")
        _ = try ExternalExerciseCatalogService.add(smith, name: "新增史密斯卧推来源变式",
            unit: .kilogram, exercises: [owner], in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).count, 1)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id)), originalLogIDs)
        XCTAssertEqual(owner.name, "Smith Bench Press")
        XCTAssertEqual(owner.equipment, "未记录")
        XCTAssertEqual(owner.notes, "每侧片重，不含杆")
        XCTAssertEqual(owner.referenceURL, "")
        XCTAssertEqual(owner.updatedAt, originalOwnerUpdated)
        XCTAssertNil(owner.approvedCanonicalID)
        XCTAssertEqual(snapshot.exerciseID, owner.id)
        XCTAssertEqual(snapshot.exerciseName, "Smith Bench Press 原始快照")
        XCTAssertEqual(snapshot.exerciseNotes, "每侧片重，不含杆")
        XCTAssertEqual(snapshot.referenceURL, "https://example.com/historical-source")
        XCTAssertEqual(snapshot.plannedSetsJSON, originalPlan)
        XCTAssertEqual(snapshot.volumeUnit, .kilogram)
        XCTAssertNil(snapshot.equipmentSnapshot)
        XCTAssertNil(snapshot.exerciseStartedAt)
        XCTAssertNil(snapshot.exerciseCompletedAt)
        XCTAssertEqual(single.exerciseID, owner.id)
        XCTAssertEqual(single.sessionExerciseID, snapshot.id)
        XCTAssertEqual(single.actualWeight, 45)
        XCTAssertEqual(single.actualReps, 6)
        XCTAssertEqual(single.actualWeightSideRaw, MeasurementSide.single.rawValue)
        XCTAssertEqual(single.actualRepsSideRaw, MeasurementSide.unknown.rawValue)
        XCTAssertNil(single.rir)
        XCTAssertTrue(single.isCompleted)
        XCTAssertEqual(single.completedAt, date)
        XCTAssertEqual(legacyUnknown.actualWeight, 20)
        XCTAssertEqual(legacyUnknown.actualReps, 16)
        XCTAssertNil(legacyUnknown.actualWeightSideRaw)
        XCTAssertNil(legacyUnknown.actualRepsSideRaw)
        XCTAssertNil(legacyUnknown.rir)
        XCTAssertTrue(legacyUnknown.isCompleted)
        XCTAssertEqual(session.importIdentifier, "owner-48-row-import")
        XCTAssertEqual(session.completedAt, date)
        XCTAssertFalse(context.hasChanges)
    }

    func testSourceReferenceKeepsPinnedIDAndRejectsUnrelatedOwnerURLs() throws {
        let entry = try sourceEntry("0748")
        let reference = ExternalExerciseCatalogService.referenceURL(for: entry)
        XCTAssertTrue(reference.contains(ExternalExerciseCatalogService.expectedCommit))
        XCTAssertEqual(ExternalExerciseCatalogService.sourceID(in: reference), "0748")
        for unrelated in ["", "https://example.com/?exercise=0748",
            "https://github.com.evil.example/hasaneyldrm/exercises-dataset/blob/main/data/exercises.json?exercise=0748",
            "https://github.com/another/repository/blob/main/data/exercises.json?exercise=0748"] {
            XCTAssertNil(ExternalExerciseCatalogService.sourceID(in: unrelated), unrelated)
        }
    }

    private func sourceEntry(_ id: String) throws -> ExternalExerciseEntry {
        let catalog = try ExternalExerciseCatalogService.catalogResult.get()
        return try XCTUnwrap(catalog.entries.first { $0.sourceID == id }, "Missing source \(id)")
    }

    private func fixtureEntry(sourceID: String = "fixture-smith", reviewNote: String = "") -> ExternalExerciseEntry {
        ExternalExerciseEntry(sourceID: sourceID, nameZH: "史密斯平板卧推", nameEN: "smith bench press",
            equipment: "史密斯机", equipmentEN: "smith machine", muscleGroup: "胸部",
            target: "胸大肌", targetEN: "pectorals", secondaryMuscles: ["肱三头肌"],
            stepsZH: ["来源参考步骤"], stepsEN: ["Reference step"],
            aliases: ["史密斯卧推"], candidateAliases: ["史密斯推胸待核对"], reviewNote: reviewNote)
    }

    private func assertNoMedia(in value: Any, file: StaticString = #filePath, line: UInt = #line) {
        let forbiddenKeys: Set<String> = ["image", "images", "imageurl", "image_url", "gif", "gifurl", "gif_url",
            "video", "videos", "videourl", "video_url", "media", "mediaid", "media_id", "attribution"]
        if let object = value as? [String: Any] {
            for (key, child) in object {
                XCTAssertFalse(forbiddenKeys.contains(key.lowercased()), "Media field: \(key)", file: file, line: line)
                assertNoMedia(in: child, file: file, line: line)
            }
        } else if let array = value as? [Any] {
            for child in array { assertNoMedia(in: child, file: file, line: line) }
        } else if let text = value as? String {
            let pattern = "https?://[^\\s\\\"<>]+\\.(gif|png|jpe?g|webp|mp4|mov|webm)([?/#][^\\s\\\"<>]*)?"
            XCTAssertNil(text.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                         "Unexpected media link", file: file, line: line)
        }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Exercise.self, WorkoutSession.self, SessionExercise.self, SetLog.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        return ModelContext(container)
    }
}
