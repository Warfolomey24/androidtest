plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    signingConfigs {
        getByName("debug") {
            storeFile = rootProject.file(".ci/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
    namespace = "dev.merlin.phone"
    compileSdk = 35
    defaultConfig { applicationId = "dev.merlin.phone"; minSdk = 29; targetSdk = 32; versionCode = 1; versionName = "0.1.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
