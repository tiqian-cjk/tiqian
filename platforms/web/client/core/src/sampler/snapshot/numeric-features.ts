// Numeric prefixes precede the engine's contextual punctuation features.
const NUMERIC_FEATURES = [
  ["lnum", "lining-nums", 1], ["onum", "oldstyle-nums", 1],
  ["pnum", "proportional-nums", 2], ["tnum", "tabular-nums", 2],
  ["frac", "diagonal-fractions", 4], ["afrc", "stacked-fractions", 4],
  ["ordn", "ordinal", 8], ["zero", "slashed-zero", 16],
] as const;

/** Decode a validated numeric prefix without discarding punctuation features. */
export function numericFeatureContract(features: readonly string[]): {
  fontVariantNumeric: string | null;
  roleFeatures: readonly string[];
} | null {
  let groups = 0;
  let count = 0;
  const variants: string[] = [];
  for (const tag of features) {
    const feature = NUMERIC_FEATURES.find(([name]) => name === tag);
    if (!feature) break;

    // Mutually exclusive CSS alternatives share a group.
    if (groups & feature[2]) return null;
    groups |= feature[2];
    variants.push(feature[1]);
    count++;
  }

  // A reset uses standard HarfBuzz feature syntax as plan evidence only.
  // Native shaping applies an empty numeric set for this explicit CSS normal.
  if (count === 0 && features[0] === "lnum=0") {
    variants.push("normal");
    count++;
  }
  const roleFeatures = features.slice(count);
  if (!["", "fwid", "pwid,palt"].includes(roleFeatures.join(","))) return null;
  return { fontVariantNumeric: variants.length ? variants.join(" ") : null, roleFeatures };
}

/** Paint the numeric override and any contextual punctuation under that run. */
export function numericFeatureStyles(features: readonly string[]): string[] {
  const contract = numericFeatureContract(features);
  if (!contract?.fontVariantNumeric) return [];
  const role = contract.roleFeatures.join(",");
  const eastAsian = role === "fwid" ? "full-width" : role ? "proportional-width" : "normal";
  const settings = role === "fwid" ? ', "fwid" 1' : role ? ', "pwid" 1' : "";
  return [
    `font-variant-numeric:${contract.fontVariantNumeric}!important`,
    `font-variant-east-asian:${eastAsian}!important`,
    `font-feature-settings:"halt" 0, "chws" 0, "palt" ${role === "pwid,palt" ? 1 : 0}${settings}!important`,
  ];
}
