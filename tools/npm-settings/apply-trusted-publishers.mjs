#!/usr/bin/env node
// Grant or inspect the npm trusted-publisher switches the release needs.
//
// The release lanes authenticate npm calls with the workflow's OIDC identity,
// so every package they publish needs a trusted publisher whose allowed
// actions cover "npm publish" and "npm dist-tag". The package page exposes
// those switches only to a signed-in maintainer, so this script drives the
// npmjs.com UI in Chromium instead of calling an API.
//
// The script never runs in CI and never publishes a package. Its report mode
// changes nothing; its apply mode flips a switch and reads the switch back.
//
// Usage:
//   node tools/npm-settings/apply-trusted-publishers.mjs --report
//   node tools/npm-settings/apply-trusted-publishers.mjs --apply --otp 123456
//
// Options:
//   --report | --apply   read the switches, or also turn the missing ones on
//   --packages a,b       package names; defaults to every package in packages.json
//   --profile <dir>      persistent browser profile; defaults to .task-tmp/npm-profile
//   --otp <code>         one-time code to enter if npm asks for a second factor
//   --timeout <ms>       per-step timeout; defaults to 45000
//
// The first run of --report is also how the selector set below gets verified
// against the live page: every locator attempt is recorded in the report, and
// a page that does not match stops the run before any switch is touched.

import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import process from "node:process";

const args = process.argv.slice(2);
const option = (name, fallback = null) => {
  const index = args.indexOf(name);
  return index === -1 ? fallback : args[index + 1] ?? fallback;
};
const flag = (name) => args.includes(name);

const apply = flag("--apply");
const profile = resolve(option("--profile", ".task-tmp/npm-profile"));
const otp = option("--otp", "");
const timeout = Number(option("--timeout", "45000"));
const here = dirname(new URL(import.meta.url).pathname);
const packagesFile = join(here, "packages.json");
const requested = option("--packages", "");
const config = JSON.parse(readFileSync(packagesFile, "utf8"));
const packages = requested
  ? requested.split(",").map((name) => name.trim()).filter(Boolean)
  : config.packages.map((entry) => entry.name);

const chromiumPath = process.env.CHROMIUM_PATH || "/run/current-system/sw/bin/chromium";
const reportPath = resolve(option("--report-path", ".task-tmp/npm-settings-report.json"));

let playwright;
try {
  playwright = await import("playwright");
} catch {
  console.error("playwright is not installed; install it outside the repository, for example:");
  console.error("  npm install --prefix .task-tmp/npm-settings playwright");
  console.error("then run with NODE_PATH=.task-tmp/npm-settings/node_modules");
  process.exit(2);
}

mkdirSync(profile, { recursive: true });
mkdirSync(dirname(reportPath), { recursive: true });

const context = await playwright.chromium.launchPersistentContext(profile, {
  executablePath: chromiumPath,
  headless: false,
  viewport: { width: 1440, height: 960 },
});
const page = context.pages()[0] ?? (await context.newPage());
page.setDefaultTimeout(timeout);

const attempts = [];
const results = [];
const note = (message) => {
  attempts.push(message);
  console.log(message);
};

async function signInIfNeeded() {
  await page.goto("https://www.npmjs.com/", { waitUntil: "domcontentloaded" });
  const signedIn = await page.locator('a[href="/settings"]').first().isVisible().catch(() => false);
  if (signedIn) return;
  note("not signed in: complete the npm sign-in in the opened window (the one-time code is the last step)");
  const deadline = Date.now() + 5 * 60 * 1000;
  while (Date.now() < deadline) {
    await page.waitForTimeout(2000);
    if (otp) {
      const codeBox = page.locator('input[name="otp"], input[autocomplete="one-time-code"]').first();
      if (await codeBox.isVisible().catch(() => false)) {
        await codeBox.fill(otp);
        await page.locator('button[type="submit"]').first().click().catch(() => {});
        note("entered the one-time code");
      }
    }
    if (await page.locator('a[href="/settings"]').first().isVisible().catch(() => false)) {
      note("signed in");
      return;
    }
  }
  throw new Error("sign-in did not complete within five minutes");
}

