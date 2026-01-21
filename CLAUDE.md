# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VideoMixer is an Elixir library that mixes multiple video inputs into a single output using ffmpeg filters. It provides a safe, layout-driven filter graph generator with named inputs to avoid index mistakes.

## Development Commands

### Building and Compiling
```bash
mix deps.get           # Install dependencies
mix compile            # Compile the project (includes native C compilation via Unifex/Bundlex)
```

### Testing
```bash
mix test                                  # Run all tests
mix test test/path/to/test.exs            # Run a specific test file
mix test test/path/to/test.exs:42         # Run a specific test at line 42
```

### Documentation
```bash
mix docs               # Generate documentation
```

### Code Formatting
```bash
mix format             # Format all Elixir code
```

## Architecture

### Core Components

1. **VideoMixer** (lib/video_mixer.ex)
   - Main public API with `init/4` and `mix/2` functions
   - `init/4`: Creates a mixer using predefined layouts (`:single_fit`, `:hstack`, `:vstack`, `:xstack`, `:primary_sidebar`)
   - `init_raw/4`: Creates a mixer with a custom ffmpeg filter graph string
   - `mix/2`: Mixes frames by role names (keyword list), validates specs, calls native code
   - Handles input validation and frame ordering before native processing

2. **VideoMixer.FilterGraph** (lib/video_mixer/filter_graph.ex)
   - Generates ffmpeg filter graph strings for supported layouts
   - Validates roles, dimensions, and pixel formats
   - Each layout has specific role requirements (e.g., `:hstack` uses `:left` and `:right`)
   - Enforces even dimension requirements for I420 pixel format

3. **VideoMixer.FrameQueue** (lib/video_mixer/frame_queue.ex)
   - Manages frame ordering and spec transitions
   - Handles dynamic spec changes during streaming
   - Maintains `ready` queue for compatible frames and `pending` queue for frames awaiting specs
   - Detects spec changes and prevents frame shadowing issues

4. **Native Integration** (c_src/video_mixer/mix.c)
   - C-based NIF using Unifex for FFmpeg integration
   - `init`: Initializes FFmpeg filter graph with input/output specs
   - `mix`: Processes frames through the filter graph
   - Uses libavfilter for actual video processing

### Data Structures

- **Frame** (lib/video_mixer/frame.ex): Contains raw video data, presentation timestamp (pts), and size
- **FrameSpec** (lib/video_mixer/frame_spec.ex): Defines expected frame characteristics (width, height, pixel_format, accepted_frame_size)
- **Error** (lib/video_mixer/error.ex): Structured error handling with context, reason, and details

### Layout System

Each layout has defined roles that must be provided:
- `:single_fit` → `primary`
- `:hstack` → `left`, `right`
- `:vstack` → `top`, `bottom`
- `:xstack` → `top_left`, `top_right`, `bottom_left`, `bottom_right`
- `:primary_sidebar` → `primary` (2/3 width), `sidebar` (1/3 width)

Filter graphs are generated as strings and parsed by libavfilter. Each graph includes scaling, padding, and composition operations.

## Build System

- Uses **Bundlex** for native compilation (bundlex.exs)
- Uses **Unifex** for NIF interface generation (c_src/video_mixer/mix.spec.exs)
- Requires FFmpeg >= 6.0 with libavfilter and pkg-config at compile time
- Native code is compiled with `:unifex` and `:bundlex` compilers in mix.exs

## Testing Patterns

Tests are organized by feature:
- `mixer_validation_test.exs`: Input validation before native calls
- `native_integration_test.exs`: End-to-end FFmpeg integration tests
- `frame_queue/*_test.exs`: Frame queue state, ordering, and error handling

Tests use `ExUnit.Case` with `async: true` where possible.
