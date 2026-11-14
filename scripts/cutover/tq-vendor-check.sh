#!/usr/bin/env bash
# tq-vendor-check.sh — vendored 生成树与驱动器产物的双向比对。
#
# 为什么是双向：只查 missing（驱动产出而挂载没有）抓不到另一类漂移——挂载里躺着
# 驱动根本不产出的文件，看着像有该能力的实现，实际不被编译、也会在下次重生成时消失。
# 见 PIT-174 与 t-muk19c87-iieq。
#
# 用法：bash scripts/tq-vendor-check.sh [tiqian 根，默认 tiqian]
# 退出码：0 = 每个挂载都干净；1 = 存在漂移（extras / full missing / 声明清单 missing / 内容不一致）；2 = 环境错误
#
# 表格式（8 列，竖线分隔）：
#   标签|模式(full|subset|files)|束 id|挂载路径(相对 tiqian 根)|额外允许的文件模式(逗号分隔)|路径重映射(dest=src,dest=src)|显式清单:该挂载应含的文件(逗号分隔,挂载坐标)|挂载根对应的驱动路径前缀
#   full   —— 挂载必须完整等于驱动产物：missing 与 extras 都必须为零，逐条列出。
#   subset —— 挂载是驱动产物的声明子集（目录专职生成物）：
#             · 显式清单（第 7 列）里的每个文件必须在挂载里，缺的逐条列出并非零退出（「本该搬却忘了搬」）；
#             · 清单外的驱动文件是声明子集余量，只报数；
#             · extras 仍必须为零（目录里出现的未声明文件一律报漂移）。
#   files  —— 目录是混放手写代码的源码包目录，不是专职挂载：只查显式清单声明的那几个
#             生成文件（存在性 + 内容），目录其余内容不查、不算 extras。
#   内容比对（extras/missing 非零时仍然要做——「有漂移」不许掩盖「内容也变了」）：
#     · 非 .ts 文件：逐字节比对。
#     · .ts 文件：先与驱动产物逐字节比；不一致再按既定约定改写后比——约定内容：
#       双引号相对导入说明符（./ 或 ../ 开头、.ts 结尾）改写成 .js，其余字节不动。
#       第三条可接受形态：在上一形态基础上，把仅导入类型的 import { X } 写成
#       import type { X }（verbatimModuleSyntax 的包必须这样写；驱动端不区分）。
#       任一形态一致即算一致，改写约定本身不报漂移。
#     · 同一挂载里同时观察到 verbatim（.ts 说明符）与 rewritten（.js 说明符）两种形态
#       → 单独报警告「形态不统一」；警告不影响退出码。（无相对 .ts 说明符的文件两种
#       形态内容相同，按「形态中性」计，不参与判定。）
#   登记表自检：显式清单里当前驱动不产出的文件 → 单独报警告。该类叫「声明但驱动不产」：
#     属登记表/驱动能力问题（pin 的生成尚不含该文件，或产出步骤是未落地的驱动特性），不是漂移，
#     不影响退出码；成因写在该行的登记表注释里。若 pin 回退把已入库文件从驱动产物里弄丢，
#     同样会触发本警告——那时是真漂移，须按行定夺。
#
# 注入自测与清理纪律（验证闸门本身有效时用；每次注入后必须走完三步，否则不得交回）：
#   1) extras 注入：往挂载写一个驱动不产的文件，例如
#      echo "// gate-test injection" > <挂载>/org/tiqian/protocol/zz_vendor_gate_injected.ts
#      预期：退出码 1、extras 逐条点名该文件。清理：rm 该文件（未跟踪文件，不用 git）。
#   2) missing 注入：rm 挂载里一个驱动产出且被 git 跟踪的文件。
#      预期：退出码 1、missing 逐条点名该文件。清理：git checkout -- <该文件路径>。
#   3) 清理后必查：a) git status --porcelain -- platforms/web engine/src 为空；
#      b) 重跑一次，输出与注入前基线逐字节相同（diff -q）。两者不齐即清理未净。
set -uo pipefail

