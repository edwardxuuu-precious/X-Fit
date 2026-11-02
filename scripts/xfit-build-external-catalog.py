#!/usr/bin/env python3
"""Build the pinned MIT non-media catalog without network access or database writes."""
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/external-exercises"
COMMIT = "7455efae41b330c265e7cd4b78dfa848e7ce5ebd"
TARGETS = {
    "abductors": ("髋外展肌群", "臀部"), "abs": ("腹肌", "核心"),
    "adductors": ("髋内收肌群", "腿部"), "biceps": ("肱二头肌", "手臂"),
    "calves": ("小腿肌群", "小腿"), "cardiovascular system": ("心肺", "有氧"),
    "delts": ("三角肌", "肩部"), "forearms": ("前臂肌群", "手臂"),
    "glutes": ("臀肌", "臀部"), "hamstrings": ("腘绳肌", "腿部"),
    "lats": ("背阔肌", "背部"), "levator scapulae": ("肩胛提肌", "颈部"),
    "pectorals": ("胸肌", "胸部"), "quads": ("股四头肌", "腿部"),
    "serratus anterior": ("前锯肌", "胸部"), "spine": ("脊柱周围肌群", "背部"),
    "traps": ("斜方肌", "背部"), "triceps": ("肱三头肌", "手臂"),
    "upper back": ("上背肌群", "背部"),
}
EQUIPMENT = dict(zip(
    ["body weight", "cable", "leverage machine", "assisted", "medicine ball", "stability ball",
     "band", "barbell", "rope", "dumbbell", "ez barbell", "sled machine", "upper body ergometer",
     "kettlebell", "olympic barbell", "weighted", "bosu ball", "resistance band", "roller",
     "skierg machine", "hammer", "smith machine", "wheel roller", "stationary bike", "tire",
     "trap bar", "elliptical machine", "stepmill machine"],
    ["自重", "龙门架", "杠杆器械", "辅助器械", "药球", "健身球", "弹力带", "杠铃", "绳索",
     "哑铃", "曲杆", "滑轨器械", "上肢功率车", "壶铃", "奥林匹克杠铃", "负重", "波速球",
     "阻力带", "滚筒", "滑雪机", "大锤", "史密斯机", "健腹轮", "固定单车", "轮胎",
     "六角杠", "椭圆机", "登阶机"]))


def semantic_reviews(source, translated):
    """Apply reviewed local annotations without replacing the pinned source text."""
    path = DATA / "semantic-review.json"
    if not path.exists():
        return {}
    review = json.loads(path.read_text())
    assert review["schemaVersion"] == 1 and review["sourceCommit"] == COMMIT
    assert review["sourceProjectionSHA256"] == hashlib.sha256((DATA / "source.json").read_bytes()).hexdigest()
    assert review["scopeCount"] == len(review["scopeSourceIDs"]) == 348
    records = review["entries"]
    by_id = {r["sourceID"]: r for r in records}
    assert len(records) == len(by_id) == 348
    assert set(by_id) == set(review["scopeSourceIDs"])
    assert set(by_id) <= {r["id"] for r in source["exercises"]}
    for record in records:
        assert record["originalNameZH"] == translated[record["sourceID"]]["nameZH"]
        assert record["decision"] in {"resolved", "retain_uncertainty"}
        assert record["equipmentConclusion"] and record["variantConclusion"] and record["evidence"]
        assert record["readScope"] == ["name", "equipment", "instruction_steps.en", "instruction_steps.zh"]
        assert any("\u4e00" <= c <= "\u9fff" for c in record["nameZH"])
        if record["decision"] == "retain_uncertainty":
            assert record["remainingUnknown"] and record["reviewNote"]
        else:
            assert not record["remainingUnknown"] and not record["reviewNote"]
    return by_id


def main():
    source_bytes = (DATA / "source.json").read_bytes()
    source = json.loads(source_bytes)
    assert source["commit"] == COMMIT and source["sourceCount"] == 1324
    rows = source["exercises"]
    assert len(rows) == len({r["id"] for r in rows}) == 1324
    localizations = [r for path in sorted((DATA / "localization").glob("chunk-*.json"))
                     for r in json.loads(path.read_text())]
    assert len(localizations) == len({r["sourceID"] for r in localizations}) == 1324
    translated = {r["sourceID"]: r for r in localizations}
    assert set(translated) == {r["id"] for r in rows}
    reviews = semantic_reviews(source, translated)
    mappings = json.loads((DATA / "matching-review.json").read_text())
    mapping = {m["sourceID"]: m for m in mappings}
    assert len(mapping) == len(mappings) and set(mapping) <= set(translated)
    duplicate_names = {name for name, count in Counter(r["name"] for r in rows).items() if count > 1}
    entries = []
    allowed_source_keys = {"id", "name", "category", "body_part", "equipment", "muscle_group",
                           "secondary_muscles", "target", "instruction_steps"}
    for row in rows:
        assert set(row) == allowed_source_keys
        loc = translated[row["id"]]
        assert set(loc) == {"sourceID", "nameZH", "reviewNote"}
        assert any("\u4e00" <= c <= "\u9fff" for c in loc["nameZH"])
        assert row["instruction_steps"]["en"] and row["instruction_steps"]["zh"]
        target, muscle_group = TARGETS[row["target"]]
        review = loc["reviewNote"]
        if row["name"] in duplicate_names:
            review = (review + " " if review else "") + "上游存在同名不同 ID 的条目；具体差异待核对，按来源 ID 分别保留。"
        annotation = reviews.get(row["id"])
        if annotation:
            assert annotation["originalReviewNote"] == review
            review = annotation["reviewNote"]
        match = mapping.get(row["id"], {})
        entries.append({
            "sourceID": row["id"], "nameZH": annotation["nameZH"] if annotation else loc["nameZH"], "nameEN": row["name"],
            "equipment": EQUIPMENT[row["equipment"]], "equipmentEN": row["equipment"],
            "muscleGroup": muscle_group, "target": target, "targetEN": row["target"],
            "secondaryMuscles": row["secondary_muscles"],
            "stepsZH": row["instruction_steps"]["zh"], "stepsEN": row["instruction_steps"]["en"],
            "aliases": match.get("aliases", []), "candidateAliases": match.get("candidateAliases", []),
            "reviewNote": review,
        })
    output = {"schemaVersion": 1, "repository": source["repository"], "commit": COMMIT,
              "sourceSHA256": source["upstreamSHA256"],
              "projectionSHA256": hashlib.sha256(source_bytes).hexdigest(),
              "licenseText": source["licenseText"], "entries": entries}
    destination = ROOT / "FitnessApp/Resources/ExternalExerciseCatalog.json"
    destination.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(json.dumps({"status": "PASS", "count": len(entries), "chineseNames": len(entries),
                      "reviewRequired": sum(bool(e["reviewNote"]) for e in entries),
                      "matchedSourceIDs": len(mapping), "bytes": destination.stat().st_size,
                      "resourceSHA256": hashlib.sha256(destination.read_bytes()).hexdigest()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
