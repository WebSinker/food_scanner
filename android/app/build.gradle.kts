plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.food_ml"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11  // Changed from VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_11  // Changed from VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "11"  // Changed from "1.8"
    }

    defaultConfig {
        applicationId = "com.example.food_ml"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.16.0"))
    implementation("androidx.multidex:multidex:2.0.1")
}