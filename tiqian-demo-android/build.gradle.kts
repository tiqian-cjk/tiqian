plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "org.tiqian.demo.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "org.tiqian.demo.android"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }
}

dependencies {
    implementation(project(":tiqian-demo"))
    implementation("androidx.activity:activity-compose:1.11.0")
}
