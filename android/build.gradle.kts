plugins {
    id("com.android.library")
}

//Single source for both compile tasks: javac defaults to 11, Kotlin follows the JDK toolchain, and AGP 9 fails the
//build unless the two share one target. 17 matches Flutter 3.44's own Gradle templates; raise it with the Flutter floor.
val javaVersion = JavaVersion.VERSION_17

//AGP 9 only, so no `kotlin-android` plugin and no compat guard. Kotlin still compiles whether or not the host sets
//`android.builtInKotlin=false` — Flutter's app template sets it, and its migrator re-adds it on every build.
//`src/main/kotlin` is a default source dir.
android {
    namespace = "io.scer.pdfx"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = javaVersion
        targetCompatibility = javaVersion
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(javaVersion.majorVersion)
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
