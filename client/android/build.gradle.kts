import com.android.build.gradle.internal.api.BaseVariantOutputImpl

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
    id("property-delegate")
}

kotlin {
    jvmToolchain(17)
}

// get values from gradle or local properties
val qtTargetSdkVersion: String by gradleProperties
val qtTargetAbiList: String by gradleProperties
val outputBaseName: String by gradleProperties

android {
    namespace = "org.amnezia.vpn"

    buildFeatures {
        viewBinding = true
    }

    androidResources {
        // don't compress Qt binary resources file
        noCompress += "rcc"
    }

    packaging {
        // compress .so binary libraries
        jniLibs.useLegacyPackaging = true
        // only the ABIs the app itself is built for: a library that came for another ABI
        // inside an AAR (libgojni has all four) would make a phone of that ABI pick it and
        // then not find the app's own library
        val builtAbis = qtTargetAbiList.split(',').map { it.trim() }.toSet()
        listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64").filterNot { it in builtAbis }
            .forEach { jniLibs.excludes += "/lib/$it/**" }
    }

    defaultConfig {
        applicationId = "org.lodestar.vpn"
        targetSdk = qtTargetSdkVersion.toInt()
        manifestPlaceholders["appName"] = "LodestarVPN"

        // keeps language resources for only the locales specified below
        resourceConfigurations += listOf("en", "ru", "b+zh+Hans")
    }

    sourceSets {
        getByName("main") {
            manifest.srcFile("AndroidManifest.xml")
            java.setSrcDirs(listOf("src"))
            res.setSrcDirs(listOf("res"))
            // androyddeployqt creates the folders below
            assets.setSrcDirs(listOf("assets"))
            jniLibs.setSrcDirs(listOf("libs"))
        }
    }

    // the release key comes from the environment (deploy/build_android_local.sh). Without
    // it a release APK stays unsigned: a debug key in its place would make every later
    // update refuse to install over it
    val releaseKeyPath = providers.environmentVariable("ANDROID_KEYSTORE_PATH").orNull
    signingConfigs {
        if (releaseKeyPath != null) {
            register("release") {
                storeFile = file(releaseKeyPath)
                storePassword = providers.environmentVariable("ANDROID_KEYSTORE_KEY_PASS").orNull
                keyAlias = providers.environmentVariable("ANDROID_KEYSTORE_KEY_ALIAS").orNull
                keyPassword = providers.environmentVariable("ANDROID_KEYSTORE_KEY_PASS").orNull
            }
        }
    }

    buildTypes {
        release {
            // exclude coroutine debug resource from release build
            packaging {
                resources.excludes += "DebugProbesKt.bin"
            }
            signingConfig = signingConfigs.findByName("release")
        }

        create("fdroid") {
            initWith(getByName("release"))
            signingConfig = null
            matchingFallbacks += "release"
        }
    }

    splits {
        abi {
            isEnable = true
            reset()
            include(*qtTargetAbiList.split(',').toTypedArray())
            isUniversalApk = true
        }
    }

    // fix for Qt Creator to allow deploying the application to a device
    // to enable this fix, add the line outputBaseName=android-build to local.properties
    if (outputBaseName.isNotEmpty()) {
        applicationVariants.all {
            outputs.map { it as BaseVariantOutputImpl }
                .forEach { output ->
                    if (output.outputFileName.endsWith(".apk")) {
                        output.outputFileName = "$outputBaseName-${buildType.name}.apk"
                    }
                }
        }
    }

    lint {
        disable += "InvalidFragmentVersionForActivityResult"
    }
}

dependencies {
    implementation(project(":qt"))
    implementation(project(":utils"))
    implementation(project(":protocolApi"))
    implementation(project(":wireguard"))
    implementation(project(":awg"))
    implementation(project(":xray"))
    implementation(libs.androidx.core)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.fragment)
    implementation(libs.kotlinx.coroutines)
    implementation(libs.kotlinx.serialization.protobuf)
    implementation(libs.bundles.androidx.camera)
    implementation(libs.google.mlkit)
    implementation(libs.androidx.datastore)
    implementation(libs.androidx.biometric)
}