ROOT="${1:-tiqian}"
if [ ! -d "$ROOT/engine-haxe/out" ]; then
  echo "找不到 $ROOT/engine-haxe/out：先跑驱动器生成，或用正确的 tiqian 根调用" >&2
  exit 2
fi

# 既定约定：双引号相对导入说明符（./ 或 ../ 开头、.ts 结尾）改写成 .js
TS_REWRITE="s|(\")(\\.\.?/[^\\\"]*)\\.ts\1|\1\2.js\1|g"
# 探测：文件是否含双引号相对 .ts 导入说明符（决定该文件的形态是否可观察）
TS_IMPORT_RE="\"\\.\.?/[^\\\"]*\\.ts\""

# 登记表（8 列）。显式清单写挂载坐标：挂载根 = 驱动根时与驱动路径同形；
# 挂载根对应驱动子树时用第 8 列前缀；单文件换位置用第 6 列重映射。
TABLE=(
  "protocol-rust|full|protocol-rust|platforms/web/server/precompute/protocol-gen|||"
  "ffi-rust-engine-gen|full|engine-rust-f64|platforms/web/server/precompute/engine-gen|||"
  "ffi-js-engine-gen|subset|ts|platforms/web/client/engine-runtime/engine-gen|*.json,clreq-exports.ts,org/tiqian/protocol/*||org/tiqian/clreq/BopomofoParser.ts,org/tiqian/clreq/BopomofoReading.ts,org/tiqian/clreq/BopomofoTone.ts,org/tiqian/clreq/NumberSymbolCohesion.ts,org/tiqian/core/EastAsianSpacingData.ts,org/tiqian/core/EastAsianSpacingEdges.ts,org/tiqian/core/EastAsianSpacingValue.ts,org/tiqian/core/IntRange.ts,org/tiqian/core/RoleOverrideInfo.ts,org/tiqian/core/SourceBoundaryBias.ts,org/tiqian/core/SourceInteractionBoundaries.ts,org/tiqian/core/TextRange.ts,org/tiqian/core/TextRangeError.ts,org/tiqian/core/TiqianIllegalArgumentException.ts,org/tiqian/core/UnicodeCombiningMarkData.ts,org/tiqian/core/UnicodeEastAsianSpacing.ts,org/tiqian/core/UnicodeEmojiModifierBaseData.ts,org/tiqian/core/UnicodeExtendedPictographicData.ts,org/tiqian/core/UnicodeNumber.ts,org/tiqian/core/UnicodeNumberData.ts,org/tiqian/core/UnicodeScriptEvidence.ts,org/tiqian/core/UnicodeScriptEvidenceClassifier.ts,org/tiqian/core/UnicodeScriptEvidenceData.ts,org/tiqian/core/UnicodeWordCharacter.ts,org/tiqian/core/UnicodeWordCharacterData.ts,org/tiqian/font/BaselineClass.ts,org/tiqian/font/BaselinePolicy.ts,org/tiqian/font/CjkFontRoleClassifier.ts,org/tiqian/font/FontMetricSource.ts,org/tiqian/font/FontMetrics.ts,org/tiqian/font/FontMetricsPolicy.ts,org/tiqian/font/FontPolicy.ts,org/tiqian/font/FontRole.ts,org/tiqian/font/FontRoleContext.ts,org/tiqian/font/InlineShapingStylePolicy.ts,org/tiqian/font/LayoutFontMetrics.ts,org/tiqian/font/MetricBox.ts,org/tiqian/font/PreferCjkForAmbiguousPunctuationResolver.ts,org/tiqian/font/RawFontMetrics.ts,org/tiqian/font/UnicodeEmojiPresentationData.ts,org/tiqian/font/UnicodeSymbolData.ts,org/tiqian/layout/ContextualDashEllipsisRoleResolver.ts,org/tiqian/layout/ContextualQuoteRoleResolver.ts,org/tiqian/layout/QuotePairAnalyzer.ts,org/tiqian/linebreak/Hyphenator.ts,org/tiqian/linebreak/LiangHyphenator.ts,org/tiqian/linebreak/LineBreakFns.ts,org/tiqian/linebreak/UnicodePunctuationLineBreak.ts,org/tiqian/linebreak/UnicodePunctuationLineBreakData.ts,runtime.ts|"
  # kotlin-protocol-engine（t-muiwi5ft-mc60 Stage1-P3 producer cutover）：engine 侧 Plan 挂载
  # 改为 kotlin-f32 束产物——engine 几何实数是 f32，挂载的生成 PlanLowering/PreparedParagraphFns
  # 必须与 Plan 数据模型同精度才能通过 Kotlin 类型检查（protocol-kotlin 束无 float-precision
  # define，产 Double 形态；该束的 Kotlin 挂载点已随顶层 ffi 目录删除）。Revision.kt 仍来自 protocol-kotlin 束，
  # 列为 allow 额外（files 在驱动 kotlin-f32 产物里不存在）。
  "kotlin-protocol-engine|subset|kotlin-f32|engine/src/commonMain/kotlin/org/tiqian/protocol|Revision.kt||Plan.kt,PlanSchema.kt,PlanStyleDelta.kt,PlanEndReason.kt|org/tiqian/protocol"
  # Stage1-P3 Kotlin 生产端挂载（t-muiwi5ft-mc60）：jvmMain 承载经 boring runtime shim 的
  # 生成物——BytesBuffer/FPHelper 在当前 pin（ede5476f）是 JVM 专用发射（java.util.ArrayList /
  # java.lang.Float），SortedTable 同理（String.codePointAt），所以 packed 管线整段落 jvmMain，
  # 等发射端多平台化后再下沉 commonMain。PlanPackedWriter.kt（手写委托入口）与
  # LayoutQueriesShim.kt（手写过渡 shim，转发 positionedClustersForLine，core 割接挂载时退役）
  # 是挂载目录里的手写文件，files 模式不查、此处登记出处。
  "kotlin-p3-engine-std|files|kotlin-f32|engine/src/commonMain/kotlin/std|||UStringException.kt|std"
  "kotlin-p3-jvm-protocol|files|kotlin-f32|engine/src/jvmMain/kotlin/org/tiqian/protocol|||PlanJson.kt,PlanJsonNumber.kt,PlanPacked.kt|org/tiqian/protocol"
  "kotlin-p3-jvm-runtime|files|kotlin-f32|engine/src/jvmMain/kotlin/org/tiqian/boring/runtime|||BytesBuffer.kt,FPHelper.kt,SortedTable.kt|runtime"
  "kotlin-p3-jvm-layout|files|kotlin-f32|engine/src/jvmMain/kotlin/org/tiqian/layout|||PlanLowering.kt,PreparedParagraph.kt|org/tiqian/layout"
  # ffi-js precompute cutover（t-muj3czx5-k19v）：platforms/web/client/engine-runtime/engine-gen 是 ts 束的 subset 挂载，
  # 但 precompute-facade.mjs 另需 protocol-ts 束的 12 个协议模块（ParagraphRequestChecks 等）。
  # 两束无法并入一行，以 files 模式对 protocol-ts 束单列内容比对。
  "ffi-js-engine-gen-protocol|files|protocol-ts|platforms/web/client/engine-runtime/engine-gen|||org/tiqian/protocol/DecorationInput.ts,org/tiqian/protocol/InlineBoxInput.ts,org/tiqian/protocol/InlineObjectInput.ts,org/tiqian/protocol/JsCoerce.ts,org/tiqian/protocol/LayoutAttribute.ts,org/tiqian/protocol/LayoutFloatShape.ts,org/tiqian/protocol/LayoutTree.ts,org/tiqian/protocol/LayoutVertex.ts,org/tiqian/protocol/LineBreakSpanInput.ts,org/tiqian/protocol/NamedError.ts,org/tiqian/protocol/ParagraphRequest.ts,org/tiqian/protocol/ParagraphRequestChecks.ts,org/tiqian/protocol/ParagraphRequestException.ts,org/tiqian/protocol/TextSpanInput.ts,org/tiqian/protocol/WireField.ts,org/tiqian/protocol/WireValue.ts|"
  "kotlin-core-engine|files|protocol-kotlin|engine/src/commonMain/kotlin/org/tiqian/core|||TiqianIllegalArgumentException.kt,UnicodeWordCharacter.kt|org/tiqian/core"
  # cinterop 行备注：tiqian_protocol_constants.h 由 protocol-c 的 afterGen 步骤写出；该步骤是
  # 另一会话尚未落地的驱动特性，当前 pin（e80d3802）的生成里没有它 → 属「声明但驱动不产」，非漂移。
  "protocol-c-cinterop|files|protocol-c|engine/src/nativeInterop/cinterop|||tiqian_protocol_constants.h|"
)

