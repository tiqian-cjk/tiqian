# npm trusted publisher switches

Every npm write in the release authenticates with the workflow's OIDC identity,
so no token is involved. Two switches on each package's trusted publisher
decide what that identity may do:

- **Allow npm publish** uploads the release tarballs.
- **Allow npm dist-tag** moves the `latest` tag after the upload. npm ships
  this switch off, so a connection that only allows publish publishes the
  package and then fails at the dist-tag step.

Both live behind the npmjs.com UI, in the package's Settings tab under
"Trusted Publisher", inside the Edit dialog of the connection. There is no API
for them, so they are changed through the Chromium MCP with
`mcp__rea__capture_browser_scenario` attached to a signed-in browser.

## The procedure

1. The browser must already be signed in to npmjs.com; the scenario attaches to
   an existing tab and never handles the sign-in.
2. Copy `enable-dist-tag.scenario.json`, replace `<package>`, `<target id>`
   and `<otp>`, and run it once per package.
3. Verify by inspecting the same tab afterwards: the connection card lists its
   allowed actions, and `npm dist-tag` must appear beside `npm publish`.

## Two constraints that the scenario cannot work around

- **The code must be in the same run.** `capture_browser_scenario` navigates to
  `start_url` before the first action, so a save that waits for a one-time code
  cannot be finished by a second scenario: the navigation discards the pending
  save. The `fill-otp` step therefore sits in the same action list.
- **A passkey cannot be typed.** If the account challenges with a passkey rather
  than a one-time code, the step has to be completed on the device; the
  scenario stops at the challenge and the report shows the step that failed.

## Current state

`packages.json` lists the eleven packages the `release.yml` entrypoint
publishes. A connection shows "Pending validation" until its first successful
publish; validation is not the same as the allowed-actions switches.
