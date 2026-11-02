#!/usr/bin/env bash

set -u
set -o pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
mode="${1:-help}"

simulator_name="${XFIT_SIMULATOR_NAME:-iPhone 17 Pro}"
xcode_project="${XFIT_XCODE_PROJECT:-FitnessApp.xcodeproj}"
build_jobs="${XFIT_BUILD_JOBS:-2}"
if ! [[ "$build_jobs" =~ ^[1-9][0-9]*$ ]] || (( build_jobs > 16 )); then
  echo "XFIT_BUILD_JOBS 必须为 1–16。" >&2
  exit 2
fi
device_id="${XFIT_DEVICE_ID:-}"
app_group="${XFIT_APP_GROUP:-group.com.edward.FitnessApp}"
bundle_id="${XFIT_BUNDLE_ID:-com.edward.FitnessApp}"
allow_device_install="${XFIT_ALLOW_DEVICE_INSTALL:-0}"
allow_device_tests="${XFIT_ALLOW_DEVICE_TESTS:-0}"
allow_device_ui_tests="${XFIT_ALLOW_DEVICE_UI_TESTS:-1}"
if [[ "$allow_device_ui_tests" != "0" && "$allow_device_ui_tests" != "1" ]]; then
  echo "XFIT_ALLOW_DEVICE_UI_TESTS must be 0 or 1." >&2
  exit 2
fi
run_id="${XFIT_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"
artifact_dir="${XFIT_ARTIFACT_DIR:-$repo_root/artifacts/stage-validation/$run_id}"
report_dir="${XFIT_REPORT_DIR:-$repo_root/outputs/stage-validation/$run_id}"
# Keep signed build products outside Documents/iCloud/File Provider paths.
# Extended attributes added there can make codesign reject embedded extensions.
derived_path="${XFIT_DERIVED_PATH:-/tmp/xfit-stage-validation-$run_id}"
result_rows="$artifact_dir/results.tsv"

usage() {
  cat <<'USAGE'
X-Fit 阶段完整测试入口

用法：
  scripts/xfit-stage-validation.sh non-device
  XFIT_DEVICE_ID='<device-id>' scripts/xfit-stage-validation.sh device
  XFIT_DEVICE_ID='<device-id>' XFIT_ALLOW_DEVICE_INSTALL=1 XFIT_ALLOW_DEVICE_TESTS=1 scripts/xfit-stage-validation.sh all
  scripts/xfit-stage-validation.sh dry-run

模式：
  non-device  静态检查、后端、Simulator 全量单元/UI、通用 iPhoneOS Release 构建
  device      真机预检、活动数据备份、签名构建；安装和真机 XCTest 需显式开关
  all         先 non-device，全部通过后再 device
  dry-run     仅展示将执行的 Gate，不运行构建、测试或设备写入

安全开关：
  XFIT_ALLOW_DEVICE_INSTALL=1  允许覆盖安装并启动；脚本永不卸载或清容器
  XFIT_ALLOW_DEVICE_TESTS=1    允许运行真机单元与 UI 测试
  XFIT_ALLOW_DEVICE_UI_TESTS=0 对已确认暂缓的真机UI记BLOCKED_ENV，单元/恢复/守恒仍执行（默认1）

可选变量：
  XFIT_BUILD_JOBS（默认 2；限制编译并发，不减少测试范围）
  XFIT_SIMULATOR_NAME、XFIT_APP_GROUP、XFIT_BUNDLE_ID、XFIT_RUN_ID
  XFIT_UI_STRESS_CYCLES（默认 5；明确专项压力测试时设为 50）
  XFIT_ARTIFACT_DIR、XFIT_REPORT_DIR、XFIT_DERIVED_PATH、XFIT_XCODE_PROJECT
USAGE
}

record_result() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$result_rows"
}

