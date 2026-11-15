package org.tiqian.shaping.android.nativefont

import android.annotation.TargetApi
import android.content.Context
import android.graphics.Paint
import android.graphics.fonts.Font
import android.os.Build
import android.text.TextPaint
import org.tiqian.boring.runtime.SortedMapTable
import org.tiqian.boring.runtime.SortedSetTable
import org.tiqian.boring.runtime.SortedTable
import org.tiqian.font.FontRole
import org.tiqian.shaping.FontBackendCapabilityIssue
import org.tiqian.shaping.FontBackendCapabilityReport
import org.tiqian.shaping.ReplayableFontCatalog
import org.tiqian.shaping.ReplayableFontFaceDescriptor
import org.tiqian.shaping.ReplayableFontFaceRequest
import org.tiqian.shaping.android.AndroidGlyphReplayRegistry
import org.tiqian.shaping.android.AndroidTypefaceResolverRegistry
import org.tiqian.shaping.android.platformRunAdvance
import java.io.File
import java.util.Locale
import kotlin.math.roundToInt

internal data class LoadedFace(
    val catalogIndex: Int,
    val familyKey: String,
    val descriptor: ReplayableFontFaceDescriptor,
    val nativeFace: NativeFontFace,
    val opticalSize: OpticalSizeInstancer? = null,
)

/** OpticalSizeFollowsFontSize state for one loaded face: the declared `opsz` range and its per-size instances. */
internal class OpticalSizeInstancer(
    val rule: AndroidOpticalSizeRule,
    val range: ClosedFloatingPointRange<Float>,
    val sourceHandle: Long,
    val sourceDigestHex: String,
) {
    /** Guarded by the backend lock; keyed by the clamped `opsz` value. */
    val instances = HashMap<Float, Pair<ReplayableFontFaceDescriptor, NativeFontFace>>()
}

/** One retained face as the renderer needs it: outline source, style provenance and platform Font. */
internal class ReplayFace(
    val face: NativeFontFace,
    val italic: Boolean,
    val syntheticItalic: Boolean,
    val syntheticBold: Boolean,
    /** An `android.graphics.fonts.Font` on API 31+, kept as Any so the class loads below API 29. */
    val platformFont: Any?,
)

private data class LoadedFamily(
    val faces: List<LoadedFace>,
    /** PlatformDefaultFamily on API 31+: resolved by asking the platform per request. */
    val platformOracle: Boolean = false,
) {
    val aliases: Set<String>
        get() = if (platformOracle) {
            setOf(AndroidFontCatalog.PLATFORM_DEFAULT_FAMILY)
        } else {
            faces.flatMapTo(linkedSetOf()) { it.descriptor.familyAliases.asIterable() }
        }
}

/** Platform selection for one request; null when [acceptUncovered] is false and the platform face lacks the text. */
private typealias PlatformOracle = (request: ReplayableFontFaceRequest, acceptUncovered: Boolean) -> ResolvedNativeFontFace?

private data class PlatformLoadedFace(
    val descriptor: ReplayableFontFaceDescriptor,
    val nativeFace: NativeFontFace,
)

private data class LoadedNativeFontSource(
    val handle: Long,
    val digestHex: String,
    val sizeBytes: Long,
)

private class RevisionListener(
    private val callback: (Long) -> Unit,
) {
    private var lastDelivered = 0L

    fun deliver(revision: Long) {
        val shouldDeliver = synchronized(this) {
            if (revision <= lastDelivered) false else {
                lastDelivered = revision
                true
            }
        }
        if (shouldDeliver) callback(revision)
    }
}

