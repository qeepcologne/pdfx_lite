plugins {
    id("com.android.library")
}

//AGP 9 only: Kotlin is built in, so no `kotlin-android` plugin and no compat guard.
//`src/main/kotlin` is a default source dir.
android {
    namespace = "io.scer.pdf_renderer"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
    }

    //javac defaults to 11 while Kotlin follows the JDK toolchain (25 here), and AGP fails the build on the
    //mismatch. Pin both to 17, matching Flutter's own app template.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
}
