# VideoMixer

Mixes multiple video inputs to a single output using ffmpeg filters.

## Installation
```elixir
def deps do
  [
    {:video_mixer, "~> 1.0.0"}
  ]
end
```

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