run_step() {
  step_id="$1"
  label="$2"
  shift 2
  log_file="$artifact_dir/${step_id}.log"
  echo "[$step_id] $label"
  if "$@" >"$log_file" 2>&1; then
    record_result "$step_id" "PASS" "$label" "$log_file"
    return 0
  else
    exit_code=$?
    record_result "$step_id" "FAIL" "$label" "$log_file (exit=$exit_code)"
    return "$exit_code"
  fi
}

run_environment_step() {
  step_id="$1"
  label="$2"
  shift 2
  log_file="$artifact_dir/${step_id}.log"
  echo "[$step_id] $label"
  if "$@" >"$log_file" 2>&1; then
    record_result "$step_id" "PASS" "$label" "$log_file"
    return 0
  else
    exit_code=$?
    record_result "$step_id" "BLOCKED_ENV" "$label" "$log_file (exit=$exit_code)"
    return "$exit_code"
  fi
}

record_not_run() {
  record_result "$1" "$2" "$3" "$4"
  echo "[$1] $2 — $3"
}

copy_device_store() {
  label="$1"
  destination="$artifact_dir/device-data/$label"
  mkdir -p "$destination"
  xcrun devicectl device copy from \
    --device "$device_id" \
    --source 'Library/Application Support' \
    --destination "$destination" \
    --domain-type appGroupDataContainer \
    --domain-identifier "$app_group" \
    --timeout 60 \
    --json-output "$artifact_dir/${label}-copy.json"
}

audit_device_store() {
  label="$1"
  source_dir="$artifact_dir/device-data/$label"
  store_file="$(find "$source_dir" -type f -name '*.store' -print | head -n 1)"
  if [[ -z "$store_file" ]]; then
    echo "未找到 SwiftData .store：$source_dir" >&2
    return 1
  fi

  audit_dir="$artifact_dir/device-audit/$label"
  mkdir -p "$audit_dir"
  sqlite3 "$store_file" 'PRAGMA quick_check;' > "$audit_dir/quick-check.txt"
  if [[ "$(tr -d '\r\n' < "$audit_dir/quick-check.txt")" != "ok" ]]; then
    echo "SQLite quick_check 未通过" >&2
    return 1
  fi

  : > "$audit_dir/files.sha256"
  find "$source_dir" -type f -print \
    | LC_ALL=C sort \
    | while IFS= read -r source_file; do
        shasum -a 256 "$source_file" >> "$audit_dir/files.sha256"
      done

  : > "$audit_dir/core-counts.tsv"
  sqlite3 "$store_file" \
    "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('ZWORKOUTSESSION','ZSESSIONEXERCISE','ZSETLOG','ZMEALENTRY','ZBODYMEASUREMENT','ZSCHEDULEDWORKOUT','ZTRAININGPREFERENCEREVISION','ZTRAININGPROGRAMREVISION','ZJUMPROPEENTRY') ORDER BY name;" \
    | while IFS= read -r table_name; do
        count="$(sqlite3 "$store_file" "SELECT COUNT(*) FROM \"$table_name\";")"
        printf '%s\t%s\n' "$table_name" "$count" >> "$audit_dir/core-counts.tsv"
        sqlite3 "$store_file" "SELECT hex(ZID) FROM \"$table_name\" ORDER BY hex(ZID);" > "$audit_dir/${table_name}-ids.txt"
      done

  core_table_count="$(wc -l < "$audit_dir/core-counts.tsv" | tr -d ' ')"
  if [[ "$core_table_count" != "9" ]]; then
    echo "核心数据表不完整：期望 9 个，实际 $core_table_count 个" >&2
    return 1
  fi
}