private class LoadedAndroidFontCatalog(
    private val loadedFaces: List<LoadedFace>,
    private val familiesByRole: Map<FontRole, List<LoadedFamily>>,
    val revision: Long,
    val usesPlatformDefaultOracle: Boolean,
    override val capabilityReport: FontBackendCapabilityReport,
) : ReplayableFontCatalog {
    override val faces: MutableList<ReplayableFontFaceDescriptor> =
        loadedFaces.map { it.descriptor }.toMutableList()

    override fun get_faces(): MutableList<ReplayableFontFaceDescriptor> = faces

    override fun get_capabilityReport(): FontBackendCapabilityReport = capabilityReport

    override fun resolve(request: ReplayableFontFaceRequest): ReplayableFontFaceDescriptor? =
        resolveNative(request, oracle = null)?.descriptor

    fun resolveNative(
        request: ReplayableFontFaceRequest,
        oracle: PlatformOracle?,
    ): ResolvedNativeFontFace? {
        val roleFamilies = familiesByRole[request.role].orEmpty()
        if (roleFamilies.isEmpty()) return null
        val pool = orderedFamilyPool(roleFamilies, request.preferredFamilies, LoadedFamily::aliases)
        fun matched(family: LoadedFamily): LoadedFace? = matchStyle(
            faces = family.faces,
            requestedWeight = request.weight,
            requestedItalic = request.italic,
            weight = { it.descriptor.weight },
            italic = { it.descriptor.italic },
            stableId = { "${it.catalogIndex}:${it.descriptor.id}" },
        )
        // StyleMatchedFaceCoverage: only the style-matched face of each family is checked for the
        // text; a platform-default position asks the platform instead.
        for (familyIndex in pool.indices) {
            val family = roleFamilies[familyIndex]
            if (family.platformOracle) {
                oracle?.invoke(request, false)?.let { return it }
                continue
            }
            val face = matched(family) ?: continue
            if (!face.nativeFace.hasGlyphs(request.selectionText)) continue
            return resolved(request, face, exactFamily = pool.isExact(familyIndex), covering = true)
        }
        // NoCoveringFacePlatformDegrade: no controlled face has these glyphs, so the platform text
        // stack measures and draws the segment; the chain's last declared family only supplies metrics.
        val lastDeclared = roleFamilies.lastOrNull { !it.platformOracle }
            ?: return oracle?.invoke(request, true)
        val face = matched(lastDeclared) ?: return null
        return resolved(request, face, exactFamily = pool.isExact(roleFamilies.indexOf(lastDeclared)), covering = false)
    }

    private fun resolved(
        request: ReplayableFontFaceRequest,
        selected: LoadedFace,
        exactFamily: Boolean,
        covering: Boolean,
    ): ResolvedNativeFontFace {
        val instance = selected.opticalSize?.takeIf { covering }?.let { instancer ->
            TiqianAndroidFontBackend.opticalSizeInstance(selected, instancer, request.fontSize)
        }
        var descriptor = instance?.first ?: selected.descriptor
        val native = instance?.second ?: selected.nativeFace
        val syntheticBold = covering && requiresSyntheticBold(request.weight, descriptor.weight)
        if (syntheticBold) descriptor = TiqianAndroidFontBackend.syntheticBoldDescriptor(descriptor, native)
        return ResolvedNativeFontFace(
            descriptor = descriptor,
            nativeFace = native,
            exactFamily = exactFamily,
            exactStyle = selected.descriptor.italic == request.italic && selected.descriptor.weight == request.weight,
            coversSelectionText = covering,
            replayable = covering,
            degradedRunAdvance = if (covering) 0f else platformDegradeAdvance(request),
            stringDrawCause = if (covering) null else PlatformStringDrawCause.NoCoveringFace,
            syntheticBold = syntheticBold,
        )
    }
}

private val platformDegradeLock = Any()

/** The advance the Android renderer's string fallback will consume for [request]'s text. */
private fun platformDegradeAdvance(request: ReplayableFontFaceRequest): Float {
    val text = request.selectionText
    if (text.isEmpty()) return 0f
    val cjkRole = request.role == FontRole.CjkText || request.role == FontRole.CjkPunctuation
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = request.fontSize
        textLocale = Locale.forLanguageTag(request.locale)
        typeface = synchronized(platformDegradeLock) {
            AndroidTypefaceResolverRegistry.current.resolve(
                request.role,
                request.preferredFamilies,
                request.weight,
                italic = request.italic && !cjkRole,
            )
        }
    }
    return platformRunAdvance(paint, text, request.role)
}

/**
 * Process-wide stable resource contract. Registered faces are retained so an
 * already-produced LayoutResult remains replayable after catalog changes.
 */
object TiqianAndroidFontBackend {
    private const val BackendName = "TiqianHarfBuzzFreeType"
    private const val SyntheticBoldStrokeSuffix = ":syntheticBold=stroke"
    private val lock = Any()
    private val sourceByLocator = LinkedHashMap<String, LoadedNativeFontSource>()
    private val sourceByDigest = LinkedHashMap<String, LoadedNativeFontSource>()
    private val faceById = LinkedHashMap<String, NativeFontFace>()
    private val descriptorById = LinkedHashMap<String, ReplayableFontFaceDescriptor>()
    private val platformFaceByRequest = object : LinkedHashMap<ReplayableFontFaceRequest, ResolvedNativeFontFace>(256, 0.75f, true) {}
    private val platformFaceByInstance = LinkedHashMap<String, PlatformLoadedFace>()
    private val platformFontById = LinkedHashMap<String, Any>()
    private val revisionListeners = linkedSetOf<RevisionListener>()
    private val syntheticBoldFaceIds = linkedSetOf<String>()
    private val syntheticItalicFaceIds = linkedSetOf<String>()
    private var lastRevision = 0L

