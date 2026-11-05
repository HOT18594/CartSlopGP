# Cart Slop GP — music drop folder

Drop **MP3 files** in this folder using these exact names:

| File | Used for | Length |
|---|---|---|
| `menu_loop.mp3` | Main menu, play/lobby/vehicle screens | 60–120 s |
| `sandbox_loop.mp3` | Driving in the sandbox | 60–120 s |

That's all the game needs right now. `MusicPlayer` crossfades between them and
silently skips any file that is missing, so you can test with just one.

> Godot imports audio when the project is opened/scanned. After adding MP3s,
> open the project once in the Godot editor (or just export again) so the files
> are packed into the build.

---

## Suno prompts

Write the **Style** box as comma-separated ingredients — strongest first:
`genre, mood, instrumentation, vocal style, tempo, production`. Put
`[Instrumental]` in the **Lyrics** box (and nothing else). Keep the style under
~200 characters; Suno truncates long prompts. Change one tag at a time if a
take misses.

### 1. menu_loop.mp3

**Style**

```
playful funk-pop, cheerful grocery-store chaos, slap bass, muted guitar stabs, brushed drums, toy piano, instrumental, 108 BPM, warm analog mix
```

**Lyrics**

```
[Instrumental]
```

**Exclude styles**

```
vocals, spoken word, heavy distortion, fade out
```

### 2. sandbox_loop.mp3

**Style**

```
energetic surf garage-rock, frantic and fun, fuzz guitar, driving bass, live drums, hand claps, instrumental, 138 BPM, punchy retro mix
```

**Lyrics**

```
[Instrumental]
```

**Exclude styles**

```
vocals, spoken word, ballad, slow tempo, fade out
```

### Optional alternates

If you want a calmer bed for free-roam, generate a third track and add it to
`MusicPlayer` later (or name it `sandbox_chill.mp3` and ask me to wire it):

```
laid-back lo-fi hip-hop, sunny and carefree, dusty drums, mellow electric piano, soft bass, instrumental, 84 BPM, tape saturation
```

```
upbeat arcade racing chiptune, nostalgic and bouncy, square lead, punchy noise drums, arpeggio bass, instrumental, 150 BPM, crisp 16-bit mix
```

---

## Loop tips

- Ask for **"seamless loop, no fade out"**; Suno still often adds an ending, so
  trim the tail in any audio editor (Audacity is free) and let it wrap.
- Avoid vocals — they make a loop obvious and the game has no lyrics.
- Normalise tracks to roughly the same loudness so the crossfade doesn't jump.
- 44.1 kHz stereo MP3 at 128–192 kbps is plenty; bigger files only bloat the build.
