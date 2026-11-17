plugins {
    id("com.android.library")
}

android {
    namespace = "org.tiqian.android.rendering"
    compileSdk = 36

    defaultConfig {
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
    api(project(":platforms:android:shaping"))

    testImplementation(kotlin("test-junit"))
    androidTestImplementation(project(":platforms:android:native-font"))
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation(kotlin("test"))
}