compare_device_counts() {
  before_label="$1"
  after_label="$2"
  before_file="$artifact_dir/device-audit/$before_label/core-counts.tsv"
  after_file="$artifact_dir/device-audit/$after_label/core-counts.tsv"
  comparison="$artifact_dir/device-audit/${before_label}-to-${after_label}.txt"
  : > "$comparison"

  while IFS=$'\t' read -r table_name before_count; do
    after_count="$(awk -F '\t' -v table="$table_name" '$1 == table { print $2 }' "$after_file")"
    if [[ -z "$after_count" ]]; then
      echo "$table_name missing after $after_label" | tee -a "$comparison" >&2
      return 1
    fi
    printf '%s\t%s\t%s\n' "$table_name" "$before_count" "$after_count" >> "$comparison"
    if (( after_count < before_count )); then
      echo "$table_name decreased: $before_count -> $after_count" | tee -a "$comparison" >&2
      return 1
    fi
    missing_ids="$(LC_ALL=C comm -23 "$artifact_dir/device-audit/$before_label/${table_name}-ids.txt" "$artifact_dir/device-audit/$after_label/${table_name}-ids.txt")"
    if [[ -n "$missing_ids" ]]; then
      echo "$table_name has missing original identifiers after $after_label" | tee -a "$comparison" >&2
      return 1
    fi
  done < "$before_file"

  # Photo files are durable user records, not a disposable image cache.
  before_photos="$artifact_dir/device-data/$before_label/MealPhotos"
  after_photos="$artifact_dir/device-data/$after_label/MealPhotos"
  if [[ -d "$before_photos" ]]; then
    while IFS= read -r photo_path; do
      photo_relative="${photo_path#"$before_photos"/}"
      if [[ ! -f "$after_photos/$photo_relative" ]] || ! cmp -s "$photo_path" "$after_photos/$photo_relative"; then
        echo "Meal photo missing or changed after $after_label: $photo_relative" | tee -a "$comparison" >&2
        return 1
      fi
    done < <(find "$before_photos" -type f -name '*.jpg' -print)
  fi
}

verify_device_online() {
  details_file="$artifact_dir/device-details.json"
  xcrun devicectl device info details \
    --device "$device_id" \
    --timeout 60 \
    --json-output "$details_file" || return 1

  tunnel_state="$(jq -r '.result.connectionProperties.tunnelState // "unknown"' "$details_file")"
  ddi_available="$(jq -r '.result.deviceProperties.ddiServicesAvailable // false' "$details_file")"
  if [[ "$tunnel_state" != "connected" || "$ddi_available" != "true" ]]; then
    echo "真机开发通道不可用：tunnelState=${tunnel_state}，ddiServicesAvailable=${ddi_available}" >&2
    return 1
  fi
  lock_file="$artifact_dir/device-lock-state.json"
  xcrun devicectl device info lockState --device "$device_id" --timeout 30 --json-output "$lock_file" || return 1
  if [[ "$(jq -r '.result.passcodeRequired' "$lock_file")" != "false" ]]; then
    echo "设备仍需本人解锁；开发通道连接不等于屏幕已解锁，未开始安装或数据写入。" >&2
    return 1
  fi
}

