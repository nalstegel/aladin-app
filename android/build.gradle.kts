allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// firebase_auth se brez tega ne prevede: njegova koda uporablja anotacije
// iz checker-frameworka (prek Firebase SDK), ki pa niso na prevajalni poti,
// zato Kotlin javi "Type annotation class ... is inaccessible".
subprojects {
    plugins.withId("com.android.library") {
        dependencies {
            add("compileOnly", "org.checkerframework:checker-qual:3.48.3")
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
