#!/usr/bin/env python3
"""Prepare three stable, owner-confirmed daily packets. Never accesses the phone."""
import datetime
import hashlib
import json
import re
import uuid
from pathlib import Path

BASE = Path(__file__).resolve().parent
REVIEW_DIR = BASE.parent
REVIEW = REVIEW_DIR / "上肢周重点动作递减组审阅版.md"
REVIEW_SHA = "ebb971dba69317ddd930ddb5003c9ddf2434a3e447f32c8ead5ebe72933e2014"
RECEIPTS = REVIEW_DIR / "手机同步回执"
NAMESPACE = uuid.UUID("75a6e897-ae33-53fb-b6fa-603608bbd609")

# IDs and equipment were captured from the phone's 2026-10-29 catalog. The
# device preview must independently compare every item with the live catalog.
CATALOG = {
    "Smith Bench Press": ("8C2B39A3-8F47-413E-BC5F-93EC3CB313DA", "史密斯机"),
    "器械上斜卧推": ("62B7E172-C76F-4502-8643-87249F7199E3", "器械"),
    "坐姿飞鸟": ("2FFA02FD-85F0-4938-A9C9-59A3561C241E", "器械"),
    "站姿绳索夹胸": ("8DE3EE03-A5A3-4767-954B-333D4BD17332", "龙门架"),
    "Smith shoulder press": ("57E855E6-E0AB-46FB-AE88-AED4ABF9144B", "史密斯机"),
    "坐姿哑铃侧平举": ("785412EA-AC6A-4910-9942-8C3B2E380CB8", "哑铃"),
    "绳索反向飞鸟": ("67518BD0-1C2E-464C-8753-EB48E62581DB", "龙门架"),
    "器械坐姿侧平举": ("9BB12534-10A3-435D-BE9A-10A70ED0616F", "器械"),
    "Dual Pulley Low Row": ("C79CFAC1-F36F-48B4-9414-CFD5DDBA36F5", "未记录"),
    "Dual Pulley Pulldown": ("D500EAB2-975C-490E-8D9E-748ACC80005A", "未记录"),
    "Barbell Row": ("C49D988B-D665-4CD8-B7A2-7F317577A59C", "杠铃"),
    "绳索直臂下压": ("C7A8C101-5D38-4D2D-8BBF-3A7995E37815", "未记录"),
    "杠铃片胸前转体": ("335CAF55-9728-409F-8ED8-C274969E04DD", "未记录"),
    "垫高绳索站姿侧屈": ("22A76B09-D7F7-59E4-B23A-406B7F0ECC4D", "龙门架"),
    "站姿水平伐木": ("195BA3AF-2C3E-43B2-84F5-89849FDA1009", "龙门架"),
    "负重仰卧起坐": ("32A4B251-B931-49DB-9891-F72ADDCF87D2", "负重片"),
}
DAY_ORDER = {
    "2026-11-02": ["Smith Bench Press", "器械上斜卧推", "坐姿飞鸟", "站姿绳索夹胸", "Smith shoulder press", "坐姿哑铃侧平举", "绳索反向飞鸟", "器械坐姿侧平举"],
    "2026-11-04": ["Dual Pulley Low Row", "Dual Pulley Pulldown", "Barbell Row", "绳索直臂下压", "杠铃片胸前转体", "垫高绳索站姿侧屈", "站姿水平伐木"],
    "2026-11-06": ["Smith Bench Press", "坐姿飞鸟", "Dual Pulley Low Row", "Dual Pulley Pulldown", "Smith shoulder press", "坐姿哑铃侧平举", "绳索反向飞鸟", "负重仰卧起坐"],
}
SECTIONS = {
    "2026-11-02": "11 月 2 日，周一：胸＋肩",
    "2026-11-04": "11 月 4 日，周三：背＋腹",
    "2026-11-06": "11 月 6 日，周五：胸背肩综合＋腹",
}
TITLES = {"2026-11-02": "胸＋肩力量 · 递减", "2026-11-04": "背＋腹力量 · 递减", "2026-11-06": "胸背肩综合＋腹 · 力竭"}
COMPOUNDS = {"Smith Bench Press", "器械上斜卧推", "Smith shoulder press", "Dual Pulley Low Row", "Dual Pulley Pulldown", "Barbell Row"}
PRIMARY = {"Smith Bench Press", "Dual Pulley Low Row"}
KNOWN = {
    "2026-11-02": {
        "Smith Bench Press": ([25, 30, 35, 40], "single", "每侧片重，不含杆"),
        "站姿绳索夹胸": ([7.5, 10, 12.5, 15], "single", "每侧配重栈"),
        "Smith shoulder press": ([40, 45, 50, 55], "single", "每侧片重，不含杆"),
    },
    "2026-11-04": {
        "Barbell Row": ([12.5, 17.5, 22.5, 27.5], "single", "每侧片重，不含杆"),
        "杠铃片胸前转体": ([10, 12.5, 15, 17.5], "bilateral", "双手持片总重"),
    },
    "2026-11-06": {
        "Smith Bench Press": ([25, 30, 35, 40], "single", "每侧片重，不含杆；参考周一实际"),
        "Smith shoulder press": ([40, 45, 50, 55], "single", "每侧片重，不含杆；参考周一实际"),
    },
}


