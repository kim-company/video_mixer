# VideoMixer

Mixes multiple video inputs to a single output using ffmpeg filters.

## Installation
```elixir
def deps do
  [
    {:video_mixer, "~> 2.0.0"}
  ]
end
```

## Usage
VideoMixer provides a safe, layout-driven filter graph generator. Inputs are named
to avoid index mistakes, and `mix/2` expects a keyword list keyed by those names.

```elixir
inputs = [
  %{name: :primary, spec: primary_spec},
  %{name: :sidebar, spec: sidebar_spec}
]

{:ok, mixer} = VideoMixer.init(:primary_sidebar, inputs, out_spec, sidebar: :sidebar)

{:ok, output} = VideoMixer.mix(mixer, primary: primary_frame, sidebar: sidebar_frame)
```

### Supported Layouts
- `:single_fit` (single input scaled/padded to output)
- `:hstack` (2 inputs side-by-side)
- `:vstack` (2 inputs top/bottom)
- `:xstack` (4 inputs in a 2x2 grid)
- `:primary_sidebar` (primary input dominant, secondary input on the side)

### Layout Options
- `pixel_format` (defaults to `:I420`)
- `sidebar` (required for `:primary_sidebar`; name of the secondary input)
- `primary` (optional; defaults to the first input name)

`primary_sidebar` is intended for layouts where the main content should dominate
and a secondary feed (like a sign interpreter or thumbnail speaker) sits on the side.

### Layout Constraints
- Output dimensions must be even for all layouts (required by `:I420`).
- `:hstack` requires output width divisible by 2.
- `:vstack` requires output height divisible by 2.
- `:xstack` requires output width and height divisible by 2.
- `:primary_sidebar` splits output width into 2/3 + 1/3, both even; widths that
  can’t be evenly split will be rejected.

## Compile-time Dependencies
- ffmpeg >= 6.0 (libraries: `libavfilter`, `libavutil`)
- `pkg-config` (used to locate ffmpeg headers and libs)

### macOS (Homebrew)
```bash
brew install ffmpeg pkg-config
```

### Debian/Ubuntu
```bash
sudo apt-get update
sudo apt-get install -y ffmpeg pkg-config
```

## Copyright and License
Copyright 2022, [KIM Keep In Mind GmbH](https://www.keepinmind.info/)
Licensed under the [Apache License, Version 2.0](LICENSE)
