plugins {
    id("com.android.library")
}

//AGP 9 only, so no `kotlin-android` plugin and no compat guard. Kotlin still compiles whether or not the host sets
//`android.builtInKotlin=false` — Flutter's app template sets it, and its migrator re-adds it on every build.
//`src/main/kotlin` is a default source dir.
android {
    namespace = "io.scer.pdfx"
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
    //`-android`, not `-core`: `Messages.updateTexture` hops back to the platform thread with
    //`withContext(Dispatchers.Main)`, and the Main dispatcher on Android lives in this artifact, not in core. It
    //compiles either way -- with core alone it fails at *runtime* ("Module with the Main dispatcher had failed to
    //initialize"). It only worked because Flutter's embedding happens to pull `-android` in transitively via
    //androidx.lifecycle; that is Flutter's business to change, not a contract with us. `-android` depends on `-core`.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
