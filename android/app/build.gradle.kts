plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.hknow.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.hknow.app"
        minSdk = 26
        targetSdk = 34
        versionCode = (project.findProperty("verCode") ?: "1").toString().toInt()
        versionName = (project.findProperty("verName") ?: "1.0").toString()
    }

    // Khóa ký cố định (commit trong repo) => các bản build sau cài đè lên bản trước được
    signingConfigs {
        getByName("debug") {
            storeFile = file("hknow-debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        // Bản debug được ký bằng khóa debug tự động => cài thẳng được, không cần keystore
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Chèn script ngay lúc tạo tài liệu (document start), giống WKUserScript bên iOS
    implementation("androidx.webkit:webkit:1.11.0")
}
