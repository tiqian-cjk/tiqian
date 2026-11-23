package org.tiqian.compose

import android.graphics.Typeface
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.core.LayoutResult
import org.tiqian.font.FontRole
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.android.AndroidTypefaceResolver
import org.tiqian.shaping.android.AndroidTypefaceResolverRegistry
import org.tiqian.shaping.android.SystemAndroidTypefaceResolver
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotSame
import kotlin.test.assertSame
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 26)
class AndroidTypefaceResolverRecompositionTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun replacingResolverRemeasuresAndRepaintsMountedText() {
        val previousResolver = AndroidTypefaceResolverRegistry.current
        val first = CountingResolver(Typeface.SANS_SERIF)
        val second = CountingResolver(Typeface.MONOSPACE)
        val revision = mutableIntStateOf(0)
        val showReference = mutableStateOf(false)
        var composedRevision = -1
        var mountedLayout: LayoutResult? = null
        var mountedCoordinates: LayoutCoordinates? = null
        val text = buildAnnotatedString {
            append("iiii ")
            ruby("汉", "mimi", fontFamily = RUBY_FONT)
        }
        try {
            AndroidTypefaceResolverRegistry.install(first)
            val session = ParagraphMeasurementSession()
            compose.setContent {
                // Registry installation is not snapshot state; the host requests recomposition.
                val currentRevision = revision.intValue
                val measurer = rememberParagraphMeasurer(session = session)
                SideEffect { composedRevision = currentRevision }
                Column {
                    Box(Modifier.size(280.dp, 120.dp).background(Color.White).testTag("mounted")) {
                        CjkText(
                            text = text,
                            fontSize = 32.sp,
                            color = Color.Black,
                            measurer = measurer,
                            modifier = Modifier
                                .onGloballyPositioned { mountedCoordinates = it }
                                .drawWithContent {
                                    first.drawing = true
                                    second.drawing = true
                                    try {
                                        drawContent()
                                    } finally {
                                        first.drawing = false
                                        second.drawing = false
                                    }
                                },
                            onTextLayout = { mountedLayout = it },
                        )
                    }
                    if (showReference.value) {
                        Box(Modifier.size(280.dp, 120.dp).background(Color.White).testTag("reference")) {
                            CjkText(
                                text = text,
                                fontSize = 32.sp,
                                color = Color.Black,
                                measurer = rememberParagraphMeasurer(session = session),
                            )
                        }
                    }
                }
            }
            val beforePixels = compose.onNodeWithTag("mounted").captureToImage().pixels()
            val beforeLayout = compose.runOnIdle { checkNotNull(mountedLayout) }
            val coordinates = compose.runOnIdle { checkNotNull(mountedCoordinates) }
            compose.runOnIdle {
                assertTrue(first.measurements > 0)
                assertTrue(first.rubyDraws > 0, "the first frame must exercise ruby drawing")
                assertTrue(beforeLayout.debug.rubyDecisions.isNotEmpty())
                first.draws = 0
                AndroidTypefaceResolverRegistry.install(second)
                revision.intValue += 1
            }
            val afterPixels = compose.onNodeWithTag("mounted").captureToImage().pixels()
            compose.runOnIdle {
                val afterLayout = checkNotNull(mountedLayout)
                assertEquals(1, composedRevision)
                assertTrue(coordinates.isAttached, "the original paragraph must remain mounted")
                assertSame(coordinates, mountedCoordinates)
                assertEquals(beforeLayout.input, afterLayout.input, "only the font source changed")
                assertNotSame(beforeLayout, afterLayout, "the old session must not return the old layout")
                assertTrue(second.measurements > 0, "the replacement resolver must serve measurement")
                assertNotEquals(beforeLayout.clusters.first().advance, afterLayout.clusters.first().advance)
                assertEquals(0, first.draws, "the mounted renderer must release the obsolete resolver")
                assertTrue(second.rubyDraws > 0, "ruby drawing must use the replacement resolver on every API")
            }
            assertTrue(!beforePixels.contentEquals(afterPixels), "the replacement font must change the pixels")

            compose.runOnIdle { showReference.value = true }
            val referencePixels = compose.onNodeWithTag("reference").captureToImage().pixels()
            assertContentEquals(referencePixels, afterPixels, "the updated node must match a fresh node using resolver B")
        } finally {
            AndroidTypefaceResolverRegistry.install(previousResolver)
        }
    }

    private class CountingResolver(private val latin: Typeface) : AndroidTypefaceResolver {
        private val system = SystemAndroidTypefaceResolver()
        var drawing = false
        var measurements = 0
        var draws = 0
        var rubyDraws = 0

        override fun resolve(input: ShapingInput): Typeface {
            if (!drawing) measurements += 1
            return resolve(input.fontDecision.role, input.style.fontFamilies, input.style.fontWeight, input.style.italic)
        }

        override fun resolve(role: FontRole, fontFamilies: List<String>, fontWeight: Int, italic: Boolean): Typeface {
            if (drawing) {
                draws += 1
                if (RUBY_FONT in fontFamilies) rubyDraws += 1
            }
            return if (role == FontRole.LatinText) latin else system.resolve(role, fontFamilies, fontWeight, italic)
        }
    }

    private fun ImageBitmap.pixels(): IntArray = IntArray(width * height).also { readPixels(it) }

    private companion object {
        const val RUBY_FONT = "resolver-recomposition-ruby"
    }
}