    @Volatile
    private var activeCatalog: LoadedAndroidFontCatalog? = null

    private val versionEvidence: String by lazy(LazyThreadSafetyMode.PUBLICATION) {
        NativeFontBridge.nativeVersions()
    }

    val nativeVersions: String
        get() = versionEvidence

    /** Install one immutable font environment. Old faces remain retained for old LayoutResult replay. */
    fun install(context: Context, catalog: AndroidFontCatalog): FontBackendCapabilityReport {
        val installed: LoadedAndroidFontCatalog
        val listeners: List<RevisionListener>
        synchronized(lock) {
            installed = loadCatalog(
                context = context.applicationContext,
                hostCatalog = catalog,
                revision = nextRevisionLocked(),
                usesPlatformDefaultOracle = false,
            )
            activeCatalog = installed
            listeners = revisionListeners.toList()
        }
        registerGlyphReplay()
        listeners.forEach { listener -> runCatching { listener.deliver(installed.revision) } }
        return installed.capabilityReport
    }

    /** Makes Compose renderers draw this backend's glyph ids through [AndroidNativeGlyphReplay]. */
    private fun registerGlyphReplay() {
        AndroidGlyphReplayRegistry.register(AndroidNativeGlyphReplay)
    }

    /** StrokeSyntheticBold identity over the same native face; retained so old layouts keep replaying. */
    internal fun syntheticBoldDescriptor(
        descriptor: ReplayableFontFaceDescriptor,
        native: NativeFontFace,
    ): ReplayableFontFaceDescriptor = synchronized(lock) {
        val id = descriptor.id + SyntheticBoldStrokeSuffix
        descriptorById.getOrPut(id) {
            faceById[id] = native
            syntheticBoldFaceIds += id
            ReplayableFontFaceDescriptor(
                id = id,
                familyAliases = descriptor.familyAliases,
                roles = descriptor.roles,
                weight = descriptor.weight,
                italic = descriptor.italic,
                collectionIndex = descriptor.collectionIndex,
                sourceLabel = descriptor.sourceLabel + SyntheticBoldStrokeSuffix,
                variationAxes = descriptor.variationAxes,
            )
        }
    }

    /** The `opsz` instance of [face] for [fontSize]: whole units clamped to the axis range, retained per value. */
    internal fun opticalSizeInstance(
        face: LoadedFace,
        instancer: OpticalSizeInstancer,
        fontSize: Float,
    ): Pair<ReplayableFontFaceDescriptor, NativeFontFace> {
        val opsz = (fontSize * instancer.rule.pointsPerPixel).roundToInt().toFloat().coerceIn(instancer.range)
        synchronized(lock) {
            instancer.instances[opsz]?.let { return it }
            val axes = face.descriptor.variationAxes.asMap().toMutableMap().apply { this["opsz"] = opsz }
            val id = stableFaceId(instancer.sourceDigestHex, face.descriptor.collectionIndex, axes)
            val native = createOrGetFaceLocked(id, instancer.sourceHandle, face.descriptor.collectionIndex, axes)
            val descriptor = descriptorById.getOrPut(id) {
                ReplayableFontFaceDescriptor(
                    id = id,
                    familyAliases = face.descriptor.familyAliases,
                    roles = face.descriptor.roles,
                    weight = face.descriptor.weight,
                    italic = face.descriptor.italic,
                    collectionIndex = face.descriptor.collectionIndex,
                    sourceLabel = face.descriptor.sourceLabel,
                    variationAxes = sortedMapTableOf(axes, SortedTable::compareStrings),
                )
            }
            return (descriptor to native).also { instancer.instances[opsz] = it }
        }
    }

    /** One FreeType/HarfBuzz face per stable id; callers hold [lock]. */
    private fun createOrGetFaceLocked(
        id: String,
        sourceHandle: Long,
        collectionIndex: Int,
        axes: Map<String, Float>,
    ): NativeFontFace = faceById.getOrPut(id) {
        val handle = NativeFontBridge.nativeCreateFace(
            sourceHandle = sourceHandle,
            collectionIndex = collectionIndex,
            variationTags = axes.keys.map(::variationTag).toIntArray(),
            variationValues = axes.values.toFloatArray(),
        )
        NativeFontFace(handle, NativeFontBridge.nativeUnitsPerEm(handle))
    }

