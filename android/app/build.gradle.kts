plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.shoo.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.shoo.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        // Same hosts as ios/ShooApp/App/AppConfig.swift. Keep them equal.
        buildConfigField("String", "CLOUD_API_URL", "\"https://shoo-api.afindo-mi01.workers.dev\"")
        buildConfigField("String", "PUBLIC_BASE_URL", "\"https://join.shoo.ai.id\"")
        // The emulator reaches `wrangler dev` on the computer at 10.0.2.2.
        buildConfigField("String", "LOCAL_API_URL", "\"http://10.0.2.2:8787\"")
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            // Debug stays on layers 1–2 (no pages sent to the AI Worker), like iOS Debug builds (#82).
            buildConfigField("String", "AI_URL", "\"\"")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            buildConfigField("String", "AI_URL", "\"https://shoo-ai.afindo-mi01.workers.dev\"")
            // No release keystore in the repo yet: sign with the debug key so the APK installs for testing.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
        // The port uses a few Compose APIs still marked experimental (sheets, pagers, flow rows, AnimatedContent).
        freeCompilerArgs += listOf(
            "-opt-in=androidx.compose.foundation.ExperimentalFoundationApi",
            "-opt-in=androidx.compose.foundation.layout.ExperimentalLayoutApi",
            "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
            "-opt-in=androidx.compose.animation.ExperimentalAnimationApi",
            "-opt-in=androidx.compose.ui.ExperimentalComposeUiApi",
            "-opt-in=androidx.compose.ui.text.ExperimentalTextApi",
        )
    }

    // contracts/fixtures/ is the mock data for the Mock backend (copied in, never edited here).
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/fixtures"))
    // The iOS string catalog (all copy) + android.xcstrings (Android-only copy), read by support/L10n.kt.
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/l10n"))
}

val copyFixtures by tasks.registering(Copy::class) {
    from(rootProject.file("../contracts/fixtures"))
    include("*.json")
    into(layout.buildDirectory.dir("generated/fixtures/fixtures"))
}

// ios/ShooApp/Resources/Localizable.xcstrings is the one source of copy (PORTING.md "Copy"); never edited here.
val copyStringCatalogs by tasks.registering(Copy::class) {
    from(rootProject.file("../ios/ShooApp/Resources/Localizable.xcstrings"))
    from(file("src/main/l10n")) { include("android*.xcstrings") }
    into(layout.buildDirectory.dir("generated/l10n/l10n"))
}
tasks.named("preBuild") { dependsOn(copyFixtures, copyStringCatalogs) }

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    // SF Symbols → Material Symbols (components/Symbols.kt).
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.animation:animation")
    // QR codes (invite code, Pairing).
    implementation("com.google.zxing:core:3.5.3")
    // QR scanner (Pairing).
    val cameraX = "1.4.1"
    implementation("androidx.camera:camera-camera2:$cameraX")
    implementation("androidx.camera:camera-lifecycle:$cameraX")
    implementation("androidx.camera:camera-view:$cameraX")
    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
