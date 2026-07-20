package org.tiqian.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import org.tiqian.clreq.ClreqProfile
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.android.AndroidFontMetricsResolver
import org.tiqian.shaping.android.AndroidPaintTextShaper
import org.tiqian.shaping.android.SystemAndroidTypefaceResolver

@Composable
internal actual fun rememberPlatformParagraphMeasurer(profile: ClreqProfile): ParagraphMeasurer =
    remember(profile) {
        val typefaces = SystemAndroidTypefaceResolver()
        ParagraphMeasurer(
            ExplainableStubParagraphLayoutEngine(
                lineBreaker = LookaheadLineBreaker(),
                textShaper = AndroidPaintTextShaper(typefaceResolver = typefaces),
                fontMetricsResolver = AndroidFontMetricsResolver(typefaceResolver = typefaces),
                clreqProfileResolver = { profile },
            ),
        )
    }
