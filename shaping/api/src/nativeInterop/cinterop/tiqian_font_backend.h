#ifndef TIQIAN_FONT_BACKEND_H
#define TIQIAN_FONT_BACKEND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Tiqian font backend protocol. ADR 0050 (PackedFfiCalls).
 *
 * The layout engine (Kotlin/Native static library) calls the host font session
 * through this vtable. One shape callback writes a whole segment as a packed
 * buffer; one metrics callback writes a fixed record. A caller that under-sized
 * the buffer learns the required size from the return value and retries once,
 * so a request costs at most two callbacks. This header is the single source
 * of truth for both sides: cinterop compiles it into Kotlin, and the Rust
 * binding compiles it directly.
 */

/* Versions the packed buffer layout and the vtable shape, not the engine. */
#define TIQIAN_FONT_BACKEND_PROTOCOL_REVISION 1u

/* Shape buffer starts with "TQPS" in native endianness (all targets LE). */
#define TIQIAN_SHAPE_BUFFER_MAGIC 0x54515053u

/* Install results for tiqian_install_font_backend. */
#define TIQIAN_FONT_BACKEND_INSTALLED 0
#define TIQIAN_FONT_BACKEND_COLLISION 1
#define TIQIAN_FONT_BACKEND_REVISION_MISMATCH 2
#define TIQIAN_FONT_BACKEND_INVALID 3

/*
 * Shape buffer layout (offsets from the start, u32 = 4 bytes, f64 = 8):
 *
 *   0   u32 magic (TIQIAN_SHAPE_BUFFER_MAGIC)
 *   4   u32 version (equals TIQIAN_FONT_BACKEND_PROTOCOL_REVISION)
 *   8   u32 glyphCount
 *   12  u32 featureCount
 *   16  u32 unsafeBreakCount
 *   20  u32 reserved (0)
 *   24  f64 totalAdvance
 *   32  u32 faceId offset, 36 u32 faceId length
 *   40  u32 instanceId offset, 44 u32 instanceId length
 *   48  u32 script offset, 52 u32 script length
 *   56  u32 features offset, 60 u32 features length
 *   64  glyphCount records of 8 f64: id, advance, x, y, bounds[4]
 *       (bounds left, top, right, bottom; all four NaN when the glyph has no
 *       ink extents)
 *   then the string area: UTF-8 bytes, features joined with U+001F
 *
 * Offsets are absolute from the buffer start. Strings are not NUL terminated.
 */

/*
 * Returns the number of bytes the packed result needs. When that fits the
 * given capacity the buffer holds a complete result. When it does not the
 * callback writes nothing and the caller retries with a larger buffer. On
 * failure returns -1 and sets *error_out to a named error string allocated by
 * the session; the caller releases it with release_string.
 */
typedef int64_t (*tiqian_shape_fn)(
    const char* session_id,
    const char* display_text,
    const char* serialized_families,
    double font_size,
    int32_t font_weight,
    int32_t italic,
    const char* locale,
    const char* role,
    const char* source_text,
    uint8_t* buffer,
    uint64_t capacity,
    char** error_out);

/*
 * Writes five f64 values: ascent, descent, leading, typo ascent, typo descent.
 * NaN marks a missing optional metric (typo values only). Returns 0 on
 * success, -1 on failure with *error_out set as by shape.
 */
typedef int64_t (*tiqian_metrics_fn)(
    const char* session_id,
    const char* serialized_families,
    double font_size,
    int32_t font_weight,
    int32_t italic,
    const char* role,
    const char* face_selection_text,
    double* out_metrics,
    char** error_out);

/* Releases a session-owned error string. Accepts NULL. */
typedef void (*tiqian_release_string_fn)(const char* string);

typedef struct {
    uint32_t size;               /* sizeof(this struct); check before use */
    uint32_t protocol_revision;  /* TIQIAN_FONT_BACKEND_PROTOCOL_REVISION */
    tiqian_shape_fn shape;
    tiqian_metrics_fn metrics;
    tiqian_release_string_fn release_string;
} tiqian_font_backend_vtable_t;

/*
 * Installs the process-wide font backend. Reinstalling the same protocol
 * revision is a no-op. Returns TIQIAN_FONT_BACKEND_INSTALLED on success;
 * TIQIAN_FONT_BACKEND_COLLISION when a different protocol revision is already
 * installed; TIQIAN_FONT_BACKEND_REVISION_MISMATCH when the vtable targets
 * another protocol revision; TIQIAN_FONT_BACKEND_INVALID on a NULL vtable or
 * missing callbacks. The vtable pointer must stay valid for the process
 * lifetime.
 */
int32_t tiqian_install_font_backend(const tiqian_font_backend_vtable_t* vtable);

#ifdef __cplusplus
}
#endif

#endif /* TIQIAN_FONT_BACKEND_H */