non_device_suite() {
  local_failed=0
  run_step N01 "Git diff 空白与冲突标记检查" git diff --check || local_failed=1
  run_step N02 "Xcode 工程与 Scheme 可读" xcodebuild -project "$xcode_project" -scheme FitnessApp -list || local_failed=1

  if [[ -f EquipmentRecognitionBackend/package.json ]]; then
    run_step N03 "器械识别后端全量测试" npm --prefix EquipmentRecognitionBackend test || local_failed=1
  else
    record_not_run N03 NOT_RUN "器械识别后端不存在" "-"
  fi
  run_step N03B "Mac 餐食交换安全测试" python3 -m unittest discover -s scripts/tests -v || local_failed=1

  run_step N04 "Simulator App 构建" \
    xcodebuild build \
      -jobs "$build_jobs" \
      -project "$xcode_project" \
      -scheme FitnessApp \
      -destination "platform=iOS Simulator,name=$simulator_name" \
      -derivedDataPath "$derived_path" \
      CODE_SIGNING_ALLOWED=NO || local_failed=1

  run_step N05 "Simulator 全量单元测试" \
    xcodebuild test \
      -jobs "$build_jobs" \
      -parallel-testing-enabled NO \
      -collect-test-diagnostics never \
      -project "$xcode_project" \
      -scheme FitnessApp \
      -destination "platform=iOS Simulator,name=$simulator_name" \
      -derivedDataPath "$derived_path" \
      -resultBundlePath "$artifact_dir/non-device-unit.xcresult" \
      -only-testing:FitnessAppTests \
      CODE_SIGNING_ALLOWED=NO || local_failed=1

  run_step N06 "Simulator 全量 UI 测试" \
    xcodebuild test \
      -jobs "$build_jobs" \
      -parallel-testing-enabled NO \
      -collect-test-diagnostics never \
      -project "$xcode_project" \
      -scheme FitnessApp \
      -destination "platform=iOS Simulator,name=$simulator_name" \
      -derivedDataPath "$derived_path" \
      -resultBundlePath "$artifact_dir/non-device-ui.xcresult" \
      -only-testing:FitnessAppUITests \
      CODE_SIGNING_ALLOWED=NO || local_failed=1

  run_step N07 "通用 iPhoneOS Release 无签名构建" \
    xcodebuild build \
      -jobs "$build_jobs" \
      -project "$xcode_project" \
      -scheme FitnessApp \
      -configuration Release \
      -destination 'generic/platform=iOS' \
      -derivedDataPath "$derived_path" \
      CODE_SIGNING_ALLOWED=NO || local_failed=1

  return "$local_failed"
}

