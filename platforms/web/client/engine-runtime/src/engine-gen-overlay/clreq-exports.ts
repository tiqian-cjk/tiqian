// Thin JSON adapters over the generated CLREQ modules under ./org/tiqian.
// The generated classes live in the boring-generated tree copied from
// engine-haxe/out/ts/gen (generator revision: .haxelib/boring/git HEAD);
// this file owns only the wire seam: it renders the same JSON strings the
// former Kotlin @JsExport exports in ffi/js ClreqExports.kt produced, so
// consumers of @tiqian/ffi keep byte-identical output. The string escaper
// mirrors the Kotlin StringBuilder.appendJsonString helper (WireJson.kt)
// over UTF-16 code units, including lone surrogates, instead of
// JSON.stringify, which escapes them.

import { BopomofoParser } from "./org/tiqian/clreq/BopomofoParser.ts";
import { NumberSymbolCohesion } from "./org/tiqian/clreq/NumberSymbolCohesion.ts";

function appendJsonString(sink: string[], value: string): void {
  sink.push('"');
  for (let index = 0; index < value.length; index += 1) {
    const unit = value.charCodeAt(index);
    if (unit === 0x22) {
      sink.push('\\"');
    } else if (unit === 0x5c) {
      sink.push("\\\\");
    } else if (unit === 0x08) {
      sink.push("\\b");
    } else if (unit === 0x0c) {
      sink.push("\\f");
    } else if (unit === 0x0a) {
      sink.push("\\n");
    } else if (unit === 0x0d) {
      sink.push("\\r");
    } else if (unit === 0x09) {
      sink.push("\\t");
    } else if (unit < 0x20) {
      sink.push("\\u" + unit.toString(16).padStart(4, "0"));
    } else {
      sink.push(value[index]!);
    }
  }
  sink.push('"');
}

/** Parses a 注音 reading into its symbols + derived tone (ADR 0033). */
export function bopomofoParse(reading: string): string {
  const parsed = BopomofoParser.parse(reading);
  const sink: string[] = ['{"symbols":['];
  for (let index = 0; index < parsed.symbols.length; index += 1) {
    if (index > 0) sink.push(",");
    appendJsonString(sink, parsed.symbols[index]!);
  }
  sink.push('],"tone":');
  appendJsonString(sink, parsed.tone.kind);
  sink.push("}");
  return sink.join("");
}

/** Source-text ranges (inclusive [start,end] pairs) kept unbroken per CLREQ. */
export function numberSymbolCohesionUnbreakableRanges(text: string): string {
  const ranges = NumberSymbolCohesion.unbreakableRanges(text);
  const sink: string[] = ["["];
  for (let index = 0; index < ranges.length; index += 1) {
    if (index > 0) sink.push(",");
    sink.push("[" + ranges[index]!.start + "," + ranges[index]!.end + "]");
  }
  sink.push("]");
  return sink.join("");
}