    /** Everything a renderer needs about a retained face, read under one lock acquisition. */
    internal fun replayFace(renderFontKey: String): ReplayFace? = synchronized(lock) {
        val id = renderFontKey
        val face = faceById[id] ?: return null
        ReplayFace(
            face = face,
            italic = descriptorById[id]?.italic == true,
            syntheticItalic = id in syntheticItalicFaceIds,
            syntheticBold = id in syntheticBoldFaceIds,
            platformFont = platformFontById[id],
        )
    }

    /** Monotonic identity of the active immutable catalog, suitable for layout/cache keys. */
    fun catalogRevision(context: Context): Long = ensureInstalled(context).revision

    /**
     * Observe active-catalog replacement. The current revision is delivered immediately so a
     * registration cannot miss an install racing with subscription.
     */
    fun addCatalogRevisionListener(context: Context, listener: (Long) -> Unit): AutoCloseable {
        ensureInstalled(context)
        val subscription = RevisionListener(listener)
        val current = synchronized(lock) {
            revisionListeners += subscription
            checkNotNull(activeCatalog).revision
        }
        subscription.deliver(current)
        return AutoCloseable { synchronized(lock) { revisionListeners -= subscription } }
    }

    fun capabilityReport(context: Context): FontBackendCapabilityReport =
        ensureInstalled(context).capabilityReport

    internal fun resolveFace(
        context: Context,
        request: ReplayableFontFaceRequest,
    ): ResolvedNativeFontFace {
        val catalog = ensureInstalled(context)
        if (Build.VERSION.SDK_INT >= 31 && catalog.usesPlatformDefaultOracle) {
            resolvePlatformDefaultFace(context.applicationContext, request, acceptUncovered = false)?.let { return it }
        }
        val oracle: PlatformOracle? = if (Build.VERSION.SDK_INT >= 31) {
            { platformRequest, acceptUncovered ->
                resolvePlatformDefaultFace(context.applicationContext, platformRequest, acceptUncovered)
            }
        } else {
            null
        }
        return catalog.resolveNative(request, oracle) ?: error(
            "MissingControlledFontFace: role=${request.role}; families=${request.preferredFamilies}; " +
                "install an AndroidFontCatalog before composing CjkText; report=${catalog.capabilityReport}",
        )
    }

    internal fun faceFor(renderFontKey: String): NativeFontFace? = synchronized(lock) {
        faceById[renderFontKey]
    }

    /** Stable replay evidence for a glyph id emitted by [AndroidNativeTextShaper]. */
    fun replayFaceDescriptor(renderFontKey: String): ReplayableFontFaceDescriptor? = synchronized(lock) {
        descriptorById[renderFontKey]
    }

    internal fun isSyntheticItalicFace(renderFontKey: String): Boolean = synchronized(lock) {
        renderFontKey in syntheticItalicFaceIds
    }

    internal fun isSyntheticBoldFace(renderFontKey: String): Boolean = synchronized(lock) {
        renderFontKey in syntheticBoldFaceIds
    }

    @TargetApi(31)
    internal fun platformFontFor(renderFontKey: String): Font? = synchronized(lock) {
        platformFontById[renderFontKey] as? Font
    }

    internal fun resourceStatsForTesting(): NativeFontResourceStats = nativeFontResourceStats()

    internal fun resetDefaultCatalogForTesting(context: Context) {
        synchronized(lock) {
            platformFaceByRequest.clear()
            platformFaceByInstance.clear()
            val catalog = defaultCatalog(context.applicationContext)
            activeCatalog = loadCatalog(
                context = context.applicationContext,
                hostCatalog = catalog,
                revision = nextRevisionLocked(),
                usesPlatformDefaultOracle = catalog.isPlatformDefaultOracleCatalog(),
            )
        }
        registerGlyphReplay()
    }

    private fun ensureInstalled(context: Context): LoadedAndroidFontCatalog {
        activeCatalog?.let { return it }
        return synchronized(lock) {
            activeCatalog ?: run {
                val catalog = defaultCatalog(context.applicationContext)
                loadCatalog(
                    context.applicationContext,
                    catalog,
                    nextRevisionLocked(),
                    usesPlatformDefaultOracle = catalog.isPlatformDefaultOracleCatalog(),
                ).also {
                    activeCatalog = it
                    registerGlyphReplay()
                }
            }
        }
    }

