plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "jp.lecturenotes.lecture_notes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "jp.lecturenotes.lecture_notes"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 試作版のため、署名の鍵をリポジトリに置いて固定している（オーナー了承済み）。
    // 鍵が毎回変わると上書き更新できず、アンインストールで講義データが消えるため。
    // ストアで公開する前には、鍵を作り直して GitHub の Secrets に移すこと。
    signingConfigs {
        create("release") {
            storeFile = file("release.jks")
            storePassword = "lecturenotes"
            keyAlias = "lecture-notes"
            keyPassword = "lecturenotes"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // コードを縮める処理（R8）が shared_preferences などのプラグインの
            // 呼び出し先まで消してしまい、起動時に NoSuchMethodError になったため無効にする。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
