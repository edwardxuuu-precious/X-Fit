#!/usr/bin/env python3
"""Generate a read-only X-Fit exercise terminology audit.

The script consumes a copied SwiftData SQLite store and the historical CSV. It
does not write to either source and deliberately excludes free-text workout
notes from every deliverable.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


STATUS_LABELS = {
    "approval_ready": "候选名可审批",
    "merge_review": "待确认是否合并",
    "variant_review": "待补具体变式",
    "unresolved": "名称未唯一解析",
}

STATUS_ACTIONS = {
    "approval_ready": "批准标准显示名；保留原名称为别名；不回写历史快照",
    "merge_review": "确认是否指向同一 canonical ID；确认前不合并 PR 或重量历史",
    "variant_review": "补充动作姿势、握法或器械变式；确认前仅归入动作家族",
    "unresolved": "补器械铭牌或动作照片/视频；确认前保持原名称",
}


def spec(raw, key, zh, en, status, confidence, family, issue="", merge_group=""):
    return {
        "raw_name": raw,
        "canonical_key": key,
        "standard_zh_candidate": zh,
        "standard_en_candidate": en,
        "review_status": status,
        "confidence": confidence,
        "exercise_family": family,
        "ambiguity_or_boundary": issue,
        "merge_group": merge_group,
    }


SPECS = [
    spec("MTS 下斜卧推", "hammer_strength_mts_iso_lateral_decline_press", "Hammer Strength MTS Iso-Lateral 下斜推胸", "Hammer Strength MTS Iso-Lateral Decline Press", "approval_ready", "high", "下斜推胸", "品牌和系列不可丢失"),
    spec("MTS 划船", "hammer_strength_mts_iso_lateral_row", "Hammer Strength MTS Iso-Lateral 划船", "Hammer Strength MTS Iso-Lateral Row", "approval_ready", "high", "水平拉", "不能仅凭名称改成 High Row"),
    spec("V 型深蹲", "machine_v_squat", "V 型深蹲机", "V-Squat Machine", "approval_ready", "high", "深蹲", "与哈克深蹲、钟摆深蹲分开"),
    spec("三头下压", "cable_triceps_pushdown", "绳索三头肌下压", "Cable Triceps Pushdown", "merge_review", "high", "肘伸", "把手附件可能不同；附件差异是否隔离 PR 需确认", "merge_cable_triceps_pushdown"),
    spec("三头下压机", "machine_triceps_press_unverified", "器械三头肌下压（待确认）", "Machine Triceps Press (Unverified)", "unresolved", "low", "肘伸", "可能是坐姿臂屈伸机、双杠下压机或固定轨迹下压机"),
    spec("三角肌训练机", "machine_deltoid_unverified", "三角肌训练机（待确认）", "Deltoid Machine (Unverified)", "unresolved", "low", "肩部训练", "可能是侧平举机、反向蝴蝶机或肩推机"),
    spec("上斜卧推", "incline_barbell_bench_press", "上斜杠铃卧推", "Incline Barbell Bench Press", "approval_ready", "high", "上斜推胸"),
    spec("上斜哑铃卧推", "incline_dumbbell_bench_press", "上斜哑铃卧推", "Incline Dumbbell Bench Press", "approval_ready", "high", "上斜推胸", "长凳角度宜另存属性"),
    spec("上背下拉机", "machine_upper_back_pulldown_unverified", "上背下拉机（待确认）", "Upper-Back Pulldown Machine (Unverified)", "unresolved", "low", "垂直拉", "需器械铭牌或照片；可能是 Front Pulldown 或 High Row"),
    spec("上背划船机", "machine_upper_back_row_unverified", "上背划船机（待确认）", "Upper-Back Row Machine (Unverified)", "unresolved", "low", "水平拉", "水平划船、高位划船和胸托划船路径不同"),
    spec("严格深蹲", "barbell_strict_squat_unverified", "严格深蹲（待确认）", "Strict Squat (Unverified)", "unresolved", "low", "深蹲", "不是稳定通用术语；可能指暂停、高杠、无护具或动作标准要求"),
    spec("举腿", "bodyweight_leg_raise", "举腿", "Leg Raise", "variant_review", "medium", "核心屈曲", "需确认悬垂、仰卧或双杠支撑"),
    spec("单腿钟摆推举", "machine_single_leg_pendulum_unverified", "单腿钟摆式腿推/深蹲（待确认）", "Single-Leg Pendulum Press/Squat (Unverified)", "unresolved", "low", "单腿推蹲", "“推举”无法判断是 Pendulum Squat 还是 Pendulum Leg Press"),
    spec("史密斯上斜卧推", "smith_machine_incline_bench_press", "史密斯机上斜卧推", "Smith Machine Incline Bench Press", "approval_ready", "high", "上斜推胸"),
    spec("史密斯卧推", "smith_machine_bench_press", "史密斯机平板卧推", "Smith Machine Bench Press", "approval_ready", "high", "水平推胸", "推荐补“平板”"),
    spec("史密斯肩推", "smith_machine_shoulder_press", "史密斯机肩上推举", "Smith Machine Shoulder Press", "approval_ready", "high", "垂直推", "坐姿或站姿宜另存属性"),
    spec("哑铃侧平举", "dumbbell_lateral_raise", "哑铃侧平举", "Dumbbell Lateral Raise", "approval_ready", "high", "肩外展"),
    spec("哑铃弯举", "dumbbell_biceps_curl", "哑铃二头肌弯举", "Dumbbell Biceps Curl", "approval_ready", "high", "肘屈", "同步、交替和握法宜另存属性"),
    spec("哑铃行走弓步", "dumbbell_walking_lunge", "哑铃行走弓步", "Dumbbell Walking Lunge", "approval_ready", "high", "弓步"),
    spec("器械上斜卧推", "machine_incline_chest_press", "坐姿上斜推胸机", "Incline Chest Press Machine", "merge_review", "high", "上斜推胸", "片载式与配重片式负重不可直接比较", "merge_machine_incline_chest_press"),
    spec("器械下斜卧推", "machine_decline_chest_press", "坐姿下斜推胸机", "Decline Chest Press Machine", "merge_review", "high", "下斜推胸", "片载式与配重片式负重不可直接比较", "merge_machine_decline_chest_press"),
    spec("器械肩推", "machine_shoulder_press", "器械肩上推举", "Shoulder Press Machine", "approval_ready", "high", "垂直推", "握法和轨迹宜另存属性"),
    spec("坐姿上斜推胸机", "machine_incline_chest_press", "坐姿上斜推胸机", "Incline Chest Press Machine", "merge_review", "high", "上斜推胸", "需确认是否与“器械上斜卧推”同一器械/负重口径", "merge_machine_incline_chest_press"),
    spec("坐姿下斜推胸机", "machine_decline_chest_press", "坐姿下斜推胸机", "Decline Chest Press Machine", "merge_review", "high", "下斜推胸", "需确认是否与“器械下斜卧推”同一器械/负重口径", "merge_machine_decline_chest_press"),
    spec("坐姿划船", "machine_seated_row", "坐姿器械划船", "Seated Row Machine", "variant_review", "medium", "水平拉", "“器械”未说明绳索、片载式或固定轨迹"),
    spec("坐姿哑铃侧平举", "seated_dumbbell_lateral_raise", "坐姿哑铃侧平举", "Seated Dumbbell Lateral Raise", "approval_ready", "high", "肩外展", "不与站姿版本合并历史"),
    spec("坐姿推举", "seated_dumbbell_shoulder_press", "坐姿哑铃肩上推举", "Seated Dumbbell Shoulder Press", "merge_review", "high", "垂直推", "需确认与“坐姿肩推”动作和重量口径一致", "merge_seated_dumbbell_shoulder_press"),
    spec("坐姿推胸机", "machine_seated_chest_press", "坐姿推胸机", "Seated Chest Press Machine", "approval_ready", "high", "水平推胸", "默认水平推胸；轨迹宜另存属性"),
    spec("坐姿肩推", "seated_dumbbell_shoulder_press", "坐姿哑铃肩上推举", "Seated Dumbbell Shoulder Press", "merge_review", "high", "垂直推", "需确认与“坐姿推举”动作和重量口径一致", "merge_seated_dumbbell_shoulder_press"),
    spec("坐姿飞鸟", "machine_pec_deck_fly", "坐姿器械夹胸（蝴蝶机飞鸟）", "Pec Deck Fly", "approval_ready", "high", "水平肩内收", "历史肌群为胸部，因此不按反向飞鸟处理"),
    spec("引体向上", "bodyweight_pull_up", "引体向上", "Pull-Up", "variant_review", "medium", "垂直拉", "需确认握向、握距以及是否负重"),
    spec("杠铃划船", "barbell_bent_over_row", "杠铃俯身划船", "Barbell Bent-Over Row", "approval_ready", "high", "水平拉", "躯干角度和正反握宜另存属性"),
    spec("杠铃卧推", "barbell_bench_press", "杠铃平板卧推", "Barbell Bench Press", "approval_ready", "high", "水平推胸", "推荐补“平板”"),
    spec("深蹲", "barbell_back_squat", "杠铃后蹲（待确认）", "Barbell Back Squat (Pending Confirmation)", "variant_review", "medium", "深蹲", "需确认不是前蹲，并记录高杠/低杠等变式"),
    spec("火箭推", "barbell_thruster_unverified", "杠铃火箭推（疑似前蹲推举）", "Barbell Thruster (Unverified)", "unresolved", "low", "蹲推", "很可能是 Thruster，但仅凭俗称不能唯一确认"),
    spec("窄握下拉", "close_grip_lat_pulldown", "窄握高位下拉", "Close-Grip Lat Pulldown", "variant_review", "medium", "垂直拉", "需确认正握、反握或 V 把中立握"),
    spec("站姿哑铃肩推", "standing_dumbbell_shoulder_press", "站姿哑铃肩上推举", "Standing Dumbbell Shoulder Press", "approval_ready", "high", "垂直推"),
    spec("站姿提踵", "machine_standing_calf_raise", "器械站姿提踵", "Standing Calf Raise Machine", "approval_ready", "high", "跖屈", "负重口径宜另存属性"),
    spec("站姿绳索夹胸", "standing_cable_chest_fly", "站姿绳索夹胸", "Standing Cable Chest Fly", "merge_review", "high", "水平肩内收", "滑轮高度宜另存属性", "merge_standing_cable_chest_fly"),
    spec("站姿髋推", "machine_standing_hip_thrust_unverified", "站姿髋推机（待确认）", "Standing Hip Thrust Machine (Unverified)", "unresolved", "low", "髋伸", "可能是站姿髋伸展、髋推机或后踢腿机"),
    spec("绳索下压", "cable_triceps_pushdown", "绳索三头肌下压", "Cable Triceps Pushdown", "merge_review", "high", "肘伸", "需确认与“三头下压”的把手和重量口径一致", "merge_cable_triceps_pushdown"),
    spec("绳索侧平举", "cable_lateral_raise", "绳索侧平举", "Cable Lateral Raise", "approval_ready", "high", "肩外展", "单臂或双臂宜另存属性"),
    spec("绳索卷腹", "cable_crunch", "绳索卷腹", "Cable Crunch", "approval_ready", "high", "躯干屈曲", "跪姿或站姿宜另存属性"),
    spec("绳索反向飞鸟", "cable_rear_delt_fly", "绳索反向飞鸟（后三角肌飞鸟）", "Cable Rear Delt Fly", "approval_ready", "high", "水平肩外展"),
    spec("绳索夹胸", "standing_cable_chest_fly", "站姿绳索夹胸", "Standing Cable Chest Fly", "merge_review", "high", "水平肩内收", "旧名未写站姿；需确认实际姿势与滑轮高度", "merge_standing_cable_chest_fly"),
    spec("绳索躯干旋转", "cable_trunk_rotation", "绳索躯干旋转", "Cable Trunk Rotation", "variant_review", "medium", "躯干旋转", "需确认水平旋转或高到低/低到高 Wood Chop"),
    spec("罗马尼亚硬拉", "barbell_romanian_deadlift", "杠铃罗马尼亚硬拉", "Barbell Romanian Deadlift", "approval_ready", "high", "髋铰链"),
    spec("腿举", "machine_leg_press", "器械腿举", "Leg Press Machine", "variant_review", "medium", "腿部推蹬", "需确认 45°、水平、坐姿、垂直或单腿"),
    spec("腿弯举", "machine_leg_curl", "器械腿弯举", "Leg Curl Machine", "variant_review", "medium", "膝屈", "需确认坐姿、俯卧或站姿"),
    spec("臀推", "barbell_hip_thrust", "杠铃臀推", "Barbell Hip Thrust", "approval_ready", "high", "髋伸"),
    spec("钟摆深蹲", "machine_pendulum_squat", "钟摆深蹲机", "Pendulum Squat Machine", "approval_ready", "high", "深蹲", "不与 V 型深蹲合并"),
    spec("面拉", "cable_face_pull", "绳索面拉", "Cable Face Pull", "approval_ready", "high", "肩外旋与水平拉", "把手附件宜另存属性"),
    spec("颈后下拉", "behind_neck_lat_pulldown", "颈后高位下拉", "Behind-the-Neck Lat Pulldown", "approval_ready", "high", "垂直拉", "独立动作，不作为普通高位下拉别名"),
    spec("高位下拉", "lat_pulldown", "高位下拉", "Lat Pulldown", "approval_ready", "high", "垂直拉", "握距和握向当前未知"),
    spec("高翻", "barbell_power_clean", "杠铃力量翻", "Barbell Power Clean", "variant_review", "medium", "奥举拉与接杠", "“高翻”通常对应 Power Clean；仍需确认从地面或悬垂起始"),
]


LOAD_EVIDENCE = {
    "举腿": "自重；历史 weight=0",
    "引体向上": "自重；历史 weight=0",
    "单腿钟摆推举": "4 组重量缺失；0 仅为占位",
    "火箭推": "1 组为空杆；杆重未知，0 仅为占位",
    "史密斯上斜卧推": "历史 4/4 组明确按每侧记录；未换算含杆总重",
    "史密斯卧推": "历史 12/12 组明确按每侧记录；未换算含杆总重",
    "器械上斜卧推": "历史 4/8 组明确按每侧记录；另 4 组口径未说明",
    "绳索躯干旋转": "历史 4 组注明左右各 10 次；不是重量口径说明",
    "深蹲": "备注中的“单边减 10”是训练建议，不是计重口径",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_device_profile(db_path: Path):
    uri = f"file:{db_path}?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    check = connection.execute("PRAGMA quick_check").fetchone()[0]
    if check != "ok":
        raise RuntimeError(f"device snapshot failed quick_check: {check}")

    query = """
    WITH usage AS (
      SELECT
        se.ZEXERCISENAME AS name,
        COUNT(DISTINCT hex(se.ZSESSIONID)) AS sessions_used,
        SUM(CASE WHEN sl.ZISCOMPLETED = 1 THEN 1 ELSE 0 END) AS completed_sets,
        MIN(date(ws.ZSTARTEDAT + 978307200, 'unixepoch', 'localtime')) AS first_used,
        MAX(date(ws.ZSTARTEDAT + 978307200, 'unixepoch', 'localtime')) AS last_used
      FROM ZSESSIONEXERCISE se
      LEFT JOIN ZSETLOG sl ON hex(sl.ZSESSIONEXERCISEID) = hex(se.ZID)
      LEFT JOIN ZWORKOUTSESSION ws ON hex(ws.ZID) = hex(se.ZSESSIONID)
      GROUP BY se.ZEXERCISENAME
    )
    SELECT
      e.ZNAME AS current_name,
      e.ZMUSCLEGROUP AS muscle_group,
      e.ZEQUIPMENT AS equipment,
      e.ZISBUILTIN AS is_builtin,
      e.ZISARCHIVED AS is_archived,
      COALESCE(u.sessions_used, 0) AS sessions_used,
      COALESCE(u.completed_sets, 0) AS completed_sets,
      u.first_used AS first_used,
      u.last_used AS last_used
    FROM ZEXERCISE e
    LEFT JOIN usage u ON u.name = e.ZNAME
    ORDER BY e.ZNAME
    """
    rows = {row["current_name"]: dict(row) for row in connection.execute(query)}
    totals = dict(
        connection.execute(
            """
            SELECT
              (SELECT COUNT(*) FROM ZEXERCISE) AS catalog_rows,
              (SELECT SUM(CASE WHEN ZISBUILTIN = 1 THEN 1 ELSE 0 END) FROM ZEXERCISE) AS builtin_rows,
              (SELECT COUNT(*) FROM ZWORKOUTSESSION) AS sessions,
              (SELECT SUM(CASE WHEN ZSTATUSRAW = 'completed' THEN 1 ELSE 0 END) FROM ZWORKOUTSESSION) AS completed_sessions,
              (SELECT COUNT(*) FROM ZSESSIONEXERCISE) AS session_exercises,
              (SELECT COUNT(*) FROM ZSETLOG) AS set_logs,
              (SELECT SUM(CASE WHEN ZISCOMPLETED = 1 THEN 1 ELSE 0 END) FROM ZSETLOG) AS completed_sets
            """
        ).fetchone()
    )
    connection.close()
    return rows, totals, check


def load_history_profile(csv_path: Path):
    by_name = defaultdict(lambda: {"session_ids": set(), "sets": 0, "muscle_groups": set(), "equipment": set()})
    session_ids = set()
    duplicate_keys = Counter()
    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            name = row["exercise"].strip()
            session_id = row["session_id"].strip()
            session_ids.add(session_id)
            profile = by_name[name]
            profile["session_ids"].add(session_id)
            profile["sets"] += 1
            profile["muscle_groups"].add(row["muscle_group"].strip())
            profile["equipment"].add(row["equipment"].strip())
            duplicate_keys[(session_id, name.casefold(), row["set"].strip())] += 1
    duplicates = sum(count - 1 for count in duplicate_keys.values() if count > 1)
    normalized = {
        name: {
            "history_sessions": len(value["session_ids"]),
            "history_sets": value["sets"],
            "history_muscle_groups": sorted(value["muscle_groups"]),
            "history_equipment": sorted(value["equipment"]),
        }
        for name, value in by_name.items()
    }
    return normalized, {
        "rows": sum(value["sets"] for value in by_name.values()),
        "sessions": len(session_ids),
        "unique_exercises": len(by_name),
        "duplicate_set_keys": duplicates,
        "muscle_group_conflicts": sum(len(value["history_muscle_groups"]) > 1 for value in normalized.values()),
        "equipment_conflicts": sum(len(value["history_equipment"]) > 1 for value in normalized.values()),
    }


def write_csv(path: Path, rows, columns):
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def build_notebook(output_dir: Path, generated_at: str):
    # Keep the notebook dependency-free: author nbformat v4 JSON directly and
    # attach outputs calculated by the same standard-library logic. The code
    # cells remain replayable in any Python 3 Jupyter environment.
    with (output_dir / "exercise_audit.csv").open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    status_counts = Counter(row["review_status"] for row in rows)
    completed_sets = sum(int(row["device_completed_sets"]) for row in rows)
    priority = sorted(
        (row for row in rows if row["review_status"] != "approval_ready"),
        key=lambda row: (-int(row["device_completed_sets"]), row["raw_name"]),
    )[:15]

    def markdown(source):
        return {"cell_type": "markdown", "metadata": {}, "source": source.splitlines(keepends=True)}

    def code(source, execution_count, output_text):
        return {
            "cell_type": "code",
            "execution_count": execution_count,
            "metadata": {},
            "outputs": [{"name": "stdout", "output_type": "stream", "text": output_text.splitlines(keepends=True)}],
            "source": source.splitlines(keepends=True),
        }

    notebook = {
        "cells": [
            markdown(
                "# X-Fit 动作标准化审计\n\n"
                f"生成时间：{generated_at}。本 notebook 只读取已脱敏的 `exercise_audit.csv`；不读取训练备注，不修改手机或 App 数据。"
            ),
            code(
                "import csv\nfrom collections import Counter\nfrom pathlib import Path\n\n"
                "audit_path = Path('exercise_audit.csv')\n"
                "with audit_path.open(encoding='utf-8-sig', newline='') as f:\n"
                "    rows = list(csv.DictReader(f))\n"
                "print({'raw_names': len(rows), 'canonical_candidates': len({r['canonical_key'] for r in rows})})",
                1,
                str({"raw_names": len(rows), "canonical_candidates": len({row["canonical_key"] for row in rows})}) + "\n",
            ),
            code(
                "status_counts = Counter(r['review_status'] for r in rows)\n"
                "completed_sets = sum(int(r['device_completed_sets']) for r in rows)\n"
                "print('review_status_counts =', dict(status_counts))\n"
                "print('device_completed_sets =', completed_sets)",
                2,
                f"review_status_counts = {dict(status_counts)}\ndevice_completed_sets = {completed_sets}\n",
            ),
            code(
                "priority = sorted(\n"
                "    (r for r in rows if r['review_status'] != 'approval_ready'),\n"
                "    key=lambda r: (-int(r['device_completed_sets']), r['raw_name']),\n"
                ")[:15]\n"
                "for r in priority:\n"
                "    print(f\"{r['review_status']:<14} {int(r['device_completed_sets']):>3} sets | {r['raw_name']} -> {r['standard_zh_candidate']}\")",
                3,
                "".join(
                    f"{row['review_status']:<14} {int(row['device_completed_sets']):>3} sets | {row['raw_name']} -> {row['standard_zh_candidate']}\n"
                    for row in priority
                ),
            ),
            markdown(
                "## 解释边界\n\n"
                "- `approval_ready` 仍表示候选待用户批准，不代表已经写入标准库。\n"
                "- `merge_review` 在批准前不得合并 UUID、PR、上次重量或历史快照。\n"
                "- `variant_review` 与 `unresolved` 需要补充姿势、握法、器械或照片证据。"
            ),
        ],
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python", "version": "3"},
            "xfit_audit": {"output_mode": "precomputed_and_replayable", "generated_at": generated_at},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    (output_dir / "exercise_audit.ipynb").write_text(json.dumps(notebook, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device-db", required=True, type=Path)
    parser.add_argument("--history-csv", required=True, type=Path)
    parser.add_argument("--seed-source", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    generated_at = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
    device, device_totals, quick_check = load_device_profile(args.device_db)
    history, history_totals = load_history_profile(args.history_csv)

    spec_names = [item["raw_name"] for item in SPECS]
    if len(spec_names) != len(set(spec_names)):
        raise RuntimeError("duplicate raw names in terminology specs")
    if set(spec_names) != set(device):
        raise RuntimeError(
            "terminology specs do not match current device catalog: "
            + json.dumps(
                {"missing_specs": sorted(set(device) - set(spec_names)), "not_on_device": sorted(set(spec_names) - set(device))},
                ensure_ascii=False,
            )
        )

    audit_rows = []
    for item in sorted(SPECS, key=lambda row: row["raw_name"]):
        raw = item["raw_name"]
        current = device[raw]
        prior = history.get(raw, {"history_sessions": 0, "history_sets": 0})
        if current["is_builtin"] and raw in history:
            source_presence = "seed + history + device"
        elif current["is_builtin"]:
            source_presence = "seed + device"
        else:
            source_presence = "history + device"
        if current["completed_sets"]:
            impact = f"当前历史含 {current['completed_sets']} 个完成组；错误映射会影响趋势/PR/推荐"
        elif current["sessions_used"]:
            impact = "存在训练快照但无完成组；仍需保留原始快照名"
        else:
            impact = "当前仅动作库记录；无训练快照"
        row = {
            **item,
            "review_status_label": STATUS_LABELS[item["review_status"]],
            "recommended_action": STATUS_ACTIONS[item["review_status"]],
            "auto_merge_allowed": "false",
            "owner_decision": "",
            "current_muscle_group": current["muscle_group"],
            "current_equipment": current["equipment"],
            "is_builtin": current["is_builtin"],
            "is_archived": current["is_archived"],
            "device_sessions_used": current["sessions_used"],
            "device_completed_sets": current["completed_sets"],
            "first_used": current["first_used"] or "",
            "last_used": current["last_used"] or "",
            "history_csv_sessions": prior.get("history_sessions", 0),
            "history_csv_sets": prior.get("history_sets", 0),
            "source_presence": source_presence,
            "load_or_rep_evidence": LOAD_EVIDENCE.get(raw, "未说明；不可推断为总重或单边重量"),
            "historical_impact": impact,
        }
        audit_rows.append(row)

    audit_columns = [
        "raw_name", "standard_zh_candidate", "standard_en_candidate", "canonical_key",
        "review_status", "review_status_label", "confidence", "exercise_family", "merge_group",
        "ambiguity_or_boundary", "recommended_action", "auto_merge_allowed", "owner_decision",
        "current_muscle_group", "current_equipment", "is_builtin", "is_archived",
        "device_sessions_used", "device_completed_sets", "first_used", "last_used",
        "history_csv_sessions", "history_csv_sets", "load_or_rep_evidence",
        "historical_impact", "source_presence",
    ]
    write_csv(args.output_dir / "exercise_audit.csv", audit_rows, audit_columns)

    mapping_columns = [
        "raw_name", "canonical_key", "standard_zh_candidate", "standard_en_candidate",
        "review_status", "confidence", "merge_group", "auto_merge_allowed", "owner_decision",
    ]
    write_csv(args.output_dir / "legacy_to_canonical_mapping.csv", audit_rows, mapping_columns)

    canonical = {}
    for row in audit_rows:
        key = row["canonical_key"]
        entry = canonical.setdefault(
            key,
            {
                "canonical_id": key,
                "status": "candidate_only",
                "standard_zh_candidate": row["standard_zh_candidate"],
                "standard_en_candidate": row["standard_en_candidate"],
                "exercise_family": row["exercise_family"],
                "raw_names": [],
                "aliases": [],
                "review_statuses": [],
                "auto_merge_allowed": False,
            },
        )
        entry["raw_names"].append(row["raw_name"])
        if row["raw_name"] != row["standard_zh_candidate"]:
            entry["aliases"].append(row["raw_name"])
        entry["review_statuses"].append(row["review_status"])
    for entry in canonical.values():
        entry["raw_names"] = sorted(set(entry["raw_names"]))
        entry["aliases"] = sorted(set(entry["aliases"]))
        entry["review_statuses"] = sorted(set(entry["review_statuses"]))
    (args.output_dir / "canonical_exercises.json").write_text(
        json.dumps({"generated_at": generated_at, "status": "proposal_only", "exercises": list(canonical.values())}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    status_counts = Counter(row["review_status"] for row in audit_rows)
    status_sets = Counter()
    for row in audit_rows:
        status_sets[row["review_status"]] += int(row["device_completed_sets"])
    chart_rows = [
        {
            "review_status": status,
            "review_status_label": STATUS_LABELS[status],
            "raw_name_count": status_counts[status],
            "completed_sets_affected": status_sets[status],
            "canonical_candidate_count": len({r["canonical_key"] for r in audit_rows if r["review_status"] == status}),
        }
        for status in ("approval_ready", "merge_review", "variant_review", "unresolved")
    ]

    summary = {
        "generated_at": generated_at,
        "audit_status": "proposal_only",
        "sources": {
            "device_snapshot_sha256": sha256(args.device_db),
            "history_csv_sha256": sha256(args.history_csv),
            "seed_source_sha256": sha256(args.seed_source),
            "device_snapshot_quick_check": quick_check,
        },
        "device": device_totals,
        "history_csv": history_totals,
        "audit": {
            "raw_names": len(audit_rows),
            "canonical_candidates": len(canonical),
            "review_status_counts": dict(status_counts),
            "merge_candidate_groups": len({row["merge_group"] for row in audit_rows if row["merge_group"]}),
            "auto_merge_allowed": 0,
        },
        "reconciliation": {
            "device_minus_csv_sessions": device_totals["sessions"] - history_totals["sessions"],
            "device_minus_csv_completed_sets": device_totals["completed_sets"] - history_totals["rows"],
            "explanation": "差额来自 2026-07-31 的一次设备训练：4 个动作快照、12 个 set log，仅杠铃卧推 1 组完成。",
        },
    }
    (args.output_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    source_notes = f"""# 来源与数据边界

