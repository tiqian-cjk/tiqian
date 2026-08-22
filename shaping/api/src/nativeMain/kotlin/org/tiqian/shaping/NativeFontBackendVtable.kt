@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class, kotlin.experimental.ExperimentalNativeApi::class)

package org.tiqian.shaping

import kotlinx.cinterop.CPointer
import kotlinx.cinterop.pointed
import org.tiqian.shaping.backend.tiqian_font_backend_vtable_t

/**
 * Process-wide font backend vtable installed by the host binding (ADR 0050).
 * Mirrors the JS lane's `__TiqianFontBackend` global: one backend per process,
 * reinstalling the same protocol revision is a no-op, a different revision is a
 * named collision instead of a silent override.
 */
internal object NativeFontBackendRegistry {
    // Must equal TIQIAN_FONT_BACKEND_PROTOCOL_REVISION in
    // tiqian_font_backend.h; the install check reports a mismatch as a named
    // error instead of trusting the number.
    internal const val PROTOCOL_REVISION: UInt = 1u

    private var installedRevision: UInt = 0u
    private var installed: CPointer<tiqian_font_backend_vtable_t>? = null

    fun install(vtable: CPointer<tiqian_font_backend_vtable_t>?): Int {
        if (vtable == null) return INSTALL_INVALID
        val layout = vtable.pointed
        if (layout.protocol_revision != PROTOCOL_REVISION) return INSTALL_REVISION_MISMATCH
        if (layout.shape == null || layout.metrics == null || layout.release_string == null) {
            return INSTALL_INVALID
        }
        val current = installed
        if (current != null) {
            return if (installedRevision == PROTOCOL_REVISION) INSTALL_INSTALLED else INSTALL_COLLISION
        }
        installed = vtable
        installedRevision = PROTOCOL_REVISION
        return INSTALL_INSTALLED
    }

    fun require(): tiqian_font_backend_vtable_t =
        installed?.pointed ?: error("FontBackendNotInstalled")

    /** Test-only: the process-global install contract has no uninstall path. */
    internal fun resetForTests() {
        installed = null
        installedRevision = 0u
    }
}

private const val INSTALL_INSTALLED = 0
private const val INSTALL_COLLISION = 1
private const val INSTALL_REVISION_MISMATCH = 2
private const val INSTALL_INVALID = 3

/**
 * C ABI entry the Rust binding calls after it builds its font session. The
 * codes are `TIQIAN_FONT_BACKEND_*` in tiqian_font_backend.h. The vtable stays
 * owned by the installer and must outlive the process.
 */
@CName("tiqian_install_font_backend")
fun tiqianInstallFontBackend(vtable: CPointer<tiqian_font_backend_vtable_t>?): Int =
    NativeFontBackendRegistry.install(vtable)