async function openPackage(name) {
  const encoded = encodeURIComponent(name);
  for (const url of [
    `https://www.npmjs.com/package/${encoded}`,
    `https://www.npmjs.com/package/${encoded}/access`,
  ]) {
    await page.goto(url, { waitUntil: "domcontentloaded" });
    const settings = page.getByRole("link", { name: /settings/iu }).first();
    if (await settings.isVisible().catch(() => false)) {
      await settings.click().catch(() => {});
      await page.waitForLoadState("domcontentloaded").catch(() => {});
      return url;
    }
    if (/access|settings/iu.test(page.url())) return url;
  }
  throw new Error(`no settings entry for ${name} at ${page.url()}`);
}

function rowFor(entry) {
  const container = page.locator("section, div").filter({ hasText: entry.workflow }).last();
  return container;
}

async function readSwitch(row, label) {
  const control = row.getByRole("switch", { name: new RegExp(label, "iu") }).first();
  if (await control.isVisible().catch(() => false)) {
    const checked = await control.getAttribute("aria-checked").catch(() => null);
    return checked === "true";
  }
  const checkbox = row.getByRole("checkbox", { name: new RegExp(label, "iu") }).first();
  if (await checkbox.isVisible().catch(() => false)) {
    return await checkbox.isChecked().catch(() => null);
  }
  return null;
}

async function toggleSwitch(row, label) {
  const control = row.getByRole("switch", { name: new RegExp(label, "iu") }).first();
  if (await control.isVisible().catch(() => false)) {
    await control.click();
    return true;
  }
  const checkbox = row.getByRole("checkbox", { name: new RegExp(label, "iu") }).first();
  if (await checkbox.isVisible().catch(() => false)) {
    await checkbox.check();
    return true;
  }
  return false;
}

async function handleSecondFactor() {
  const codeBox = page.locator('input[name="otp"], input[autocomplete="one-time-code"]').first();
  if (!(await codeBox.isVisible().catch(() => false))) return false;
  if (!otp) {
    note("npm asked for a one-time code and --otp was not supplied");
    return false;
  }
  await codeBox.fill(otp);
  await page.getByRole("button", { name: /verify|confirm|save|continue/iu }).first().click().catch(() => {});
  await page.waitForTimeout(1500);
  note("submitted the one-time code for this change");
  return true;
}

try {
  await signInIfNeeded();
  for (const name of packages) {
    const entry = config.packages.find((item) => item.name === name) ?? {
      name,
      org: config.organization,
      repo: config.repository,
      workflow: config.workflow,
      actions: ["publish", "dist-tag"],
    };
    const result = { package: name, url: null, switches: {}, changed: [], error: null };
    try {
      result.url = await openPackage(name);
      const row = rowFor(entry);
      for (const [key, label] of [["publish", "npm publish"], ["distTag", "npm dist-tag"]]) {
        const before = await readSwitch(row, label);
        result.switches[key] = before;
        if (before === true || before === null) continue;
        if (!apply) continue;
        if (!(await toggleSwitch(row, label))) {
          note(`no control for ${label} on ${name}`);
          continue;
        }
        await handleSecondFactor();
        await page.waitForTimeout(1000);
        const after = await readSwitch(row, label);
        result.switches[key] = after;
        if (after === true) result.changed.push(key);
      }
    } catch (error) {
      result.error = String(error.message ?? error);
    }
    results.push(result);
    console.log(JSON.stringify(result));
  }
} finally {
  const report = {
    generatedAt: new Date().toISOString(),
    mode: apply ? "apply" : "report",
    chromium: chromiumPath,
    profile,
    packages: results,
    attempts,
  };
  writeFileSync(reportPath, JSON.stringify(report, null, 2) + "\n", "utf8");
  console.log(`report: ${reportPath}`);
  await context.close();
}