def stable(*parts):
    return str(uuid.uuid5(NAMESPACE, ":".join((REVIEW_SHA, *map(str, parts))))).upper()


def rows_for(source, section):
    body = source.split("## " + section, 1)[1].split("\n## ", 1)[0]
    rows = [line for line in body.splitlines() if re.match(r"^\| [1-8] \|", line)]
    result = []
    for row in rows:
        fields = [value.strip() for value in row.strip("|").split("|")]
        rest = re.fullmatch(r"(\d+) 秒", fields[2])
        if not rest:
            raise ValueError("计划休息无法识别：" + row)
        result.append((fields[1], int(rest.group(1)), fields[3]))
    return result


def planned_notes(day, name):
    if day == "2026-11-02" and name == "Smith Bench Press":
        return ("第4组约8次并安全锁杆后，如能快速对称换片，每侧由40降至30kg，接续约6–10次至技术力竭。"
                "不能安全快速换片时移至器械上斜卧推第4组后；两种强化不同时做。"
                "如两台均不适合快速减重且保护可靠，史密斯第4组改技术力竭；保护不足保留1–2次余力并跳过。"
                "延伸段实际重量、次数写动作备注。")
    if day == "2026-11-02" and name == "器械上斜卧推":
        return ("仅当史密斯无法安全快速换片时，本动作第4组后快速降至末组约75%–85%或邻近档，"
                "接续约6–10次至技术力竭；本课只做一次强化。延伸段实际重量、次数写动作备注。")
    if day == "2026-11-04" and name == "Dual Pulley Low Row":
        return ("第4组后立即降约20%–25%或邻近档，接续约6–10次至技术力竭。若末组为该机显示40kg，"
                "30kg为条件候选。先核原机、单位及侧别；延伸段实际重量、次数写动作备注。")
    if day == "2026-11-06" and name == "Smith Bench Press":
        return ("第4组以8次为目标，安全限位或保护可靠时做到技术力竭；实际次数可能高于或低于8。"
                "保护不足时留1–2次余力。周一实际与当天恢复优先；不额外接递减段。")
    return ""