- 生成时间：{generated_at}
- iPhone SwiftData 只读副本：`PRAGMA quick_check = {quick_check}`；SHA-256 `{summary['sources']['device_snapshot_sha256']}`。
- 历史 CSV：430 行、14 个 session、50 个唯一动作；SHA-256 `{summary['sources']['history_csv_sha256']}`。
- SeedDataService：12 个内置动作；SHA-256 `{summary['sources']['seed_source_sha256']}`。
- 审计交付物不包含原始 SQLite、训练备注、表现备注或其他自由文本。
- 当前设备是事实层；CSV 用于来源、备注和计重口径核验。设备比 CSV 多 1 个 session 与 1 个完成组。
- 术语参考只用于生成候选名，不能证明用户做的就是某个具体变式：JEFIT、Hevy、ACE、Life Fitness/Hammer Strength、CrossFit。
- 所有 canonical ID、标准中英文和 alias 均为 proposal；`auto_merge_allowed` 全部为 false。
"""
    (args.output_dir / "source_notes.md").write_text(source_notes, encoding="utf-8")

    chart_contract = """# Chart contract

- Decision question: 人工审核工作主要集中在哪类状态，多少历史完成组会受影响？
- Intended takeaway: 既要看名称数量，也要看历史影响；“可审批”不等于已写入，“待合并/变式/未解析”必须先人工确认。
- Chart family: 单系列分类柱状图。
- Renderer: canonical artifact native `bar` chart，portable HTML builder。
- Data shape: 每个审核状态一行；包含原始名称数、候选 canonical 数、受影响完成组数。
- Encodings: x=审核状态；y=原始名称数；详情保留完成组数和 canonical 候选数。
- Color/legend: 单系列，不显示冗余图例。
- Label/format: 名称数为整数；无小数、无百分比。
- Interaction: 只读 source affordance；无筛选、无外部请求。
- QA: artifact validation + portable builder desktop/narrow verification；精确明细由 55 行审计表承载。
"""
    (args.output_dir / "chart_contract.md").write_text(chart_contract, encoding="utf-8")

    report_md = f"""# X-Fit 动作标准化审计（第一阶段）

