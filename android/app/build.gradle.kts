plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.main_memo.memo_cat_project"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // ✅ core library desugaring 활성화 (flutter_local_notifications 요구)
        isCoreLibraryDesugaringEnabled = true

        // 프로젝트 현 설정 유지 (Java 11)
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        // 프로젝트 현 설정 유지 (JVM 11)
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.main_memo.memo_cat_project"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 임시: 디버그 키로 서명 (필요 시 릴리즈 키로 교체)
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ desugaring용 라이브러리 추가 (버전 2.0.4 권장)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // 다른 의존성들은 Flutter 플러그인이 자동으로 주입하므로 여기서는 추가 불필요
}
