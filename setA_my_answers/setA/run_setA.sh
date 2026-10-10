#!/usr/bin/env bash
# 사용: ./run_setA.sh [org 별칭]   (생략하면 기본 org)
ORG=${1:+--target-org $1}
cd "$(dirname "$0")"
for i in 1 2 3 4 5 6 7 8 9; do
  echo; echo "===== A$i ====="
  sf data query --file A$i.soql $ORG
done
echo; echo "===== A10 (Anonymous Apex) ====="
sf apex run --file A10.apex $ORG | grep -E "USER_DEBUG|Error|error"
