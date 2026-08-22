#ifndef TIQIAN_LAYOUT_ABI_H
#define TIQIAN_LAYOUT_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Tiqian engine layout ABI. ADR 0050 amendment (EngineLevelAbi).
 *
 * The Rust binding packs one LayoutInput into a versioned request buffer and
 * reads back the plan JSON the Kotlin engine produced. This header is the
 * single source of truth for the byte layout; the Kotlin exit module and the
 * Rust sys crate both mirror it. All targets are little endian.
 */

/* Versions the request buffer layout and the symbol set, not the engine. */
#define TIQIAN_LAYOUT_ABI_PROTOCOL_REVISION 1u

/* Request buffers start with "TQLR". */
#define TIQIAN_LAYOUT_REQUEST_MAGIC 0x54514C52u

/* Status codes for tiqian_layout_paragraph. */
#define TIQIAN_LAYOUT_OK 0
#define TIQIAN_LAYOUT_ERROR 1

/*
 * Request buffer layout. A fixed 32-byte header, then sequential sections
 * read by cursor. u32 = 4 bytes, f32 = IEEE 754, strings are u32 byte length
 * plus UTF-8 bytes, arrays are u32 count plus records. Nothing is NUL
 * terminated and no offsets are stored; readers walk the sections in order.
 *
 *   0   u32 magic (TIQIAN_LAYOUT_REQUEST_MAGIC)
 *   4   u32 version (TIQIAN_LAYOUT_ABI_PROTOCOL_REVISION)
 *   8   f32 maxWidthPx
 *   12  f32 fontSizePx
 *   16  f32 lineHeightPx
 *   20  f32 firstLineIndentIc
 *   24  i32 fontWeight
 *   28  u8  italic (0 or 1)
 *   29  u8  lineLengthGridEnabled (0 or 1)
 *   30  u16 reserved (0)
 *
 * Sections, in order:
 *
 *   locale            string
 *   families          array of string
 *   text              string
 *   textSpans         array of record:
 *                       i32 start, i32 end, f32 fontSize, i32 fontWeight,
 *                       u8 italic (0 or 1), f32 baselineShift,
 *                       u32 familyCount, then that many strings
 *   sourceBoundaries  array of i32
 *   lineBreakSpans    array of record: i32 start, i32 end, i32 policy
 *   inlineBoxes       array of record:
 *                       i32 start, i32 end, f32 inlineStart, f32 inlineEnd,
 *                       i32 outerSpacing
 *   fontSessionId     string
 *
 * Every text index counts UTF-16 code units, the engine TextRange space.
 * Callers holding UTF-8 must convert indices before packing. All f32 values
 * must be finite; all span and box ranges must satisfy 0 <= start < end
 * <= UTF-16 length of text, and boundary offsets 0 <= offset <= length.
 *
 * Enum codes: policy 0 = ProgressiveTechnical; outerSpacing 0 = Narrow,
 * 1 = Source. Unknown codes are named errors.
 *
 * Named protocol errors reported through error_out: InvalidLayoutRequest,
 * InvalidLayoutRequestMagic, InvalidLayoutRequestVersion,
 * InvalidLayoutRequestTruncated, InvalidLayoutRequestValue,
 * InvalidLayoutRequestIndex, InvalidLayoutRequestCode,
 * InvalidLayoutRequestTrailing. Domain validation (empty paragraph, font
 * weight range, and the names the npm tests assert) belongs to the Rust
 * caller before packing; the exit re-checks structure only.
 */

/*
 * Runs the layout for one packed request. On success returns
 * TIQIAN_LAYOUT_OK and sets *plan_json_out to a NUL-terminated UTF-8 plan
 * JSON string allocated on the native heap; *error_out is set to NULL. On
 * failure returns TIQIAN_LAYOUT_ERROR, sets *error_out to a NUL-terminated
 * named issue string, and sets *plan_json_out to NULL. Kotlin exceptions
 * never cross this boundary. Both pointers are released with
 * tiqian_release_buffer. The call is safe to issue concurrently; the
 * installed font backend owns its thread safety.
 */
int32_t tiqian_layout_paragraph(
    const uint8_t* request,
    uint64_t request_len,
    char** plan_json_out,
    char** error_out);

/* Releases a buffer this ABI allocated. Accepts NULL. */
void tiqian_release_buffer(char* buffer);

/*
 * Installs the process-wide font backend vtable. Signature and result codes:
 * tiqian_font_backend.h in shaping/api. Re-exported here because the static
 * library only exports @CName symbols of this module.
 */
int32_t tiqian_install_font_backend(const void* vtable);

#ifdef __cplusplus
}
#endif

#endif /* TIQIAN_LAYOUT_ABI_H */