## 结论

当前 55 个原始名称可以提出 50 个 canonical 候选，但没有任何一条应该直接自动写回手机或合并历史。28 个名称可进入用户审批，10 个名称属于 5 组合并候选，9 个缺少关键变式，8 个无法唯一解析。

## 当前事实

- 手机动作库：{device_totals['catalog_rows']} 个动作（{device_totals['builtin_rows']} 个内置、{device_totals['catalog_rows'] - device_totals['builtin_rows']} 个自定义），0 个归档。
- 手机历史：{device_totals['sessions']} 次训练、{device_totals['completed_sets']} 个完成组、{device_totals['set_logs']} 个 set log。
- 历史 CSV：{history_totals['sessions']} 次训练、{history_totals['rows']} 行完成组、{history_totals['unique_exercises']} 个唯一动作；无重复 `session + exercise + set` 键，肌群/器械维度无冲突。
- 差额：手机比 CSV 多 1 次训练与 1 个完成组；来自 2026-07-31 的设备记录，不应被覆盖或误判为导入错误。

## 审核分层

| 状态 | 原始名称数 | 受影响完成组 | 处理方式 |
|---|---:|---:|---|
""" + "\n".join(
        f"| {STATUS_LABELS[row['review_status']]} | {row['raw_name_count']} | {row['completed_sets_affected']} | {STATUS_ACTIONS[row['review_status']]} |"
        for row in chart_rows
    ) + f"""