device_suite() {
  if [[ -z "$device_id" ]]; then
    record_not_run D00 BLOCKED_ENV "未设置 XFIT_DEVICE_ID" "真机阶段未开始"
    return 2
  fi

  local_failed=0
  if ! run_environment_step D00 "真机在线与开发服务预检" verify_device_online; then
    record_not_run D01 NOT_RUN "真机开发通道不可用，未读取活动 App Group" "依赖 D00"
    record_not_run D02 NOT_RUN "未执行安装前 SQLite 完整性与核心计数" "依赖 D01"
    record_not_run D03 NOT_RUN "设备预检失败，停止后续真机步骤" "-"
    record_unreached_device_steps "依赖 D00；未安装或写入产品数据"
    return 1
  fi
  run_step D01 "安装前活动 App Group 只读备份" copy_device_store pre-install || local_failed=1
  run_step D02 "安装前 SQLite 完整性与核心计数" audit_device_store pre-install || local_failed=1

  if (( local_failed != 0 )); then
    record_not_run D03 NOT_RUN "设备或活动数据预检失败，停止后续真机步骤" "-"
    record_unreached_device_steps "依赖 D01/D02；未安装或写入产品数据"
    return 1
  fi

  run_step D03 "真机签名 Release 构建" \
    xcodebuild build \
      -jobs "$build_jobs" \
      -project "$xcode_project" \
      -scheme FitnessApp \
      -configuration Release \
      -destination "id=$device_id" \
      -derivedDataPath "$derived_path" \
      -allowProvisioningUpdates || local_failed=1

  signed_app="$derived_path/Build/Products/Release-iphoneos/FitnessApp.app"
  if [[ -d "$signed_app" ]]; then
    run_step D04 "签名、entitlements 与版本回读" /bin/bash -c \
      "codesign --verify --deep --strict '$signed_app' && codesign -d --entitlements :- '$signed_app' && /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '$signed_app/Info.plist' && /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' '$signed_app/Info.plist'" || local_failed=1
  else
    record_not_run D04 NOT_RUN "未生成签名 App" "$signed_app"
    local_failed=1
  fi

  if [[ "$allow_device_install" != "1" ]]; then
    record_not_run D05 NOT_RUN "未授权覆盖安装" "设置 XFIT_ALLOW_DEVICE_INSTALL=1"
    record_not_run D06 NOT_RUN "安装后活动数据回读" "依赖 D05"
  elif (( local_failed == 0 )); then
    run_step D05 "真机覆盖安装、启动与版本回读（不卸载、不清容器）" /bin/bash -c \
      "xcrun devicectl device install app --device '$device_id' '$signed_app' --timeout 120 --json-output '$artifact_dir/device-install.json' && xcrun devicectl device process launch --device '$device_id' --terminate-existing --timeout 60 --json-output '$artifact_dir/device-launch.json' '$bundle_id' && xcrun devicectl device info apps --device '$device_id' --bundle-id '$bundle_id' --timeout 60 --json-output '$artifact_dir/device-app-readback.json'" || local_failed=1
    run_step D06A "安装后活动 App Group 只读备份" copy_device_store post-install || local_failed=1
    run_step D06B "安装后 SQLite 完整性与核心计数" audit_device_store post-install || local_failed=1
    run_step D06C "安装前后核心记录不减少" compare_device_counts pre-install post-install || local_failed=1
  else
    record_not_run D05 NOT_RUN "构建或签名门未通过，未安装" "依赖 D03/D04"
    record_not_run D06 NOT_RUN "未安装，未执行安装后数据回读" "依赖 D05"
  fi

  if [[ "$allow_device_tests" != "1" ]]; then
    record_not_run D07 NOT_RUN "未授权真机 XCTest" "设置 XFIT_ALLOW_DEVICE_TESTS=1"
  elif [[ "$allow_device_install" != "1" ]]; then
    record_not_run D07 NOT_RUN "真机测试要求先完成本次候选包覆盖安装" "启用两个真机开关"
  elif (( local_failed == 0 )); then
    run_step D07A "真机全量单元测试" \
      xcodebuild test \
      -jobs "$build_jobs" \
      -parallel-testing-enabled NO \
        -project "$xcode_project" \
        -scheme FitnessApp \
        -destination "id=$device_id" \
        -derivedDataPath "$derived_path" \
        -resultBundlePath "$artifact_dir/device-unit.xcresult" \
        -only-testing:FitnessAppTests \
        -collect-test-diagnostics never \
        -allowProvisioningUpdates || local_failed=1

    if [[ "$allow_device_ui_tests" == "1" ]]; then
      run_step D07B "真机全量 UI 测试" \
        xcodebuild test \
        -jobs "$build_jobs" \
        -parallel-testing-enabled NO \
          -project "$xcode_project" \
          -scheme FitnessApp \
          -destination "id=$device_id" \
          -derivedDataPath "$derived_path" \
          -resultBundlePath "$artifact_dir/device-ui.xcresult" \
          -only-testing:FitnessAppUITests \
          -collect-test-diagnostics never \
          -allowProvisioningUpdates || local_failed=1

    else
      record_not_run D07B BLOCKED_ENV "按已确认停止规则暂缓真机 UI" "XFIT_ALLOW_DEVICE_UI_TESTS=0; 不计为通过"
    fi

    run_step D07C "真机测试后恢复本次签名 Release 并启动回读" /bin/bash -c \
      "xcrun devicectl device install app --device '$device_id' '$signed_app' --timeout 120 --json-output '$artifact_dir/device-final-install.json' && xcrun devicectl device process launch --device '$device_id' --terminate-existing --timeout 60 --json-output '$artifact_dir/device-final-launch.json' '$bundle_id' && xcrun devicectl device info apps --device '$device_id' --bundle-id '$bundle_id' --timeout 60 --json-output '$artifact_dir/device-final-app-readback.json'" || local_failed=1
    run_step D08A "真机测试后活动 App Group 只读备份" copy_device_store post-tests || local_failed=1
    run_step D08B "真机测试后 SQLite 完整性与核心计数" audit_device_store post-tests || local_failed=1
    run_step D08C "安装前到测试后核心记录不减少" compare_device_counts pre-install post-tests || local_failed=1
  else
    record_not_run D07 NOT_RUN "安装前置门未通过，未运行真机 XCTest" "依赖 D03–D06"
    record_not_run D08 NOT_RUN "真机 XCTest 未执行" "依赖 D07"
  fi

  manual_copy="$report_dir/真机人工测试清单.md"
  cp "$repo_root/docs/X-Fit_真机人工测试清单.md" "$manual_copy"
  record_not_run D09 BLOCKED_HUMAN "真机人工体验与系统权限清单" "$manual_copy"
  return "$local_failed"
}

