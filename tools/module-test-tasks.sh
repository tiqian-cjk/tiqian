#!/usr/bin/env bash
# The Gradle task set the module test lane runs.
#
# One entry point sources this file instead of spelling the set out again:
#   .github/workflows/module-tests.yml   every push to main and every pull request
#
# The names are unqualified on purpose. Gradle runs an unqualified task name in
# every project that has a task with that name, so a module that gains a test
# source set joins the lane without editing this file, and a module that loses
# one stops running without leaving a stale entry behind. A qualified list would
# have to name each project twice, and a module added later would stay untested
# until someone remembered to add it.
#
# The lane reports three different verdicts, because they do not prove the same
# thing:
#
#   1. execute       tests run on the machine that runs the lane; their pass/fail
#                    count is the lane's verdict.
#   2. probe         assertion classes that the probe runner executes one class
#                    at a time; they also run, with the same verdict.
#   3. compile only  test sources this runner can compile but cannot run.
#
# No array may carry --tests, --exclude or a skip switch: the lane reports the
# real verdict of every test source set, so a filtered or excluded test would be
# reported green without running.

# Tasks whose tests run on the runner and whose pass/fail count is the lane's
# verdict.
#
#   jvmTest               every Kotlin/JVM test source set: :platforms:compose:compose,
#                         :platforms:compose:material3 and
#                         :platforms:compose:skia-jvm carry a populated
#                         src/jvmTest; the remaining projects declare the task and
#                         report NO-SOURCE.
#   testDebugUnitTest     every Android unit test source set (src/test, the
#                         androidUnitTest source set): :demo:font-diagnostics,
#                         :platforms:android:native-font and
#                         :platforms:android:view carry one. These tests run on
#                         the host JVM, so they need no device and the lane
#                         executes them rather than compiling them.
MODULE_TEST_EXECUTE_TASKS=(
  jvmTest
  testDebugUnitTest
)

# Assertion classes that live in :tools:engine-probes.
#
# That module keeps the AWT shaper and the Skia comparison probes in jvmMain, so
# it declares no jvmTest source set and :tools:engine-probes:jvmTest is
# NO-SOURCE. The assertion classes among them are its *Test.kt files, currently
# AwtTextShaperTest (4 cases), InkBoundsCoverageTest (1) and
# AwtSkiaShapingComparisonTest (1); the *Probe.kt files are measurement and
# experiment tools, and some of them only run behind TIQIAN_RUN_EXPERIMENTS=1,
# so the lane leaves them to whoever runs a measurement.
#
# The task runs one class per invocation, so the lane runs one Gradle invocation
# per class. The price is one build configuration per class (about ten seconds
# with --no-daemon); the price of dropping them is losing six assertion cases
# that the lane executed before they moved here. If assertion classes keep
# accumulating in this module, add a task there that runs every *Test class in
# one invocation instead of growing this loop.
MODULE_TEST_PROBE_TASK=":tools:engine-probes:runProbe"

# Print the fully qualified name of every *Test.kt class under
# tools/engine-probes/src/jvmMain that imports kotlin.test.Test, one per line.
# Discovery is by source file so a class added there joins the lane by itself.
module_test_probe_classes() {
  local root="${1:-.}"
  local dir="$root/tools/engine-probes/src/jvmMain"
  [ -d "$dir" ] || return 0
  local file package
  while IFS= read -r file; do
    package=$(sed -n 's/^package[[:space:]]\{1,\}\([A-Za-z0-9_.]*\).*$/\1/p' "$file" | head -n 1)
    printf '%s.%s\n' "$package" "$(basename "$file" .kt)"
  done < <(grep -rl --include='*Test.kt' '^import kotlin\.test\.Test' "$dir" | sort)
}

# Tasks that only compile test sources whose tests cannot run on this runner.
#
#   compileDebugAndroidTestKotlin        the androidTest source set of every
#                                        Android library and application module:
#                                        :platforms:android:shaping,
#                                        :platforms:android:native-font,
#                                        :platforms:android:rendering,
#                                        :platforms:android:view and
#                                        :demo:android. These are instrumented
#                                        tests: they run inside an emulator or on
#                                        a device through connectedDebugAndroidTest,
#                                        and a GitHub Linux runner has neither.
#                                        The lane therefore reports "compiles" and
#                                        never "passes" for them.
#   compileAndroidDeviceTest             the androidDeviceTest source set of the
#                                        Kotlin Multiplatform Android targets:
#                                        :platforms:compose:compose. Instrumented
#                                        for the same reason as androidTest.
#   compileTestKotlinMacosArm64          the generated engine test sources of
#   compileTestKotlinIosArm64            :boring-kotlin-f32 for each Apple
#   compileTestKotlinIosSimulatorArm64   Kotlin/Native target it publishes. The
#                                        Kotlin/Native backend emits the test
#                                        klib on Linux, but linking the test
#                                        binary and running it needs macOS and
#                                        the Apple linker, which no Linux runner
#                                        has. The lane compiles the klib and
#                                        never runs the tests. The Apple
#                                        frontend is a SwiftPM package under
#                                        platforms/apple (ADR 0064) and is not a
#                                        Gradle module.
#
# The androidTest and androidDeviceTest modules are also why the lane is not a
# release lane: it runs without a device by design, and a green run says the
# instrumented sources compile, not that they pass.
MODULE_TEST_COMPILE_ONLY_TASKS=(
  compileDebugAndroidTestKotlin
  compileAndroidDeviceTest
  compileTestKotlinMacosArm64
  compileTestKotlinIosArm64
  compileTestKotlinIosSimulatorArm64
)
