plugins {
    id("com.android.library")
}

android {
    namespace = "org.tiqian.shaping.android"
    compileSdk = 36

    defaultConfig {
        // TextRunShaper (per-glyph ids/positions) requires API 31.
        minSdk = 31
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(project(":tiqian-shaping-api"))

    androidTestImplementation(project(":tiqian-layout"))
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation(kotlin("test"))
}
