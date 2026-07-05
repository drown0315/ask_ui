# scrcpy Server 4.0

This directory stores the project-controlled official scrcpy server artifact
used by the Ask UI bridge for Android Live App Surface sessions.

- File: `scrcpy-server-v4.0`
- Version: official Genymobile scrcpy server 4.0
- SHA256: `84924bd564a1eb6089c872c7521f968058977f91f5ff02514a8c74aff3210f3a`

The bridge pushes this file to the Android device at runtime as:

```text
/data/local/tmp/scrcpy-server.jar
```

Do not replace this artifact silently. When upgrading scrcpy, add a new versioned
directory, update the bridge default path, and record the new checksum here.
