plugins {
    id("com.android.library")
}

android {
    namespace = "org.tiqian.android.view"
    compileSdk = 36

    defaultConfig {
        minSdk = 23
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    androidResources.enable = true

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(project(":boring-kotlin-f32"))
    api(project(":platforms:android:rendering"))
    implementation("androidx.core:core:1.16.0")
    implementation("androidx.customview:customview:1.2.0")

    testImplementation(kotlin("test-junit"))
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.recyclerview:recyclerview:1.4.0")
    androidTestImplementation(kotlin("test"))
}
