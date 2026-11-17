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
# The lane splits the set in two because "the test ran and passed" and "the test
# compiles" are different claims. A task belongs in the first array only when
# its tests execute on the machine that runs the lane; everything else belongs in
# the second array, where the lane claims compilation and nothing more.
#
# Neither array may carry --tests, --exclude or a skip switch: the lane reports
# the real verdict of every test source set, so a filtered or excluded test would
# be reported green without running.

# Tasks whose tests run on the Linux runner and whose pass/fail count is the
# lane's verdict.
#
#   jvmTest               every Kotlin/JVM test source set: :platforms:jvm:shaping,
#                         :platforms:jvm:skia, :platforms:compose:compose and
#                         :platforms:compose:material3 carry a populated
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

# Tasks that only compile test sources whose tests cannot run on this runner.
#
#   compileDebugAndroidTestKotlin        the androidTest source set of every
#                                        Android library and application module:
#                                        :platforms:android:shaping,
#                                        :platforms:android:native-font,
#                                        :platforms:android:rendering,
#                                        :platforms:android:view and
#                                        :demo:android. These are
#                                        instrumented tests: they run inside an
#                                        emulator or on a device through
#                                        connectedDebugAndroidTest, and a GitHub
#                                        Linux runner has neither. The lane
#                                        therefore reports "compiles" and never
#                                        "passes" for them.
#   compileAndroidDeviceTest             the androidDeviceTest source set of the
#                                        Kotlin Multiplatform Android targets:
#                                        :platforms:compose:compose. Instrumented
#                                        for the same reason as androidTest.
#   compileTestKotlinMacosArm64          the appleTest source set of
#   compileTestKotlinIosArm64            :platforms:apple:shaping,
#   compileTestKotlinIosSimulatorArm64   :platforms:apple:frontend and
#                                        :platforms:apple:frontend:coretext-render
#                                        for each Apple Kotlin/Native target. The
#                                        Kotlin/Native backend emits the test
#                                        klib on Linux, but linking the test
#                                        binary and running it needs macOS and
#                                        the Apple linker, which no Linux runner
#                                        has. The lane compiles the klib and
#                                        never runs the tests.
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
