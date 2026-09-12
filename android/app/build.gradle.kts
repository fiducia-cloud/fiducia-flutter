import java.io.File
import java.io.FileInputStream
import java.security.KeyStore
import java.security.MessageDigest
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

class ReleaseSigningMaterial(
    val keystore: File,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
    val certificateSha256: String,
)

fun requiredReleaseEnvironment(name: String, trim: Boolean = false): String {
    val raw = System.getenv(name)
    if (raw == null || raw.isBlank()) {
        throw GradleException("DEN-2843: Android release signing requires non-blank $name")
    }
    return if (trim) raw.trim() else raw
}

fun normalizeSha256Fingerprint(value: String): String {
    val normalized = value.filter(Char::isLetterOrDigit).uppercase()
    if (!Regex("[0-9A-F]{64}").matches(normalized)) {
        throw GradleException(
            "DEN-2843: FIDUCIA_ANDROID_CERT_SHA256 must be a 64-digit SHA-256 fingerprint",
        )
    }
    return normalized
}

fun loadReleaseKeyStore(path: File, password: CharArray): KeyStore {
    val failures = mutableListOf<String>()
    for (type in listOf("PKCS12", "JKS")) {
        try {
            val keyStore = KeyStore.getInstance(type)
            FileInputStream(path).use { stream -> keyStore.load(stream, password) }
            return keyStore
        } catch (error: Exception) {
            failures += "$type:${error.javaClass.simpleName}"
        }
    }
    throw GradleException(
        "DEN-2843: release keystore is unreadable or its password is invalid (${failures.joinToString()})",
    )
}

fun certificateSha256(keyStore: KeyStore, alias: String): String {
    if (!keyStore.containsAlias(alias) || !keyStore.isKeyEntry(alias)) {
        throw GradleException("DEN-2843: release key alias is absent or is not a private-key entry")
    }
    val certificate = keyStore.getCertificate(alias)
        ?: throw GradleException("DEN-2843: release key alias has no certificate")
    return MessageDigest.getInstance("SHA-256")
        .digest(certificate.encoded)
        .joinToString(separator = "") { byte ->
            (byte.toInt() and 0xff).toString(16).padStart(2, '0').uppercase()
        }
}

// Android Studio sync and ordinary debug builds must not require production
// credentials. Every explicitly requested release task does require them.
val releaseTaskRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true)
}

val releaseSigningMaterial = if (releaseTaskRequested) {
    val requestedPath = requiredReleaseEnvironment("FIDUCIA_ANDROID_KEYSTORE_PATH", trim = true)
    val requestedFile = File(requestedPath)
    if (!requestedFile.isAbsolute) {
        throw GradleException("DEN-2843: FIDUCIA_ANDROID_KEYSTORE_PATH must be absolute")
    }
    val keystore = try {
        requestedFile.canonicalFile
    } catch (error: Exception) {
        throw GradleException("DEN-2843: release keystore path cannot be canonicalized", error)
    }
    if (!keystore.isFile || !keystore.canRead()) {
        throw GradleException("DEN-2843: release keystore must be an existing readable file")
    }

    val debugKeystore = File(System.getProperty("user.home"), ".android/debug.keystore").canonicalFile
    if (keystore == debugKeystore || keystore.name.equals("debug.keystore", ignoreCase = true)) {
        throw GradleException("DEN-2843: the Android debug keystore is forbidden for release builds")
    }

    val storePassword = requiredReleaseEnvironment("FIDUCIA_ANDROID_KEYSTORE_PASSWORD")
    val keyAlias = requiredReleaseEnvironment("FIDUCIA_ANDROID_KEY_ALIAS", trim = true)
    val keyPassword = requiredReleaseEnvironment("FIDUCIA_ANDROID_KEY_PASSWORD")
    val expectedFingerprint = normalizeSha256Fingerprint(
        requiredReleaseEnvironment("FIDUCIA_ANDROID_CERT_SHA256", trim = true),
    )
    if (keyAlias.equals("androiddebugkey", ignoreCase = true)) {
        throw GradleException("DEN-2843: the Android debug key alias is forbidden for release builds")
    }

    val keyStore = loadReleaseKeyStore(keystore, storePassword.toCharArray())
    val actualFingerprint = certificateSha256(keyStore, keyAlias)
    if (actualFingerprint != expectedFingerprint) {
        throw GradleException(
            "DEN-2843: release certificate SHA-256 mismatch; expected $expectedFingerprint, got $actualFingerprint",
        )
    }

    ReleaseSigningMaterial(
        keystore = keystore,
        storePassword = storePassword,
        keyAlias = keyAlias,
        keyPassword = keyPassword,
        certificateSha256 = actualFingerprint,
    )
} else {
    null
}

android {
    namespace = "cloud.fiducia.fiducia_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cloud.fiducia.fiducia_flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        releaseSigningMaterial?.let { material ->
            create("release") {
                storeFile = material.keystore
                storePassword = material.storePassword
                keyAlias = material.keyAlias
                keyPassword = material.keyPassword
            }
        }
    }

    buildTypes {
        release {
            releaseSigningMaterial?.let {
                signingConfig = signingConfigs.getByName("release")
            }
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