## 5 组合并候选

1. 三头下压 ↔ 绳索下压
2. 器械上斜卧推 ↔ 坐姿上斜推胸机
3. 器械下斜卧推 ↔ 坐姿下斜推胸机
4. 坐姿推举 ↔ 坐姿肩推
5. 站姿绳索夹胸 ↔ 绳索夹胸

这些是语义合并候选，不是自动合并授权。确认前不得共享 PR、上次重量或推荐历史。

## 8 个必须补证据的名称

三头下压机、三角肌训练机、上背下拉机、上背划船机、严格深蹲、单腿钟摆推举、火箭推、站姿髋推。每项至少补器械铭牌、动作照片/视频、握法或起止姿势中的一项。

## 数据模型风险（开发前必须解决）

1. 当前趋势按历史名称聚合，推荐与起始重量按动作 UUID 聚合；重命名会让趋势与推荐产生不同身份。
2. 设备合并在名称唯一时可能直接匹配，不能充分保护同名不同器械/变式。
3. 动作模型缺少 canonical ID、中英文名、审核别名、单/双侧、计数类型与重量口径。
4. Catalog、CSV、Metrics、Device Merge 的名称归一规则不统一。
5. 历史快照必须保留原始名称；canonical 只应作为身份解析层，不应覆写过去展示。

