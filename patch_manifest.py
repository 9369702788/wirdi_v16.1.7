import re
from pathlib import Path

path = Path('android/app/src/main/AndroidManifest.xml')
text = path.read_text()

# All permissions needed by Wirdi
perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.VIBRATE',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.SCHEDULE_EXACT_ALARM',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
    'android.permission.WAKE_LOCK',
]
perm_lines = '\n'.join(
    f'    <uses-permission android:name="{p}" />'
    for p in perms if p not in text
)
if perm_lines:
    text = text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n' + perm_lines,
    )

# Add usesCleartextTraffic and networkSecurityConfig to <application>
if 'usesCleartextTraffic' not in text:
    text = re.sub(
        r'<application\b',
        '<application android:usesCleartextTraffic="true" '
        'android:networkSecurityConfig="@xml/network_security_config"',
        text, count=1
    )

# Add <queries> block for URL launcher and radio streams
if '<queries>' not in text:
    queries = (
        '\n    <queries>\n'
        '        <intent>\n'
        '            <action android:name="android.intent.action.VIEW" />\n'
        '            <data android:scheme="https" />\n'
        '        </intent>\n'
        '        <intent>\n'
        '            <action android:name="android.intent.action.VIEW" />\n'
        '            <data android:scheme="http" />\n'
        '        </intent>\n'
        '        <intent>\n'
        '            <action android:name="android.intent.action.VIEW" />\n'
        '            <data android:scheme="geo" />\n'
        '        </intent>\n'
        '    </queries>\n'
    )
    text = text.replace('</manifest>', queries + '</manifest>')

path.write_text(text)
print('AndroidManifest.xml patched:')
print(text)
