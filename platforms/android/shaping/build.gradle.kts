plugins {
    id("com.android.library")
}

android {
    namespace = "org.tiqian.shaping.android"
    compileSdk = 36

    defaultConfig {
        // The artifact remains loadable on the Compose API 23 floor. The
        // TextRunShaper implementation itself is guarded as an API 31-only
        // optional comparison/optimization backend.
        minSdk = 23
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(project(":boring-kotlin-f32"))

    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation(kotlin("test"))
}
