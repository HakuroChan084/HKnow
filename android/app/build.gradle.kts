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
        versionCode = 1
        versionName = "1.0"
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