    private fun nextRevisionLocked(): Long = (++lastRevision).also {
        check(it > 0L) { "Android font catalog revision overflow" }
    }

    /** Discovery only: the catalog [install] would fall back to, without loading or installing it. */
    fun systemCatalog(context: Context): AndroidFontCatalog = defaultCatalog(context.applicationContext)

    /** Complete real style instances for hosts composing a custom system-derived font family. */
    fun systemStyleCatalog(context: Context): AndroidFontCatalog {
        if (Build.VERSION.SDK_INT >= 31) {
            AndroidPlatformFontOracle.styleCatalogOrNull()?.let { return it }
        }
        return declaredSystemCatalog(context.applicationContext)
    }

    /** The declared system catalog without the API 31 oracle; what a platform-default entry expands to. */
    private fun declaredSystemCatalog(context: Context): AndroidFontCatalog {
        DeclaredSystemFontConfigCatalog.createOrNull()?.let { return it }
        if (Build.VERSION.SDK_INT >= 29) {
            ApproximatePublicSystemFontsCatalog.createOrNull()?.let { return it }
        }
        return wellKnownSystemPathCatalog()
    }

    private fun defaultCatalog(context: Context): AndroidFontCatalog {
        if (Build.VERSION.SDK_INT >= 31) {
            AndroidPlatformFontOracle.bootstrapCatalogOrNull()?.let { return it }
        }
        DeclaredSystemFontConfigCatalog.createOrNull()?.let { return it }
        if (Build.VERSION.SDK_INT >= 29) {
            ApproximatePublicSystemFontsCatalog.createOrNull()?.let { return it }
        }
        return wellKnownSystemPathCatalog()
    }

    private fun AndroidFontCatalog.isPlatformDefaultOracleCatalog(): Boolean =
        sourceKind == "AndroidPlatformTextRunOracleApi31"

    private fun loadCatalog(
        context: Context,
        hostCatalog: AndroidFontCatalog,
        revision: Long,
        usesPlatformDefaultOracle: Boolean,
    ): LoadedAndroidFontCatalog {
        // PlatformDefaultFamily: API 31+ keeps the marker and asks the platform per request;
        // older systems expand it into the declared system families now.
        val delegateToOracle = hostCatalog.referencesPlatformDefault &&
            Build.VERSION.SDK_INT >= 31 &&
            AndroidPlatformFontOracle.bootstrapCatalogOrNull() != null
        val catalog = if (hostCatalog.referencesPlatformDefault && !delegateToOracle) {
            hostCatalog.expandPlatformDefault(declaredSystemCatalog(context))
        } else {
            hostCatalog
        }
        val issues = catalog.declaredIssues.toMutableList()
        val loaded = mutableListOf<LoadedFace>()
        for ((catalogIndex, spec) in catalog.faceSpecs.withIndex()) {
            val axes = spec.variationAxes.toSortedMap()
            val source = runCatching { loadSourceLocked(context, spec.source) }.getOrElse { error ->
                issues += FontBackendCapabilityIssue(
                    code = "FontSourceUnavailable",
                    detail = "${spec.source.label}: ${error::class.simpleName}: ${error.message}",
                )
                continue
            }
            val loadedFace = runCatching {
                val id = stableFaceId(source.digestHex, spec.collectionIndex, axes)
                id to createOrGetFaceLocked(id, source.handle, spec.collectionIndex, axes)
            }.getOrElse { error ->
                issues += FontBackendCapabilityIssue(
                    code = "FontFaceLoadFailed",
                    detail = "${spec.source.label}#${spec.collectionIndex}: ${error::class.simpleName}: ${error.message}",
                )
                continue
            }
            val (id, native) = loadedFace
            val descriptor = ReplayableFontFaceDescriptor(
                id = id,
                familyAliases = sortedSetTableOf(spec.familyAliases, SortedTable::compareStrings),
                roles = spec.roles.toMutableList(),
                weight = spec.weight,
                italic = spec.italic,
                collectionIndex = spec.collectionIndex,
                sourceLabel = spec.source.label,
                variationAxes = sortedMapTableOf(axes, SortedTable::compareStrings),
            )
            descriptorById[id] = descriptor
            val opticalSize = spec.opticalSize?.let { rule ->
                val range = native.axisRange("opsz")
                if (range == null) {
                    issues += FontBackendCapabilityIssue(
                        code = "OpticalSizeAxisUnavailable",
                        detail = "${spec.source.label}#${spec.collectionIndex} declares OpticalSizeFollowsFontSize without an opsz axis",
                    )
                    null
                } else {
                    OpticalSizeInstancer(
                        rule = rule,
                        range = range,
                        sourceHandle = source.handle,
                        sourceDigestHex = source.digestHex,
                    )
                }
            }
            loaded += LoadedFace(
                catalogIndex = catalogIndex,
                familyKey = spec.familyKey,
                descriptor = descriptor,
                nativeFace = native,
                opticalSize = opticalSize,
            )
        }
        val familiesByRole = catalog.fallbackChains.mapValues { (role, familyKeys) ->
            familyKeys.mapNotNull { familyKey ->
                if (familyKey == AndroidFontCatalog.PLATFORM_DEFAULT_FAMILY) {
                    return@mapNotNull LoadedFamily(faces = emptyList(), platformOracle = true)
                }
                loaded
                    .filter { it.familyKey == familyKey && role in it.descriptor.roles }
                    .takeIf(List<LoadedFace>::isNotEmpty)
                    ?.let(::LoadedFamily)
            }
        }
        val roles = familiesByRole.filterValues(List<LoadedFamily>::isNotEmpty).keys
        val requiredRoles = setOf(FontRole.CjkText, FontRole.CjkPunctuation, FontRole.LatinText)
        val missingRoles = requiredRoles - roles
        if (missingRoles.isNotEmpty()) {
            issues += FontBackendCapabilityIssue(
                code = "MissingControlledFontFace",
                detail = "No loaded face covers roles ${missingRoles.joinToString()}",
            )
        }
        val report = FontBackendCapabilityReport(
            backend = "$BackendName;${NativeFontBridge.nativeVersions()}",
            sourceKind = catalog.sourceKind,
            faces = loaded.map { it.descriptor }.toMutableList(),
            issues = issues,
        )
        return LoadedAndroidFontCatalog(
            loadedFaces = loaded,
            familiesByRole = familiesByRole,
            revision = revision,
            usesPlatformDefaultOracle = usesPlatformDefaultOracle,
            capabilityReport = report,
        )
    }