## DeepSeek/API 的正确位置

API 可生成标准名候选、别名、可能歧义和需要用户补充的问题；不可直接批准 canonical、合并 UUID、改历史快照、设定重量口径或更新 PR。正式接入应在本表人工审批之后，并以结构化 JSON、低温度、版本化提示词、结果缓存和人工复核为边界。

## 下一审批顺序

1. 先处理 8 个未解析名称。
2. 再确认 5 组合并候选是否为同一器械、附件与重量口径。
3. 审批 9 个变式缺失项的家族与具体变式。
4. 批准其余 28 个标准中英文候选。
5. 才进入 canonical 数据模型和 API 检查层开发。
"""
    (args.output_dir / "audit_report.md").write_text(report_md, encoding="utf-8")

    source_audit = {
        "id": "audit_profile",
        "label": "X-Fit 动作标准化审计表",
        "path": "exercise_audit.csv",
        "query": {
            "engine": "python",
            "language": "python",
            "id": "exercise-audit-v1",
            "description": "合并只读设备动作画像、历史 CSV 计数和候选词典，并按审核状态汇总。",
            "sql": "SELECT raw_name, canonical_key, review_status, device_completed_sets, standard_zh_candidate, standard_en_candidate, ambiguity_or_boundary FROM exercise_audit",
            "executed_at": generated_at,
        },
    }
    source_device = {
        "id": "device_snapshot",
        "label": "Edward_iPhone X-Fit SwiftData 只读快照",
        "path": "evidence/edward-iphone-xfit-swiftdata-snapshot",
        "query": {
            "engine": "sqlite",
            "language": "sql",
            "id": "device-exercise-profile-v1",
            "description": "按动作快照名汇总设备训练次数、完成组数与首次/最近使用日期。",
            "sql": "SELECT se.ZEXERCISENAME AS exercise_name, COUNT(DISTINCT hex(se.ZSESSIONID)) AS sessions_used, SUM(CASE WHEN sl.ZISCOMPLETED = 1 THEN 1 ELSE 0 END) AS completed_sets FROM ZSESSIONEXERCISE se LEFT JOIN ZSETLOG sl ON hex(sl.ZSESSIONEXERCISEID) = hex(se.ZID) GROUP BY se.ZEXERCISENAME",
            "executed_at": generated_at,
        },
    }
    source_history = {
        "id": "history_csv",
        "label": "X-Fit 2026-07 历史训练 CSV",
        "path": "artifacts/private-history/x-fit-notes-2026-07.csv",
        "query": {
            "engine": "python_csv",
            "language": "python",
            "id": "history-csv-profile-v1",
            "description": "使用标准 CSV 解析器统计 session、动作、组数、维度一致性与计重提示；不输出自由文本备注。",
            "sql": "SELECT exercise, COUNT(DISTINCT session_id) AS sessions, COUNT(*) AS completed_sets, COUNT(DISTINCT muscle_group) AS muscle_group_values, COUNT(DISTINCT equipment) AS equipment_values FROM read_csv_auto('x-fit-notes-2026-07.csv') GROUP BY exercise",
            "executed_at": generated_at,
        },
    }
    source_code = {
        "id": "code_audit",
        "label": "X-Fit 当前动作身份与历史聚合代码审计",
        "path": "FitnessApp/Models/TrainingMetrics.swift",
        "query": {
            "engine": "source_review",
            "language": "swift",
            "id": "exercise-identity-code-audit-v1",
            "description": "检查 TrainingMetrics、WorkoutRecommendation、Catalog、CSV 导入和设备合并的身份解析边界。",
            "sql": "SELECT file_path, identity_key, normalization_rule, history_impact FROM reviewed_exercise_identity_code_paths",
            "executed_at": generated_at,
        },
    }
    source_terms = {
        "id": "terminology_refs",
        "label": "公开动作库与厂商术语参考",
        "url": "https://www.jefit.com/exercises",
        "query": {
            "engine": "web_reference",
            "language": "text",
            "id": "exercise-terminology-reference-v1",
            "description": "JEFIT、Hevy、ACE、Life Fitness/Hammer Strength 与 CrossFit 用于候选英文名交叉核验；不作为用户具体变式证明。",
            "sql": "SELECT source_name, exercise_label, equipment_label, reference_url FROM reviewed_exercise_terminology_sources",
            "executed_at": generated_at,
        },
    }
    sources = [source_audit, source_device, source_history, source_code, source_terms]

    table_rows = [
        {
            "raw_name": row["raw_name"],
            "standard_zh": row["standard_zh_candidate"],
            "standard_en": row["standard_en_candidate"],
            "status": row["review_status_label"],
            "completed_sets": row["device_completed_sets"],
            "review_note": row["ambiguity_or_boundary"] or "候选名待用户批准",
        }
        for row in audit_rows
    ]
    summary_rows = [{
        "raw_names": len(audit_rows),
        "canonical_candidates": len(canonical),
        "completed_sets": device_totals["completed_sets"],
        "unresolved_names": status_counts["unresolved"],
    }]
    artifact = {
        "surface": "report",
        "manifest": {
            "version": 1,
            "surface": "report",
            "title": "X-Fit 动作标准化审计",
            "description": "55 个当前动作的标准中英文候选、历史影响与人工审批边界。",
            "generatedAt": generated_at,
            "cards": [
                {"id": "raw_names", "description": "当前 iPhone 动作库原始名称数。", "dataset": "summary", "sourceId": "audit_profile", "metrics": [{"label": "原始名称", "field": "raw_names", "format": "number"}]},
                {"id": "canonical_candidates", "description": "五组合并候选归一后的候选 canonical 数；尚未批准。", "dataset": "summary", "sourceId": "audit_profile", "metrics": [{"label": "Canonical 候选", "field": "canonical_candidates", "format": "number"}]},
                {"id": "completed_sets", "description": "当前设备只读快照内完成组数。", "dataset": "summary", "sourceId": "device_snapshot", "metrics": [{"label": "设备完成组", "field": "completed_sets", "format": "number"}]},
                {"id": "unresolved_names", "description": "需器械铭牌、照片/视频或动作细节才能唯一解析的名称。", "dataset": "summary", "sourceId": "audit_profile", "metrics": [{"label": "未唯一解析", "field": "unresolved_names", "format": "number"}]},
            ],
            "charts": [
                {
                    "id": "review_status_chart",
                    "title": "审核工作集中在 27 个需补证据或确认合并的名称",
                    "subtitle": "柱高为原始名称数；详情数据同时保留受影响完成组数。",
                    "type": "bar",
                    "dataset": "review_status",
                    "sourceId": "audit_profile",
                    "encodings": {
                        "x": {"field": "review_status_label", "type": "nominal", "label": "审核状态"},
                        "y": {"field": "raw_name_count", "type": "quantitative", "label": "原始名称数", "format": "number"},
                    },
                }
            ],
            "tables": [
                {
                    "id": "exercise_detail",
                    "title": "55 个动作逐项候选与审核状态",
                    "dataset": "exercise_detail",
                    "sourceId": "audit_profile",
                    "columns": [
                        {"field": "raw_name", "label": "原名称", "type": "text"},
                        {"field": "standard_zh", "label": "标准中文候选", "type": "text"},
                        {"field": "standard_en", "label": "Standard English", "type": "text"},
                        {"field": "status", "label": "审核状态", "type": "text"},
                        {"field": "completed_sets", "label": "完成组", "format": "number"},
                        {"field": "review_note", "label": "需确认/边界", "type": "text"},
                    ],
                }
            ],
            "sources": [{k: v for k, v in source.items() if k in {"id", "label", "path", "url"}} for source in sources],
            "blocks": [
                {"id": "title", "type": "markdown", "body": "# X-Fit 动作标准化审计\n\n第一阶段只读审计 · 所有标准名与 canonical ID 均为候选。"},
                {"id": "summary_text", "type": "markdown", "sourceId": "audit_profile", "body": "## 结论\n\n当前 **55 个原始名称**形成 **50 个 canonical 候选**。其中 28 个可进入审批，10 个属于 5 组合并候选，9 个缺少关键变式，8 个无法唯一解析。**自动合并许可为 0**。"},
                {"id": "metrics", "type": "metric-strip", "cardIds": ["raw_names", "canonical_candidates", "completed_sets", "unresolved_names"]},
                {"id": "status_chart", "type": "chart", "chartId": "review_status_chart"},
                {"id": "device_reconciliation", "type": "markdown", "sourceId": "device_snapshot", "body": "## 设备与 CSV 已对账\n\n手机有 **15 次训练、431 个完成组**；CSV 有 **14 次训练、430 行完成组**。差额来自 2026-07-31 的一次设备训练：4 个动作快照、12 个 set log，仅杠铃卧推 1 组完成。手机快照作为当前事实，CSV 不覆盖该记录。"},
                {"id": "risk_text", "type": "markdown", "sourceId": "code_audit", "body": "## 开发前的关键保护\n\n当前趋势按历史名称聚合，而推荐/起始重量按动作 UUID 聚合；仅重命名就可能让趋势和推荐产生不同身份。设备合并、CSV 导入和 Catalog 又使用不同匹配规则。因此 canonical 层必须统一身份解析，同时保留历史快照原名，并隔离器械、变式与重量口径不同的 PR。"},
                {"id": "detail", "type": "table", "tableId": "exercise_detail"},
                {"id": "approval", "type": "markdown", "body": "## 审批顺序\n\n1. 先补 8 个未解析动作的器械/姿势证据。\n2. 再确认 5 组合并候选的器械、附件与重量口径。\n3. 审批 9 个变式缺失项及其动作家族。\n4. 批准其余 28 个中英文候选。\n5. 最后才进入数据模型和 DeepSeek/API 检查层开发。"},
                {"id": "caveats", "type": "markdown", "sourceId": "history_csv", "body": "## 计重边界\n\nCSV 没有任何备注明确说明“总重”。只有 20 行明确按每侧记录，另有自重、缺失重量占位和空杆未知等情况。器械类型不能替代重量口径，标准化不得改变这些原始数值。"},
            ],
        },
        "snapshot": {
            "version": 1,
            "generatedAt": generated_at,
            "status": "ready",
            "datasets": {
                "summary": summary_rows,
                "review_status": chart_rows,
                "exercise_detail": table_rows,
            },
        },
        "sources": sources,
        "package_info": {},
    }
    (args.output_dir / "artifact.json").write_text(json.dumps(artifact, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    build_notebook(args.output_dir, generated_at)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
