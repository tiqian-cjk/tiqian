#!/usr/bin/env bash
# The Gradle task set the release verification runs.
#
# Two entry points source this file instead of spelling the set out again:
#   .github/workflows/publish.yml   the release, driven from a v*.*.* tag
#   tools/staging-pipeline.sh     the same steps on every push to main
#
# Both must run the same set. The generated Kotlin test suite is not in this
# list: it is not a JUnit suite, so publish.yml runs it through the driver
# (boring test kotlin-f32) in its own step and staging-pipeline.sh runs the same
# command in its maven-local-publish stage.
#
# assemble is what compiles the modules outside publishedModules in
# build.gradle.kts: :demo, :demo:android, :demo:font-diagnostics and
# :tools:engine-probes. publishTiqianToMavenLocal touches none of them, so a staging run that only publishes reports green for a release
# path it never executed.
#
# A Gradle task the release verifies belongs here rather than in either caller.
RELEASE_GRADLE_TASKS=(
  assemble
  publishTiqianToMavenLocal
)