    @TargetApi(31)
    private fun resolvePlatformDefaultFace(
        context: Context,
        request: ReplayableFontFaceRequest,
        acceptUncovered: Boolean,
    ): ResolvedNativeFontFace? {
        synchronized(lock) {
            platformFaceByRequest[request]?.let { return it }
        }
        val selection = AndroidPlatformFontOracle.select(request)
        synchronized(lock) {
            platformFaceByInstance[selection.instanceKey]?.let { loaded ->
                return ResolvedNativeFontFace(
                    descriptor = ReplayableFontFaceDescriptor(
                        id = loaded.descriptor.id,
                        familyAliases = sortedSetTableOf(selection.aliases, SortedTable::compareStrings),
                        roles = mutableListOf(request.role),
                        weight = selection.weight,
                        italic = selection.italic,
                        collectionIndex = loaded.descriptor.collectionIndex,
                        sourceLabel = loaded.descriptor.sourceLabel,
                        variationAxes = loaded.descriptor.variationAxes,
                    ),
                    nativeFace = loaded.nativeFace,
                    exactFamily = true,
                    exactStyle = true,
                    coversSelectionText = !selection.spansMultipleFaces,
                    replayable = !selection.spansMultipleFaces,
                    degradedRunAdvance = selection.degradedRunAdvance,
                    stringDrawCause = if (selection.spansMultipleFaces) PlatformStringDrawCause.MultiFace else null,
                ).also { resolved -> cachePlatformRequestLocked(request, resolved) }
            }
        }
        val axes = selection.variationAxes.toSortedMap()
        val resolved = runCatching {
            val native = synchronized(lock) {
                val source = loadSourceLocked(context, selection.source)
                val physicalId = stableFaceId(source.digestHex, selection.collectionIndex, axes)
                val id = platformReplayFaceId(
                    physicalId = physicalId,
                    syntheticBold = selection.syntheticBold,
                    syntheticItalic = selection.syntheticItalic,
                )
                val physicalFace = createOrGetFaceLocked(physicalId, source.handle, selection.collectionIndex, axes)
                faceById[id] = physicalFace
                if (selection.syntheticBold) syntheticBoldFaceIds += id
                if (selection.syntheticItalic) syntheticItalicFaceIds += id
                // The platform Font and the NativeFontFace above are two handles over the same
                // source, TTC index and variation axes. Retain it for exact Canvas.drawGlyphs
                // replay on API 31+, not only for the fake-bold special case.
                platformFontById[id] = selection.font
                physicalFace to id
            }
            val (nativeFace, id) = native
            ResolvedNativeFontFace(
                descriptor = ReplayableFontFaceDescriptor(
                    id = id,
                    familyAliases = sortedSetTableOf(selection.aliases, SortedTable::compareStrings),
                    roles = mutableListOf(request.role),
                    weight = selection.weight,
                    italic = selection.italic,
                    collectionIndex = selection.collectionIndex,
                    sourceLabel = buildString {
                        append(selection.source.label)
                        if (selection.syntheticBold) append(":syntheticBold=platform")
                        if (selection.syntheticItalic) append(":syntheticItalic=-0.25")
                    },
                    variationAxes = sortedMapTableOf(axes, SortedTable::compareStrings),
                ),
                nativeFace = nativeFace,
                exactFamily = true,
                exactStyle = true,
                coversSelectionText = nativeFace.hasGlyphs(request.selectionText),
                replayable = !selection.spansMultipleFaces,
                degradedRunAdvance = selection.degradedRunAdvance,
                stringDrawCause = if (selection.spansMultipleFaces) PlatformStringDrawCause.MultiFace else null,
            )
        }.getOrElse { return null }
        // CjkPunctuationHanFaceAnchor deliberately keeps the CJK face even when a proposed
        // display substitution is absent. HarfBuzz must report the missing glyph so layout can
        // roll the substitution back to its source form; silently switching to a Latin face here
        // would both defeat the role decision and conceal that evidence. A non-replayable
        // multi-face degrade intentionally does not cover the whole run, so it bypasses this
        // rejection and is handled by the platform string-draw path.
        if (resolved.replayable && !resolved.coversSelectionText && request.role != FontRole.CjkPunctuation) {
            if (!acceptUncovered) return null
            // End of a chain that delegates to the platform: the platform text stack draws the
            // segment; this face only supplies metrics. Not cached, the covering answer is.
            return resolved.copy(
                replayable = false,
                degradedRunAdvance = platformDegradeAdvance(request),
                stringDrawCause = PlatformStringDrawCause.NoCoveringFace,
            )
        }
        synchronized(lock) {
            descriptorById[resolved.descriptor.id] = resolved.descriptor
            platformFaceByInstance[selection.instanceKey] = PlatformLoadedFace(
                descriptor = resolved.descriptor,
                nativeFace = resolved.nativeFace,
            )
            cachePlatformRequestLocked(request, resolved)
        }
        return resolved
    }