record_unreached_device_steps() {
  local reason="$1"
  record_not_run D04 NOT_RUN "签名、entitlements 与版本回读" "$reason"
  record_not_run D05 NOT_RUN "覆盖安装、启动与版本回读" "$reason"
  record_not_run D06 NOT_RUN "安装后活动数据与守恒" "$reason"
  record_not_run D07 NOT_RUN "真机全量单元/UI 测试" "$reason"
  record_not_run D08 NOT_RUN "真机测试后活动数据与守恒" "$reason"
  record_not_run D09 BLOCKED_HUMAN "真机人工体验与系统权限清单" "$repo_root/docs/X-Fit_真机人工测试清单.md"
}

write_summary() {
  summary="$report_dir/summary.md"
  {
    echo "# X-Fit 阶段测试摘要"
    echo
    echo "- Run ID：\`$run_id\`"
    echo "- 模式：\`$mode\`"
    echo "- 时间：\`$(date '+%Y-%m-%d %H:%M:%S %z')\`"
    echo "- 仓库：\`$repo_root\`"
    echo "- Xcode 工程：\`$xcode_project\`"
    echo "- Git：\`$(git branch --show-current 2>/dev/null || true) / $(git rev-parse --short HEAD 2>/dev/null || true)\`"
    echo "- Artifacts：\`$artifact_dir\`"
    echo
    echo "| Gate | 状态 | 检查 | 证据/说明 |"
    echo "|---|---|---|---|"
    while IFS=$'\t' read -r step_id status label evidence; do
      echo "| $step_id | $status | $label | \`$evidence\` |"
    done < "$result_rows"
    echo
    echo "## 判定边界"
    echo
    echo "- 任一 FAIL 均阻断 GO。"
    echo "- 真机必测项 NOT_RUN、BLOCKED_ENV 或 BLOCKED_HUMAN 时，阶段只能是 PARTIAL/BLOCKED。"
    echo "- 构建、Simulator、覆盖安装、真机 XCTest、活动数据库回读和真人验收不得互相替代。"
  } > "$summary"
  echo "摘要：$summary"
}

dry_run() {
  cat <<'PLAN'
N01 git diff --check
N02 Xcode 工程/Scheme
N03 后端全量测试
N04 Simulator 构建
N05 Simulator 全量单元测试
N06 Simulator 全量 UI 测试
N07 通用 iPhoneOS Release 无签名构建
D00 真机在线门
D01-D02 安装前活动 App Group 备份、quick_check、核心计数
D03-D04 签名 Release 构建、entitlements 与版本
D05-D06 显式授权后覆盖安装、启动、安装后数据守恒
D07-D08 显式授权后真机单元/UI、测试后数据守恒
D09 真人体验、权限、锁屏、真实键盘、动态字体、VoiceOver 清单
PLAN
}

case "$mode" in
  help|-h|--help)
    usage
    exit 0
    ;;
  dry-run)
    dry_run
    exit 0
    ;;
  non-device|device|all)
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

mkdir -p "$artifact_dir" "$report_dir" "$derived_path"
: > "$result_rows"
cd "$repo_root"

overall=0
if [[ "$mode" == "non-device" || "$mode" == "all" ]]; then
  non_device_suite || overall=1
fi

if [[ "$mode" == "device" ]]; then
  device_suite || overall=1
elif [[ "$mode" == "all" ]]; then
  if (( overall == 0 )); then
    device_suite || overall=1
  else
    record_not_run D00 NOT_RUN "非真机 Gate 失败，未进入真机阶段" "-"
  fi
fi

write_summary
exit "$overall"