TMP=$(mktemp -d); trap "rm -rf \$TMP" EXIT
fail=0; warns=0

for row in "${TABLE[@]}"; do
  IFS="|" read -r label mode bundle mount allow remaps expected prefix <<< "$row"
  echo "=== $label  ($bundle / $mount, mode=$mode)"
  echo

  # 驱动产物集合：gen/ 与 gen-tests/ 去掉各自前缀后合并（两个目录是同一棵目标的两种产物）
  : > "$TMP/driver"
  for sub in gen gen-tests; do
    d="$ROOT/engine-haxe/out/$bundle/$sub"
    [ -d "$d" ] && ( cd "$d" && find . -type f | sed "s|^\./||" ) >> "$TMP/driver"
  done
  LC_ALL=C sort -u "$TMP/driver" -o "$TMP/driver"

  if [ ! -d "$ROOT/$mount" ]; then
    echo "  !! 挂载目录不存在：$ROOT/$mount"; fail=1; continue
  fi

  # 挂载实际文件集合（先滤掉登记表允许的非驱动产物模式），记 驱动名→挂载内路径
  declare -A MOUNTPATH=()
  : > "$TMP/mount"
  while IFS= read -r f; do
    rel="${f#"$ROOT"/$mount/}"
    if [ "$mode" != files ] && [ -n "$allow" ]; then
      skip=0
      IFS=, read -ra pats <<< "$allow"
      for p in "${pats[@]}"; do case "$rel" in $p) skip=1;; esac; done
      [ "$skip" = 1 ] && continue
    fi
    drivername="$rel"
    [ -n "$prefix" ] && drivername="$prefix/$drivername"
    if [ -n "$remaps" ]; then
      for pair in ${remaps//,/ }; do
        case "$rel" in
          "${pair%%=*}") drivername="${pair#*=}"; break;;
        esac
      done
    fi
    MOUNTPATH["$drivername"]="$rel"
    echo "$drivername" >> "$TMP/mount"
  done < <(find "$ROOT/$mount" -type f)
  LC_ALL=C sort -u "$TMP/mount" -o "$TMP/mount"

  # 显式清单（subset / files 模式）：挂载坐标 → 驱动坐标（前缀 + 重映射）
  have_expected=0
  if [ -n "$expected" ]; then
    have_expected=1
    : > "$TMP/expected"
    IFS=, read -ra efiles <<< "$expected"
    for e in "${efiles[@]}"; do
      drivername="$e"
      [ -n "$prefix" ] && drivername="$prefix/$drivername"
      if [ -n "$remaps" ]; then
        for pair in ${remaps//,/ }; do
          case "$e" in
            "${pair%%=*}") drivername="${pair#*=}"; break;;
          esac
        done
      fi
      echo "$drivername" >> "$TMP/expected"
    done
    LC_ALL=C sort -u "$TMP/expected" -o "$TMP/expected"
    bad=$(LC_ALL=C comm -23 "$TMP/expected" "$TMP/driver")
    if [ -n "$bad" ]; then
      echo "  !! 警告（非漂移类，不影响退出码）：清单里声明但当前驱动不产出——「声明但驱动不产」（成因见该行登记表注释；若 pin 回退弄丢了文件则是真漂移，按行定夺）："
      echo "$bad" | sed "s/^/     /"; warns=$((warns+1))
    fi
  fi

  LC_ALL=C comm -13 "$TMP/driver" "$TMP/mount" > "$TMP/extras"
  LC_ALL=C comm -23 "$TMP/driver" "$TMP/mount" > "$TMP/missing"
  ne=$(wc -l < "$TMP/extras"); nm=$(wc -l < "$TMP/missing")

  if [ "$mode" = files ]; then
    nm_listed=0
    if [ "$have_expected" = 1 ]; then
      LC_ALL=C comm -23 "$TMP/expected" "$TMP/mount" > "$TMP/missing_expected"
      nm_listed=$(wc -l < "$TMP/missing_expected")
    fi
    printf "  驱动 %s 个 / 挂载目录 %s 个 / 声明清单 %s 个  missing(清单)=%s（目录其余内容不查）\n" \
      "$(wc -l < "$TMP/driver")" "$(wc -l < "$TMP/mount")" \
      "$([ "$have_expected" = 1 ] && wc -l < "$TMP/expected" || echo 0)" "$nm_listed"
    if [ "$nm_listed" -gt 0 ]; then
      echo "  !! missing（清单声明应搬、挂载里没有——本该搬却忘了搬）："; sed "s/^/     /" "$TMP/missing_expected"; fail=1
    fi
  else
    nm_listed=0; nm_remainder=0
    if [ "$mode" = subset ] && [ "$have_expected" = 1 ]; then
      LC_ALL=C comm -23 "$TMP/expected" "$TMP/mount" > "$TMP/missing_expected"
      nm_listed=$(wc -l < "$TMP/missing_expected")
      nm_remainder=$(LC_ALL=C comm -23 "$TMP/missing" "$TMP/expected" | wc -l)
      printf "  驱动 %s 个 / 挂载 %s 个 / 声明清单 %s 个  extras=%s  missing(清单)=%s  subset 余量=%s\n" \
        "$(wc -l < "$TMP/driver")" "$(wc -l < "$TMP/mount")" "$(wc -l < "$TMP/expected")" "$ne" "$nm_listed" "$nm_remainder"
    else
      if [ "$mode" = subset ] && [ "$have_expected" = 0 ]; then
        echo "  -- 未声明显式清单：missing 只报数（旧行为；补上第 7 列才会判「本该搬却忘了搬」）"
      fi
      printf "  驱动 %s 个 / 挂载 %s 个  extras=%s  missing=%s\n" \
        "$(wc -l < "$TMP/driver")" "$(wc -l < "$TMP/mount")" "$ne" "$nm"
    fi

    if [ "$ne" -gt 0 ]; then
      echo "  !! extras（挂载有而驱动不产出——手工搬运或遗留生成物，逐条定成因）："
      sed "s/^/     /" "$TMP/extras"; fail=1
    fi
    if [ "$nm" -gt 0 ]; then
      if [ "$mode" = full ]; then
        echo "  !! missing（驱动产出而挂载缺失）："; sed "s/^/     /" "$TMP/missing"; fail=1
      elif [ "$have_expected" = 1 ]; then
        if [ "$nm_listed" -gt 0 ]; then
          echo "  !! missing（清单声明应搬、挂载里没有——本该搬却忘了搬）："; sed "s/^/     /" "$TMP/missing_expected"; fail=1
        fi
        [ "$nm_remainder" -gt 0 ] && echo "  -- missing 余量 $nm_remainder 个属声明子集，仅报数（进清单才会判错）"
      else
        echo "  -- missing $nm 个属声明子集，仅报数（改登记表模式才会判错）"
      fi
    fi
  fi

  # 内容比对（.ts 两种形态任一一致即算一致；其余文件逐字节；extras/missing 非零时仍要做）
  diffs=0; n_common=0; n_byte=0; n_rewritten=0; n_type_import=0; n_ts=0
  form_verbatim=""; form_rewritten=""
  while IFS= read -r rel; do
    if [ "$mode" = files ] && [ "$have_expected" = 1 ]; then
      grep -Fxq "$rel" "$TMP/expected" || continue
    fi
    mpath="${MOUNTPATH[$rel]:-$rel}"
    dfull=""
    for sub in gen gen-tests; do
      if [ -f "$ROOT/engine-haxe/out/$bundle/$sub/$rel" ]; then dfull="$ROOT/engine-haxe/out/$bundle/$sub/$rel"; break; fi
    done
    [ -n "$dfull" ] || continue
    n_common=$((n_common+1))
    mfull="$ROOT/$mount/$mpath"
    if cmp -s "$dfull" "$mfull"; then
      n_byte=$((n_byte+1))
      if [[ "$rel" == *.ts ]]; then
        n_ts=$((n_ts+1))
        if grep -Eq "$TS_IMPORT_RE" "$dfull"; then form_verbatim="$form_verbatim $rel"; fi
      fi
    elif [[ "$rel" == *.ts ]]; then
      n_ts=$((n_ts+1))
      sed -E "$TS_REWRITE" "$dfull" > "$TMP/rewritten"
      if cmp -s "$TMP/rewritten" "$mfull"; then
        n_rewritten=$((n_rewritten+1))
        if grep -Eq "$TS_IMPORT_RE" "$dfull"; then form_rewritten="$form_rewritten $rel"; fi
      elif sed -E 's|^import type \{|import {|' "$mfull" | cmp -s "$TMP/rewritten" -; then
        # 第三形态：在 .ts→.js 改写基础上，把仅含类型的 import 写成 import type
        # （verbatimModuleSyntax 的包必须这样写，见文件头约定说明）。
        n_type_import=$((n_type_import+1))
        if grep -Eq "$TS_IMPORT_RE" "$dfull"; then form_rewritten="$form_rewritten $rel"; fi
      else
        echo "  !! 内容不一致（逐字节、.ts→.js 改写、再加 import type 归一三种形态都不符）：$rel"
        diffs=$((diffs+1))
      fi
    else
      echo "  !! 内容不一致：$rel"
      diffs=$((diffs+1))
    fi
  done < <(LC_ALL=C comm -12 "$TMP/driver" "$TMP/mount")
  [ "$diffs" -gt 0 ] && fail=1

  if [ "$n_common" -gt 0 ]; then
    if [ "$diffs" -eq 0 ]; then
      echo "  -- 内容：$n_common/$n_common 全一致（逐字节 $n_byte、.ts→.js 改写后 $n_rewritten、import type 归一 $n_type_import）"
    else
      echo "  -- 内容：$n_common/$n_common 中 $diffs 个不一致（逐字节 $n_byte、改写后 $n_rewritten、import type 归一 $n_type_import）"
    fi
  fi
  # 形态判定：只统计可观察的 .ts 文件（含相对 .ts 说明符的）；其余形态中性
  fv=$(echo $form_verbatim | wc -w); fr=$(echo $form_rewritten | wc -w)
  if [ "$fv" -gt 0 ] || [ "$fr" -gt 0 ]; then
    if [ "$fv" -gt 0 ] && [ "$fr" -gt 0 ]; then
      echo "  !! 警告：同一挂载内形态不统一——verbatim .ts 说明符（$fv 个）与 rewritten .js 说明符（$fr 个）并存："
      echo "     [verbatim .ts]${form_verbatim}"
      echo "     [rewritten .js]${form_rewritten}"
      echo "  -- .ts→.js 改写约定本身不算漂移（两种形态都判一致）；但 tsconfig 是 module/moduleResolution=NodeNext 且未开 allowImportingTsExtensions 时，verbatim 形态过不了类型检查：要么统一改写成 .js，要么同时开 moduleResolution: bundler + allowImportingTsExtensions"
      warns=$((warns+1))
    elif [ "$fv" -gt 0 ]; then
      echo "  -- 形态：统一 verbatim .ts（可观察 $fv 个，形态中性 $((n_ts - fv - fr)) 个）"
    else
      echo "  -- 形态：统一 rewritten .js（可观察 $fr 个，形态中性 $((n_ts - fv - fr)) 个）"
    fi
  fi
  echo
done

if [ "$fail" -eq 0 ]; then
  echo "OK：所有挂载与驱动产物一致$([ "$warns" -gt 0 ] && echo "（另有 $warns 条警告，不影响闸门）")"
else
  echo "FAIL：存在漂移，pin advance 前必须清零"
fi
exit "$fail"
