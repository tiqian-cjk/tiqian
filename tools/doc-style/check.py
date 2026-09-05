#!/usr/bin/env python3
"""Chinese documentation style self-check for tiqian docs.

Scans Chinese text files (ADR, design docs, README) for vocabulary and
rhetorical patterns that the project style rules ban: metaphor verbs used
as technical terms, internet jargon, coined compression words, contrast
constructions, and decorative adjectives.

Usage:
    python3 tools/doc-style/check.py             # scan README.md and docs/
    python3 tools/doc-style/check.py FILE ...    # scan specific files or dirs

Exit status: 0 when no hits remain, 1 when hits remain after the allowlist.
Each hit is a candidate for manual judgment, not an automatic violation.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Metaphor verbs, internet jargon, coined compression words, and colloquial
# shorthand named in style corrections. In writing, replace each with a plain
# verb or noun; swapping one metaphor for a near-synonym metaphor is not a
# fix (收窄 was such a failed replacement for 瘦身 and is banned as well).
WORDS = [
    # aviation shorthand for running/dispatched work (2026-09-05 correction)
    "在飞",
    # gate and doorway metaphors
    "门面", "扇门", "门控", "门禁", "缓存门", "字体门",
    # gate / threshold 直译（CI gate、graduation gate）
    "门槛", "毕业门", "硬门", "CI 门",
    # bookkeeping and finance metaphors
    "闭环", "台账", "账", "账目", "兑现", "零钱", "流失",
    # coined self-reference for the coordinating session (2026-08-29 correction)
    "中央裁定", "中央收尾", "中央复核", "中央实测", "中央独立",
    # campaign shorthand for unreachable-line proofs (2026-08-29 correction)
    "判死", "死臂", "清零", "残差",
    # targeting and pinning
    "钉在", "钉住", "钉死", "锁死", "写死", "绑死",
    # motion and body metaphors
    "瘦身", "收口", "兜底", "退路", "穿透", "镜像", "升格", "降格", "摘出",
    "收窄", "寄生", "换装", "落地", "退役", "落档", "留档", "落点", "对拍",
    "钳位", "落盘", "射程",
    "虚胖", "穿帮", "失血", "幻影", "塌成", "塌缩", "腰斩", "砍半", "冲垮",
    "兜住", "掐死", "解冻", "前哨", "病根", "断崖", "元凶", "北极星", "皇冠",
    "犯忌", "无依无靠", "守门", "打回", "污染", "传染",
    "收归", "收档",
    "落为", "落格", "归位",
    "塞回", "硬塞", "误塞", "多塞", "能塞就塞", "插进",
    "吃掉", "吃光", "吃满", "吃饱",
    # internet jargon verbs
    "链路", "打通", "拉齐", "沉淀", "反哺", "赋能", "抓手", "打磨", "深耕",
    "复盘", "一把梭", "弃坑", "跑通", "回流", "通路", "真·", "波次",
    # alignment-dimension metaphor (2026-09-05 correction): 轴 as in 对齐轴
    "轴",
    # gate metaphor for the verification suite (2026-09-05 correction)
    "四门",
    # coined compressions (2026-09-05 corrections)
    "降级链", "终态", "横比",
    # misattributed or vague causal wording
    "根因", "归因", "掩盖", "口径", "挡住", "契约", "缺口", "夹具", "刀次",
    "包袱", "载体", "收束", "下沉", "节拍",
    # measurement metaphors and coined measurement words
    "车道", "lane", "wall", "墙钟", "仪表", "亚毫", "膨胀", "显形", "重录",
    "冷构建", "热构建", "冷热", "全冷", "多重集", "构建链", "排空", "惰性",
    "互不推导", "三面", "三段式",
    "全 0",
    "零漂移", "零差异", "零改动", "零引擎", "归零",
    "导出面", "消费面", "使用面", "调用面", "语义面", "运行时面", "改动面",
    "构造面", "不稳定面", "引擎面",
    "证据带", "整数带", "带表", "带条目",
    "发布线", "版本线", "延续线", "排版线", 
    "首绘", "真身", "含射", "发射", "烘焙", "单一事实源", "语义负担", "全链",
    "表路", "读侧", "走表", "填表人", "子片", "进表", "补造", "切片", "打桩",
    "进解", "对赛", "互串", "错层", "加建", "过桥", "反连接", "换带", "收紧",
    # coined technical-sounding words replaced by plain statements
    "失配", "真源", "转出口", "合批", "同批", "执行位", "线格式", "零违例", "违例",
    "伪差异", "偶合", "已真", "换嗓", 
    "半提交", "双份实现", "双职", "起测", "必产出", "帧迹", "随迁",
    "信号形状", "自管", "空挂", "替身", "本体", "整根", "挂旗", "处置链",
    "wire 编解码",
    "时钟泵", "旅程", "采纳链", "习语", "净胜",
    # colloquial shorthand
    "毛躁", "全绿", "全红", "锁相", "塞进", "收进", "测试绿", "测试红",
    "糊", "照跑", "拍平", "散落", "堆放", "接线", "免费拿到",
    # decorative adjectives and vague quantifiers: judge each line by context
    "恒", "恰好", "巨大的", "完整的", "真实", "合法", "归一", "缝隙", "大概率",
    "当日",
    "真正", "恰", "诱人", "灾难", "今天", "当天",
    # machine-translated or literal-translation feel
    "烘出", "烘入", "烘死", "农场", "裸", "回落",
    "电池",
    "缝", "姿态",
    # meta phrasing about the document itself: state facts instead
    "本记录", "终版", "不进仓库", "够支撑", "记录在案",
]

# Rhetorical sentence patterns: negate-first contrast, intensifiers, em-dash.
PATTERNS = [
    (r"不是[^。；！？\n]{0,60}而是", "contrast"),
    (r"，而是", "contrast"),
    (r"而不是", "contrast"),
    (r"，不是", "contrast"),
    (r"，而非", "contrast"),
    (r"更是", "contrast"),
    (r"——", "em-dash"),
    # AI-generated filler transitions: restating without adding information
    (r"换句话说", "ai-filler"),
    (r"也就是说", "ai-filler"),
    (r"这意味着", "ai-filler"),
    (r"实际上[，:：]", "ai-filler"),
    (r"但实际", "ai-filler"),
    (r"看起来(?!像|$)", "ai-filler"),
    (r"但其实|[，。：；——」』]其实", "ai-filler"),
    # put-downs that add no information
    (r"只是把", "putdown"),
    (r"算不上", "putdown"),
    (r"根本不是", "putdown"),
    (r"纯粹是", "putdown"),
    # The X-level suffix classes, banned whole instead of enumerated:
    # English coinages (file-level, module-level) and Chinese glue words
    # (会话级, 帧级). "top-level" is platform vocabulary and stays the
    # single English exemption.
    (r"(?i)\b(?!top-levels?\b)[a-z]+-levels?\b", "coinage"),
]

# Dictionary compounds where 级 is part of a standard word, not a glued
# granularity coinage. The suffix check skips these; everything else of
# the shape 名词+级 reports for manual judgment.
LEVEL_STANDARD = (
    "优先级", "等级", "级别", "升级", "降级", "上级", "下级",
    "一级", "二级", "三级", "四级", "五级", "星级", "阶级",
    "量级", "分级", "层级", "同级", "两级", "平级", "评级",
)


def matchedLevelSuffix(line: str) -> list[str]:
    hits = []
    for m in re.finditer(r"[一-龥A-Za-z0-9]{1,12} ?级", line):
        token = m.group(0)
        if any(token.endswith(word) for word in LEVEL_STANDARD):
            continue
        hits.append(token)
    return hits

# Known accepted uses. A line matching this regex is skipped entirely, so
# keep entries narrow: a line holding both an accepted use and a real
# violation would be missed, and the skip is per line, not per match.
# YOU ARE NOT ALLOWED TO EXPAND THIS LIST WITHOUT CLEAR PERMISSION.
ALLOW = re.compile(
    r"回退路径"  # contains the substring 退路 but is a standard term
)


def iter_targets(args: list[str]):
    if args:
        for arg in args:
            path = Path(arg)
            if path.is_dir():
                yield from sorted(path.rglob("*.md"))
            else:
                yield path
        return
    yield REPO_ROOT / "README.md"
    yield from sorted((REPO_ROOT / "docs").rglob("*.md"))


def matched_words(line: str) -> list[str]:
    matched = [word for word in WORDS if word in line]
    # Drop words fully contained in a longer matched word on the same line
    # (账 inside 台账) so each line reports the narrowest cause once.
    return [
        word
        for word in matched
        if not any(word != other and word in other for other in matched)
    ]


def main() -> int:
    hits: list[tuple[str, int, str, str, str]] = []
    for path in iter_targets(sys.argv[1:]):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            print(f"skip {path}: {exc}", file=sys.stderr)
            continue
        try:
            shown = path.relative_to(REPO_ROOT)
        except ValueError:
            shown = path
        for number, line in enumerate(text.splitlines(), 1):
            if ALLOW.search(line):
                continue
            for word in matched_words(line):
                hits.append((str(shown), number, "word", word, line.strip()))
            for token in matchedLevelSuffix(line):
                hits.append((str(shown), number, "coinage", token, line.strip()))
            for regex, tag in PATTERNS:
                if re.search(regex, line):
                    hits.append((str(shown), number, tag, regex, line.strip()))
    for shown, number, tag, token, line in hits:
        print(f"{shown}:{number}: [{tag}] {token}: {line}")
    print()
    print(f"命中 {len(hits)} 处。")
    print("说明：本工具只是自动化的检查列表，词表与句式模式不完整，需要随时填充。")
    print("命中仅为候选，逐条人工判定后改写。")
    print("自动检查不替代手动校验。")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