    private fun cachePlatformRequestLocked(
        request: ReplayableFontFaceRequest,
        resolved: ResolvedNativeFontFace,
    ) {
        platformFaceByRequest[request] = resolved
        while (platformFaceByRequest.size > MaxPlatformRequestEntries) {
            val iterator = platformFaceByRequest.entries.iterator()
            if (!iterator.hasNext()) break
            iterator.next()
            iterator.remove()
        }
    }

    private fun stableFaceId(
        sourceDigestHex: String,
        collectionIndex: Int,
        variationAxes: Map<String, Float>,
    ): String {
        val axes = variationAxes.entries.joinToString(",") { (tag, value) ->
            "$tag=${value.toRawBits().toUInt().toString(16)}"
        }
        return buildString {
            append("tiqian-font:sha256:")
            append(sourceDigestHex)
            append(':')
            append(collectionIndex)
            if (axes.isNotEmpty()) {
                append(":axes:")
                append(axes)
            }
        }
    }

    /**
     * Sources are immutable for the process lifetime. Locator lookup avoids re-hashing a system
     * file for every platform request; digest lookup folds different locators with identical
     * content into one native mapping/direct buffer. A Face only retains this shared source.
     */
    private fun loadSourceLocked(context: Context, source: AndroidFontSource): LoadedNativeFontSource {
        val locator = source.locatorKey(context)
        sourceByLocator[locator]?.let { return it }
        val prepared = source.prepare(context)
        sourceByDigest[prepared.digestHex]?.let { existing ->
            if (prepared is PreparedAndroidFontSource.DescriptorRegion) prepared.descriptor.close()
            sourceByLocator[locator] = existing
            return existing
        }
        val handle = when (prepared) {
            is PreparedAndroidFontSource.FileMapping ->
                NativeFontBridge.nativeRegisterFileSource(prepared.path)
            is PreparedAndroidFontSource.DirectBuffer ->
                NativeFontBridge.nativeRegisterBufferSource(prepared.buffer, prepared.sizeBytes)
            is PreparedAndroidFontSource.DescriptorRegion ->
                NativeFontBridge.nativeRegisterDescriptorRegionSource(prepared.descriptor.detachFd(), prepared.offset, prepared.sizeBytes)
        }
        check(handle != 0L) { "Native font source registration did not return a handle" }
        return LoadedNativeFontSource(
            handle = handle,
            digestHex = prepared.digestHex,
            sizeBytes = prepared.sizeBytes,
        ).also { loaded ->
            sourceByLocator[locator] = loaded
            sourceByDigest[prepared.digestHex] = loaded
        }
    }

