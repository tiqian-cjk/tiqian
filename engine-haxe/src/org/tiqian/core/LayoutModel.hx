package org.tiqian.core;

// Paragraph indent resolution records [source] as "MeasureAdaptiveFirstLineIndent" and uses [measureEm] in 字, or records "Explicit" for firstLineIndent.
// The adaptive branch compares [measureEm] with [thresholdEm] and returns [resolvedEm].
// The explicit branch uses the author-provided 段首缩进 value.
// The 注文 font-family list is ordered by preference; an empty list uses the renderer's default 字体.
// The weight of 注文 is 100 above the 基文 weight when its size is smaller.
// The shaping record stores the BCP-47 language used by the 注文.
// The weight of 注音 is 300 above the 基文 weight when its size is smaller.
// The shaping record stores the BCP-47 language used by the 注音.
