plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// CI passes BUILD_NUMBER (the run number) and SITE (the website from brand/brand.txt).
val buildNo = (System.getenv("BUILD_NUMBER") ?: "1").toIntOrNull() ?: 1
val site = (System.getenv("SITE") ?: "").trim().trimEnd('/')

android {
    namespace = "com.liteplayer.recorder"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.liteplayer.recorder"
        minSdk = 24
        targetSdk = 34
        versionCode = buildNo
        versionName = "1.0.$buildNo"
        buildConfigField("String", "SITE", "\"$site\"")
    }

    buildFeatures { buildConfig = true }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Signed again with the app key in CI when the key secrets are set.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
