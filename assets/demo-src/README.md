# Demo GIF source

`scene.html` is a deterministic animation: `window.render(t)` draws the frame at time `t` seconds.
`capture.mjs` screenshots it frame by frame; ffmpeg turns the frames into the GIF.

```bash
npm i playwright-core
CHROMIUM_PATH=/path/to/chromium node capture.mjs frames 12 frames
ffmpeg -framerate 12 -i frames/f%04d.png -vf "palettegen=max_colors=128:stats_mode=full:reserve_transparent=0" palette.png
ffmpeg -framerate 12 -i frames/f%04d.png -i palette.png \
  -lavfi "[0:v][1:v]paletteuse=dither=none:diff_mode=rectangle" -loop 0 ../demo.gif
```

Preview single moments with `node capture.mjs stills 13.5,18.4,29.5 stills`.
