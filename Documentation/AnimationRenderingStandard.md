<!-- AnimationRenderingStandard.md — Created by dimaswisodewo on 2026-11-09. -->

# 3D animation rendering standard

Use this standard for new rendered 3D exercise demonstrations. Follow the animation behavior, side handling, playback, and asset ownership described in [SYSTEM_DESIGN.md](../SYSTEM_DESIGN.md) and [the animation resources README](../Itera/Resources/Animations/README.md). Existing 640 × 640 hand videos are legacy assets; this standard does not require changing them.

## Render and export

- Render a square **768 × 768** image at **24 frames per second**. Keep the subject fully inside the frame throughout the motion, with consistent camera framing and lighting.
- Export the final animation as a silent **`.mp4`** using H.264 video and `yuv420p` pixel format for app playback. Use a background that works with the intended app surface. MP4/H.264 does not preserve transparency; retain transparent source frames or the Blender scene separately when future compositing is needed.
- Keep the complete motion cycle and its start/end timing consistent with the app's playback mode. Check the first, middle, and last frames for clipping, outline quality, color, and motion continuity.
- Name the bundled output for the exercise and its role in lowercase snake case, such as `arm_raise_demonstration.mp4` or `elbow_bend_demonstration.mp4`. Place it in `Itera/Resources/Animations/`. Do not use a temporary color, version, or tool name as the app asset name. Record the source scene and any replacement in that folder's README.

## FFmpeg

Use FFmpeg to encode the rendered frames. Check whether it is installed with `command -v ffmpeg`. If it is missing, install it with `brew install ffmpeg` before exporting. If Homebrew is unavailable, report the missing tool instead of claiming an MP4 was produced.

For numbered RGBA PNG frames, composite over the chosen app background before encoding. Replace the example paths and background color for the exercise:

```sh
ffmpeg -framerate 24 -start_number 0 -i 'work/frames/frame_%04d.png' \
  -f lavfi -i 'color=c=0xF5F5F5:s=768x768:r=24' \
  -filter_complex '[1:v][0:v]overlay=shortest=1:format=auto,format=yuv420p[v]' \
  -map '[v]' -c:v libx264 -crf 18 -movflags +faststart \
  'Itera/Resources/Animations/arm_raise_demonstration.mp4'
```

Verify the exported file is 768 × 768, 24 FPS, playable through its complete cycle, and named for the intended exercise. Check its appearance on the actual light or dark app surface and verify playback on the baseline M1 iPad; a Simulator build alone does not establish visual or device acceptance.
