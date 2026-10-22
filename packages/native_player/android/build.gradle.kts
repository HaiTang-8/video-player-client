import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "com.mediaserver.nativeplayer"
version = "1.0"

plugins {
    id("com.android.library")
    id("kotlin-android")
}

// 预编译的 Media3 FFmpeg 音频扩展（tool/build_ffmpeg_extension.sh）；App 工程解析依赖时也要能找到它
val ffmpegRepository = file("maven").toURI()
rootProject.allprojects {
    repositories {
        maven {
            url = ffmpegRepository
            content { includeGroup("com.mediaserver.media3") }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

android {
    namespace = "com.mediaserver.nativeplayer"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    val media3 = "1.10.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-ui:$media3")
    // 系统没有 AC3 / E-AC3 / DTS / TrueHD 解码器时使用，版本必须与 Media3 一致
    implementation("com.mediaserver.media3:decoder-ffmpeg:$media3")
    // libass 渲染 ASS / SSA（MIT）；它依赖 media3-effect 1.8.0，这里对齐到当前 Media3 版本
    val ass = "0.5.1"
    implementation("io.github.peerless2012:ass-media:$ass")
    implementation("io.github.peerless2012:ass-kt:$ass")
    implementation("androidx.media3:media3-effect:$media3")
}
