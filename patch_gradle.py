from pathlib import Path

kts_path = Path('android/app/build.gradle.kts')
groovy_path = Path('android/app/build.gradle')
path = kts_path if kts_path.exists() else groovy_path
text = path.read_text()
is_kts = path.suffix == '.kts'

if 'isCoreLibraryDesugaringEnabled' not in text and 'coreLibraryDesugaringEnabled' not in text:
    flag = '        isCoreLibraryDesugaringEnabled = true\n' if is_kts else '        coreLibraryDesugaringEnabled true\n'
    text = text.replace('compileOptions {\n', 'compileOptions {\n' + flag, 1)

if 'coreLibraryDesugaring(' not in text and 'coreLibraryDesugaring ' not in text:
    dep = '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n' if is_kts else "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n"
    if '\ndependencies {' in text:
        text = text.replace('\ndependencies {', '\ndependencies {\n' + dep, 1)
    else:
        text += '\ndependencies {\n' + dep + '}\n'

path.write_text(text)
print('Gradle patched')
