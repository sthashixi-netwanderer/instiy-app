allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Several plugins (flutter_ringtone_player 4.0.0+4, giphy_get) pin compileSdk
// 33 or lower while their resolved AndroidX dependencies require 34+, which
// fails checkDebugAarMetadata. Raise any plugin below the app's compileSdk
// (37 in app/build.gradle.kts). Keep the two values in sync. Raising a
// library's compileSdk is backward-compatible and does not change runtime
// behavior (unlike targetSdk/minSdk).
subprojects {
    fun raiseCompileSdk(target: Project) {
        val androidExtension = target.extensions.findByName("android")
        if (androidExtension is com.android.build.api.dsl.LibraryExtension &&
            (androidExtension.compileSdk ?: 0) < 37
        ) {
            androidExtension.compileSdk = 37
        }
    }
    // The Flutter Gradle plugin eagerly evaluates plugin projects while :app
    // is configured (via evaluationDependsOn above), so afterEvaluate is not
    // always registerable.
    if (state.executed) {
        raiseCompileSdk(project)
    } else {
        afterEvaluate { raiseCompileSdk(project) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
