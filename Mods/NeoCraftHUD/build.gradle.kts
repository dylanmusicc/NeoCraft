plugins {
    java
    id("net.fabricmc.fabric-loom") version "1.18-SNAPSHOT"
}

version = "1.0.0"
group = "com.neocraft"

base {
    archivesName = "neocraft-hud"
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(25)
    }
    withSourcesJar()
}

repositories {
    maven("https://maven.fabricmc.net/")
    mavenCentral()
}

dependencies {
    minecraft("com.mojang:minecraft:26.3")
    implementation("net.fabricmc:fabric-loader:0.19.5")
    implementation("net.fabricmc.fabric-api:fabric-api:0.161.0+26.3")
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(25)
}

tasks.jar {
    from("LICENSE") {
        rename { "${it}_${project.base.archivesName.get()}" }
    }
}
