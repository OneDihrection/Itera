<!-- README.md — Created by Amelia Putri Aftiana on 05/11/2026. -->
# Exercise music

User-supplied MP3 files copied unchanged into the project on 5 November 2026:

- `Floats.mp3` — Floats, Swoop; approximately 5 minutes 2 seconds.
- `Homecoming.mp3` — Homecoming, Tranquilium; approximately 3 minutes 29 seconds.

The source files were supplied from the user's local Music library. Both are bundled for offline playback and loop during an active session. This record identifies provenance, rather than assigning a new license to third-party recordings.

`ExerciseMusicPlayer` performs playback inside the existing audio services; it never configures an audio session. The selected track is a device-local preference, defaults to Floats, and includes No music. The older routine `ambientSound` field remains readable for stored-routine compatibility; the global music selection replaces its UI and playback behavior. No Music-library or network access is needed at runtime.
