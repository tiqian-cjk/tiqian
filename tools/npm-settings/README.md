# npm trusted publisher switches

The release lanes authenticate npm with the workflow's OIDC identity, so no
long-lived token is involved. Two switches on each package's trusted publisher
govern what that identity may do:

- **npm publish** uploads the release tarballs.
- **npm dist-tag** moves the `latest` tag after the upload. npm disables this
  switch by default, so a package whose trusted publisher only allows publish
  publishes fine and then fails at the dist-tag step.

`apply-trusted-publishers.mjs` reports those switches and, with `--apply`,
turns the missing ones on. It drives the npmjs.com UI because the switches are
maintainer-only; there is no API for them.

## Before you run it

- Playwright must be installed outside the repository:
  `npm install --prefix .task-tmp/npm-settings playwright`
- The Chromium binary comes from `CHROMIUM_PATH`, defaulting to
  `/run/current-system/sw/bin/chromium`.
- The profile directory keeps the npm session between runs, so the sign-in and
  the one-time code are only needed once per profile.

## Running it

Report first; it changes nothing and records what each page actually shows:

```shell
NODE_PATH=.task-tmp/npm-settings/node_modules \
  node tools/npm-settings/apply-trusted-publishers.mjs --report
```

Then apply, with the one-time code in hand:

```shell
NODE_PATH=.task-tmp/npm-settings/node_modules \
  node tools/npm-settings/apply-trusted-publishers.mjs --apply --otp 123456
```

Both modes write `.task-tmp/npm-settings-report.json`. A package whose switches
stay `null` did not expose the control under the locator the script tried; the
report's `attempts` list shows which page each package resolved to, and the run
stops before touching a switch it could not read.

## After it runs

The dist-tag step in `tools/npm-dist-tag.sh` reads the current tags before it
writes, so a release that already published a version and failed at the tag can
be re-run without republishing. `tools/npm-publish.sh` compares the local
tarball's sha1 with the published shasum for the same reason.