def make_exercise(day, name, row):
    exercise_id, equipment = CATALOG[name]
    display, rest, row_notes = row
    numeric = KNOWN[day].get(name)
    step = 5 if name in COMPOUNDS else 2.5
    side = numeric[1] if numeric else "unknown"
    guidance = ("重量口径：" + numeric[2] + "；条件目标 " + "、".join(f"{x:g}" for x in numeric[0]) + " kg。"
                "同器械、同口径并热身合适时参考；实际输入留空。") if numeric else (
                f"重量口径：同机及侧别待核。首组校准为W，后续每组加{step:g}kg；实际输入留空。")
    rep_side = "single" if name in {"垫高绳索站姿侧屈", "站姿水平伐木"} else (
        "bilateral" if name in {"Smith Bench Press", "Smith shoulder press", "Barbell Row", "杠铃片胸前转体", "负重仰卧起坐"} else "unknown")
    notes = row_notes.replace("**", "")
    if name in {"垫高绳索站姿侧屈", "站姿水平伐木"}:
        notes += " 每侧均为14、12、10、8次，左右完成计1组。"
    if name == "杠铃片胸前转体":
        notes += " 左右交替总次数14、12、10、8；每侧分别7、6、5、4次。"
    extra = planned_notes(day, name)
    if extra:
        notes += "\n" + extra
    sets = []
    for index, reps in enumerate((14, 12, 10, 8)):
        weight = numeric[0][index] if numeric else 0
        label = f"条件 {weight:g}kg，{numeric[2]}" if numeric else ("首组W，现场校准" if index == 0 else f"W＋{step*index:g}kg，现场校准")
        effort = "热身校准；疼痛、动作失稳或异常疲劳时停止或调整。"
        rir_lower, rir_upper = ((2, 3) if index == 0 or name not in PRIMARY else (1, 2))
        if index == 3 and ((day == "2026-11-02" and name == "Smith Bench Press") or (day == "2026-11-04" and name == "Dual Pulley Low Row")):
            label += "；本组后条件递减"
            effort += " 本组后尽快降重接续6–10次，细节见动作备注。"
        if index == 3 and day == "2026-11-02" and name == "器械上斜卧推":
            effort += " 若史密斯无法安全快速换片，本组后条件递减；详见备注。"
        if index == 3 and day == "2026-11-06" and name == "Smith Bench Press":
            label += "；目标约8次，技术力竭"
            effort += " 仅保护可靠时执行，实际次数按表现记录。"
            rir_lower, rir_upper = (0, 1)
        sets.append({"id": stable(day, name, index + 1), "weight": weight, "reps": reps,
            "weightSide": side, "repsSide": rep_side, "actualDefaultPolicyRaw": "blank",
            "prescription": {"label": label, "repsLower": reps, "repsUpper": reps,
                "rirLower": rir_lower, "rirUpper": rir_upper,
                "restLowerSeconds": rest, "restUpperSeconds": rest, "effortCue": effort}})
    return {"catalogExerciseID": exercise_id, "catalogName": name, "displayName": display,
        "equipment": equipment, "volumeUnit": "kilogram", "loadGuidance": guidance,
        "notes": notes, "plannedSets": sets, "planPattern": "pyramidUp"}


def main():
    review = REVIEW.read_text()
    assert hashlib.sha256(review.encode()).hexdigest() == REVIEW_SHA, "审阅正文变化，停止生成。"
    timestamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    confirmed = ("# 本人确认的训练计划\n\n"
        "本人在本次对话回复“好的”，确认下列完整审阅版及递减段通过动作备注记录的方式。"
        "原文中的待确认措辞保留为审阅时状态。"
        f"审阅正文 SHA-256：{REVIEW_SHA}。本确认记录创建时间：{timestamp}。\n\n" + review)
    source_hash = hashlib.sha256(confirmed.encode()).hexdigest()
    manifest = {"reviewPath": str(REVIEW), "reviewSHA256": REVIEW_SHA, "approval": "本人回复：好的",
        "approvalRecordedAt": timestamp, "state": "PREPARED_NOT_WRITTEN", "days": []}
    guidance = ("本人确认本周三次力量、两次有氧；热身另计。四组14/12/10/8，"
        "主项逐组加5kg，小肌群加2.5kg；目标90分钟。第4组递减或力竭按各动作备注执行，"
        "额外递减段实际重量和次数记动作备注。疼痛、动作不稳或异常疲劳时调整或停止。")
    for day, names in DAY_ORDER.items():
        before = json.loads((RECEIPTS / (day + "-readback.json")).read_text())
        rows = rows_for(review, SECTIONS[day])
        assert len(rows) == len(names)
        exercises = [make_exercise(day, name, row) for name, row in zip(names, rows)]
        packet = {"version": 1, "id": stable(day, "schedule"), "localDay": day,
            "timeZoneIdentifier": "Asia/Shanghai", "title": TITLES[day], "preferenceRevisionCode": "TP-20261021-06",
            "confirmedAt": timestamp, "confirmationReference": "本人在本次对话回复‘好的’，确认完整审阅版及备注记录方式。",
            "sourceMarkdown": confirmed, "sourceSHA256": source_hash, "guidance": guidance, "exercises": exercises,
            "replacement": {"scheduleID": before["packet"]["id"], "packetSHA256": before["packetSHA256"]}}
        path = BASE / (day + "-packet.json")
        data = (json.dumps(packet, ensure_ascii=False, indent=2) + "\n").encode()
        with path.open("xb") as f:
            f.write(data)
        manifest["days"].append({"day": day, "packetID": packet["id"], "packetFile": path.name,
            "packetFileSHA256": hashlib.sha256(data).hexdigest(), "oldID": packet["replacement"]["scheduleID"],
            "oldPacketSHA256": packet["replacement"]["packetSHA256"], "exerciseCount": len(exercises),
            "plannedSets": sum(len(e["plannedSets"]) for e in exercises)})
    with (BASE / "manifest.json").open("x") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
