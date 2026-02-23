#!/bin/bash
# zol2o - Remove unwanted plugins from ALL WP sites (Cloudways)
set -euo pipefail

BASE_DIR="/home/master/applications"
LOG_FILE="/home/master/wp_clean_plugins.log"

REMOVE_PLUGINS=("all-in-one-wp-migration" "all-in-one-wp-migration-unlimited-extension" "wp-rocket")

> "$LOG_FILE"
echo "------ WP CLEAN started at $(date) ------" | tee -a "$LOG_FILE"

# หา wp-config.php ทุกเว็บ (safe: NUL-separated)
mapfile -d '' SITES < <(find -L "$BASE_DIR" -name "wp-config.php" ! -path "*/.*" -print0)
TOTAL="${#SITES[@]}"

if [ "$TOTAL" -eq 0 ]; then
  echo "No WordPress installations found in $BASE_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

echo "Found $TOTAL WordPress sites" | tee -a "$LOG_FILE"

SUCCESS=0
FAILED=0
IDX=0

for config_path in "${SITES[@]}"; do
  ((IDX++))
  SITE_PATH="$(dirname "$config_path")"

  (
    set +e
    cd "$SITE_PATH" || exit 1

    # เช็ค wp-cli
    command -v wp >/dev/null 2>&1 || { echo "[ERR] wp-cli not found"; exit 1; }

    # เช็คว่าเป็น WP ติดตั้งแล้ว
    wp core is-installed --allow-root >/dev/null 2>&1 || exit 0

    DOMAIN="$(wp option get home --allow-root 2>/dev/null || echo "Unknown")"

    echo "------------------------------------------------" | tee -a "$LOG_FILE"
    echo "[$IDX/$TOTAL] $DOMAIN" | tee -a "$LOG_FILE"

    for p in "${REMOVE_PLUGINS[@]}"; do
      if wp plugin is-installed "$p" --allow-root >/dev/null 2>&1; then
        echo "   [FOUND] $p -> deactivate & delete" | tee -a "$LOG_FILE"

        # deactivate ก่อนเสมอ (กันลบพัง)
        wp plugin deactivate "$p" --allow-root >> "$LOG_FILE" 2>&1 || true
        wp plugin delete "$p" --allow-root >> "$LOG_FILE" 2>&1 || true

        # เช็คซ้ำ
        if wp plugin is-installed "$p" --allow-root >/dev/null 2>&1; then
          echo "   [ERR] Could not delete: $p" | tee -a "$LOG_FILE"
        else
          echo "   [OK] Removed: $p" | tee -a "$LOG_FILE"
        fi
      else
        echo "   [SKIP] Not installed: $p" | tee -a "$LOG_FILE"
      fi
    done

    # ล้าง cache เผื่อ wp-rocket เคยทำงาน
    wp cache flush --allow-root >/dev/null 2>&1 || true
    wp varnish purge --allow-root >/dev/null 2>&1 || true

    exit 0
  )

  rc=$?
  if [ $rc -eq 0 ]; then
    ((SUCCESS++))
  else
    ((FAILED++))
    echo "[FAIL] Site path: $SITE_PATH" | tee -a "$LOG_FILE"
  fi
done

echo "------------------------------------------------" | tee -a "$LOG_FILE"
echo "Summary: Success $SUCCESS | Failed $FAILED" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