    private const val MaxPlatformRequestEntries = 4096
}

internal fun platformReplayFaceId(
    physicalId: String,
    syntheticBold: Boolean,
    syntheticItalic: Boolean,
): String = buildString {
    append(physicalId)
    if (syntheticBold) append(":syntheticBold=platform")
    if (syntheticItalic) append(":syntheticItalic=-0.25")
}

private fun wellKnownSystemPathCatalog(): AndroidFontCatalog {
    val cjkRoles = setOf(
        FontRole.CjkText,
        FontRole.CjkPunctuation,
        FontRole.Symbol,
        FontRole.Emoji,
        FontRole.Unknown,
    )
    val latinFallbackRoles = setOf(
        FontRole.LatinText,
        FontRole.CjkPunctuation,
        FontRole.Symbol,
        FontRole.Unknown,
    )
    fun face(
        path: String,
        index: Int,
        aliases: Set<String>,
        roles: Set<FontRole>,
        weight: Int = 400,
        italic: Boolean = false,
    ) = AndroidFontFaceSpec(
        source = AndroidFontSource.file(File(path)),
        collectionIndex = index,
        familyKey = if (FontRole.CjkText in roles) "well-known-cjk" else "well-known-latin",
        familyAliases = aliases,
        roles = roles,
        weight = weight,
        italic = italic,
    )
    return AndroidFontCatalog(
        sourceKind = "ControlledWellKnownSystemPaths",
        declaredIssues = listOf(
            FontBackendCapabilityIssue(
                code = "HostFontCatalogRecommendedBelowApi29",
                detail = "API 23-28 cannot enumerate system fonts publicly; install asset/file/ByteArray faces for OEM-portable production use",
            ),
        ),
        faceSpecs = listOf(
            face(
                "/system/fonts/NotoSansCJK-Regular.ttc",
                2,
                setOf("sans", "sans-serif", "noto sans cjk sc"),
                cjkRoles,
            ),
            face(
                "/system/fonts/NotoSansCJK-Bold.ttc",
                2,
                setOf("sans", "sans-serif", "noto sans cjk sc"),
                cjkRoles,
                weight = 700,
            ),
            face(
                "/system/fonts/NotoSansSC-Regular.otf",
                0,
                setOf("sans", "sans-serif", "noto sans sc"),
                cjkRoles,
            ),
            face(
                "/system/fonts/Roboto-Regular.ttf",
                0,
                setOf("sans", "sans-serif", "roboto"),
                latinFallbackRoles,
            ),
            face(
                "/system/fonts/Roboto-Bold.ttf",
                0,
                setOf("sans", "sans-serif", "roboto"),
                latinFallbackRoles,
                weight = 700,
            ),
            face(
                "/system/fonts/Roboto-Italic.ttf",
                0,
                setOf("sans", "sans-serif", "roboto"),
                latinFallbackRoles,
                italic = true,
            ),
        ),
    )
}

private fun <K> sortedSetTableOf(values: Iterable<K>, compare: (K, K) -> Int): SortedSetTable<K> =
    SortedTable.setBuilder(compare).also { builder -> values.forEach { builder.put(it) } }.build()

private fun <K, V> sortedMapTableOf(values: Map<K, V>, compare: (K, K) -> Int): SortedMapTable<K, V> =
    SortedTable.mapBuilder<K, V>(compare).also { builder -> values.forEach { (key, value) -> builder.put(key, value) } }.build()

private fun <K> SortedSetTable<K>.asIterable(): List<K> = (0 until size()).map { at(it) }

private fun <K, V> SortedMapTable<K, V>.asMap(): Map<K, V> =
    (0 until size()).associateTo(linkedMapOf()) { keyAt(it) to valueAt(it) }

internal fun variationTag(tag: String): Int =
    tag.fold(0) { result, char -> (result shl 8) or char.code }
