plugins {
    id("com.android.library")
}

//AGP 9 only: Kotlin is built in, so no `kotlin-android` plugin and no compat guard.
//`src/main/kotlin` is a default source dir, and Java compatibility comes from the toolchain.
android {
    namespace = "io.scer.pdf_renderer"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
}
