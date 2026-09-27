package org.tiqian.core;

// CLREQ 着重号 — a solid dot under each emphasised Han character.
// 示亡号 — a solid black frame around a (deceased person's) name.
// 专名号 — a straight underline below a proper noun (horizontal
// writing). One of the CLREQ 行间线: one continuous segment per
// ADJACENT sides only (≤1/8 em) so the two marks read separately.
// 书名号（甲式）— a wavy underline below a work's title (horizontal
// writing). Same 行间线 segment rules as [ProperNoun].
enum DecorationKind {
    Emphasis;
    Mourning;
    ProperNoun;
    BookTitle;
}
