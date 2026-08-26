#!/usr/bin/env bash

set -u
set -o pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
title="${1:-}"
requested_slug="${2:-}"
confirmed="${XFIT_CONFIRMED:-0}"
confirmation_note="${XFIT_CONFIRMATION_NOTE:-}"

if [[ -z "$title" ]]; then
  echo "用法：XFIT_CONFIRMED=1 XFIT_CONFIRMATION_NOTE=\"确认摘要\" $0 \"需求标题\" [英文-slug]" >&2
  exit 64
fi

if [[ "$confirmed" != "1" || -z "$confirmation_note" ]]; then
  echo "需求尚未记录用户确认。请先与用户统一需求和验收标准，再设置 XFIT_CONFIRMED=1 与 XFIT_CONFIRMATION_NOTE。" >&2
  exit 65
fi

created_at="$(date '+%Y-%m-%d %H:%M:%S %z')"
day="$(date '+%Y-%m-%d')"
clock="$(date '+%H%M%S')"

if [[ -n "$requested_slug" ]]; then
  slug="$requested_slug"
else
  slug="$(printf '%s' "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-48)"
fi

if [[ -z "$slug" ]]; then
  slug="requirement"
fi

target_dir="$repo_root/docs/requirements/$day"
target_file="$target_dir/${clock}_${slug}.md"
escaped_title="$(printf '%s' "$title" | sed 's/[\\&|]/\\&/g')"
escaped_confirmation_note="$(printf '%s' "$confirmation_note" | sed 's/[\\&|]/\\&/g')"

mkdir -p "$target_dir"
if [[ -e "$target_file" ]]; then
  echo "拒绝覆盖已有需求文件：$target_file" >&2
  exit 73
fi

sed \
  -e "s|# 需求：<标题>|# 需求：$escaped_title|" \
  -e "s|REQ-YYYYMMDD-HHMMSS|REQ-$(date '+%Y%m%d')-$clock|" \
  -e "s|YYYY-MM-DD HH:MM:SS +0800|$created_at|g" \
  -e "s|<确认范围或回复摘要>|$escaped_confirmation_note|" \
  "$repo_root/docs/requirements/TEMPLATE.md" > "$target_file"

echo "$target_file"
