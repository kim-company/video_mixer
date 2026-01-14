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
specs = [
  primary: primary_spec,
  sidebar: sidebar_spec
]

{:ok, mixer} = VideoMixer.init(:primary_sidebar, specs, out_spec)

{:ok, output} = VideoMixer.mix(mixer, primary: primary_frame, sidebar: sidebar_frame)
```

### Supported Layouts
- `:single_fit` (roles: `primary`)
- `:hstack` (roles: `left`, `right`)
- `:vstack` (roles: `top`, `bottom`)
- `:xstack` (roles: `top_left`, `top_right`, `bottom_left`, `bottom_right`)
- `:primary_sidebar` (roles: `primary`, `sidebar`)

### Role Reference
Use these role keys for both specs and frames:
- `:single_fit` → `primary`
- `:hstack` → `left`, `right`
- `:vstack` → `top`, `bottom`
- `:xstack` → `top_left`, `top_right`, `bottom_left`, `bottom_right`
- `:primary_sidebar` → `primary`, `sidebar`

### Custom Filter Graphs
You can bypass the layout generator and provide your own filter graph string
with `init_raw/4`. This is useful for advanced ffmpeg graphs or nonstandard
layouts.

```elixir
filter_graph = {"[0:v]null[out]", [0]}
input_order = [:primary]

{:ok, mixer} = VideoMixer.init_raw(filter_graph, [primary_spec], input_order, out_spec)

{:ok, output} = VideoMixer.mix(mixer, primary: primary_frame)
```

### Layout Options
- `pixel_format` (defaults to `:I420`)

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
