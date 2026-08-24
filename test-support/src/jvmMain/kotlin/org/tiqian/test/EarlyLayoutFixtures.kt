package org.tiqian.test

/**
 * The shared conformance corpus, loaded from the language-neutral JSON files under
 * `conformance/fixtures`. The name predates the conformance move; JVM tests and the
 * layout report keep consuming it unchanged.
 */
object EarlyLayoutFixtures {
    val all: List<LayoutFixture> by lazy { ConformanceFixtures.loadAll() }
}
