defmodule VideoMixer.NativeIntegrationTest do
  use ExUnit.Case, async: true

  alias VideoMixer.Error
  alias VideoMixer.Frame
  alias VideoMixer.FrameSpec

  defp i420_frame(width, height, y_value, u_value, v_value) do
    y_plane = :binary.copy(<<y_value>>, width * height)
    uv_size = div(width, 2) * div(height, 2)
    u_plane = :binary.copy(<<u_value>>, uv_size)
    v_plane = :binary.copy(<<v_value>>, uv_size)

    %Frame{
      data: IO.iodata_to_binary([y_plane, u_plane, v_plane]),
      size: width * height + 2 * uv_size,
      pts: 0
    }
  end

  defp split_i420(binary, width, height) do
    y_size = width * height
    uv_size = div(width, 2) * div(height, 2)

    <<y_plane::binary-size(y_size), u_plane::binary-size(uv_size), v_plane::binary-size(uv_size)>> =
      binary

    {y_plane, u_plane, v_plane}
  end

  defp rgba_frame(width, height, r, g, b, a) do
    pixel = <<r, g, b, a>>
    data = :binary.copy(pixel, width * height)

    %Frame{
      data: data,
      size: width * height * 4,
      pts: 0
    }
  end

  test "initializes and mixes a single input" do
    spec = %FrameSpec{
      width: 2,
      height: 2,
      pixel_format: :I420,
      accepted_frame_size: 6
    }

    specs = [primary: spec]

    assert {:ok, mixer} = VideoMixer.init(:single_fit, specs, spec)

    frame = %Frame{data: <<0::48>>, size: 6, pts: 0}

    assert {:ok, output} = VideoMixer.mix(mixer, primary: frame)
    assert byte_size(output) == 6
  end

  test "mixes two inputs side-by-side with hstack" do
    left_spec = %FrameSpec{
      width: 2,
      height: 2,
      pixel_format: :I420,
      accepted_frame_size: 6
    }

    right_spec = %FrameSpec{left_spec | accepted_frame_size: 6}
    out_spec = %FrameSpec{left_spec | width: 4, accepted_frame_size: 12}

    specs = [left: left_spec, right: right_spec]

    assert {:ok, mixer} = VideoMixer.init(:hstack, specs, out_spec)

    left = i420_frame(2, 2, 10, 90, 100)
    right = i420_frame(2, 2, 200, 160, 170)

    assert {:ok, output} = VideoMixer.mix(mixer, left: left, right: right)
    assert byte_size(output) == 12

    {y_plane, u_plane, v_plane} = split_i420(output, 4, 2)

    assert y_plane == <<10, 10, 200, 200, 10, 10, 200, 200>>
    assert u_plane == <<90, 160>>
    assert v_plane == <<100, 170>>
  end

  test "mixes two inputs vertically with vstack" do
    top_spec = %FrameSpec{
      width: 2,
      height: 2,
      pixel_format: :I420,
      accepted_frame_size: 6
    }

    bottom_spec = %FrameSpec{top_spec | accepted_frame_size: 6}
    out_spec = %FrameSpec{top_spec | height: 4, accepted_frame_size: 12}

    specs = [top: top_spec, bottom: bottom_spec]

    assert {:ok, mixer} = VideoMixer.init(:vstack, specs, out_spec)

    top = i420_frame(2, 2, 10, 20, 30)
    bottom = i420_frame(2, 2, 200, 210, 220)

    assert {:ok, output} = VideoMixer.mix(mixer, top: top, bottom: bottom)
    assert byte_size(output) == 12

    {y_plane, u_plane, v_plane} = split_i420(output, 2, 4)

    assert y_plane == <<10, 10, 10, 10, 200, 200, 200, 200>>
    assert u_plane == <<20, 210>>
    assert v_plane == <<30, 220>>
  end

  test "mixes four inputs in a 2x2 grid with xstack" do
    base_spec = %FrameSpec{
      width: 2,
      height: 2,
      pixel_format: :I420,
      accepted_frame_size: 6
    }

    out_spec = %FrameSpec{base_spec | width: 4, height: 4, accepted_frame_size: 24}

    specs = [
      top_left: base_spec,
      top_right: base_spec,
      bottom_left: base_spec,
      bottom_right: base_spec
    ]

    assert {:ok, mixer} = VideoMixer.init(:xstack, specs, out_spec)

    a = i420_frame(2, 2, 10, 20, 30)
    b = i420_frame(2, 2, 60, 70, 80)
    c = i420_frame(2, 2, 120, 130, 140)
    d = i420_frame(2, 2, 200, 210, 220)

    assert {:ok, output} =
             VideoMixer.mix(mixer, top_left: a, top_right: b, bottom_left: c, bottom_right: d)

    assert byte_size(output) == 24

    {y_plane, u_plane, v_plane} = split_i420(output, 4, 4)

    assert y_plane == <<
             10,
             10,
             60,
             60,
             10,
             10,
             60,
             60,
             120,
             120,
             200,
             200,
             120,
             120,
             200,
             200
           >>

    assert u_plane == <<20, 70, 130, 210>>
    assert v_plane == <<30, 80, 140, 220>>
  end

  test "mixes two inputs with primary_sidebar layout" do
    left_spec = %FrameSpec{
      width: 4,
      height: 2,
      pixel_format: :I420,
      accepted_frame_size: 12
    }

    right_spec = %FrameSpec{
      width: 2,
      height: 2,
      pixel_format: :I420,
      accepted_frame_size: 6
    }

    out_spec = %FrameSpec{left_spec | width: 6, height: 2, accepted_frame_size: 18}

    specs = [primary: left_spec, sidebar: right_spec]

    assert {:ok, mixer} = VideoMixer.init(:primary_sidebar, specs, out_spec)

    left = i420_frame(4, 2, 10, 20, 30)
    right = i420_frame(2, 2, 200, 210, 220)

    assert {:ok, output} = VideoMixer.mix(mixer, primary: left, sidebar: right)
    assert byte_size(output) == 18

    {y_plane, u_plane, v_plane} = split_i420(output, 6, 2)

    assert y_plane == <<10, 10, 10, 10, 200, 200, 10, 10, 10, 10, 200, 200>>
    assert u_plane == <<20, 20, 210>>
    assert v_plane == <<30, 30, 220>>
  end

  test "wraps native init errors" do
    spec = %FrameSpec{
      width: 2,
      height: 2,
      pixel_format: :I420,
      accepted_frame_size: 6
    }

    bad_out_spec = %FrameSpec{spec | pixel_format: :BAD}

    filter_graph = {"[0:v]null[out]", [0]}
    input_order = [:main]

    assert {:error, %Error{context: :native_init, reason: :unsupported_out_pixel_format}} =
             VideoMixer.init_raw(filter_graph, [spec], input_order, bad_out_spec)
  end

  test "wraps native mix errors" do
    spec = %FrameSpec{
      width: 2,
      height: 2,
      pixel_format: :I420,
      accepted_frame_size: 1
    }

    out_spec = %FrameSpec{spec | accepted_frame_size: 6}

    specs = [primary: spec]

    assert {:ok, mixer} = VideoMixer.init(:single_fit, specs, out_spec)

    frame = %Frame{data: <<0>>, size: 1, pts: 0}

    assert {:error, %Error{context: :native_mix, reason: :input_payload_size_mismatch}} =
             VideoMixer.mix(mixer, primary: frame)
  end

  test "mixes with a custom filter graph via init_raw" do
    filter_graph = {"[0:v]null[out]", [0]}
    input_order = [:primary]

    spec = %FrameSpec{
      width: 2,
      height: 2,
      pixel_format: :I420,
      accepted_frame_size: 6
    }

    assert {:ok, mixer} = VideoMixer.init_raw(filter_graph, [spec], input_order, spec)

    frame = i420_frame(2, 2, 10, 20, 30)

    assert {:ok, output} = VideoMixer.mix(mixer, primary: frame)
    assert byte_size(output) == 6
  end

  test "init_raw accepts RGBA input pixel format" do
    rgba_spec = %FrameSpec{width: 2, height: 2, pixel_format: :RGBA, accepted_frame_size: 16}
    out_spec = %FrameSpec{width: 2, height: 2, pixel_format: :I420, accepted_frame_size: 6}

    filter_graph = {"[0:v]format=yuv420p[out]", [0]}

    assert {:ok, _mixer} =
             VideoMixer.init_raw(filter_graph, [rgba_spec], [:overlay], out_spec)
  end

  test "init_raw accepts BGRA input pixel format" do
    bgra_spec = %FrameSpec{width: 2, height: 2, pixel_format: :BGRA, accepted_frame_size: 16}
    out_spec = %FrameSpec{width: 2, height: 2, pixel_format: :I420, accepted_frame_size: 6}

    filter_graph = {"[0:v]format=yuv420p[out]", [0]}

    assert {:ok, _mixer} =
             VideoMixer.init_raw(filter_graph, [bgra_spec], [:overlay], out_spec)
  end

  test "init_raw composes an opaque RGBA overlay onto an I420 base via overlay filter" do
    base_spec = %FrameSpec{width: 4, height: 4, pixel_format: :I420, accepted_frame_size: 24}
    overlay_spec = %FrameSpec{width: 4, height: 4, pixel_format: :RGBA, accepted_frame_size: 64}
    out_spec = base_spec

    filter_graph =
      {"[1:v]format=yuva420p[ovl];[0:v][ovl]overlay=x=0:y=0:format=yuv420[out]", [0, 1]}

    assert {:ok, mixer} =
             VideoMixer.init_raw(
               filter_graph,
               [base_spec, overlay_spec],
               [:base, :overlay],
               out_spec
             )

    base = i420_frame(4, 4, 0, 128, 128)
    overlay = rgba_frame(4, 4, 255, 0, 0, 255)

    assert {:ok, output} = VideoMixer.mix(mixer, base: base, overlay: overlay)
    assert byte_size(output) == 24

    {y_plane, _u, _v} = split_i420(output, 4, 4)

    # RGB(255,0,0) → Y ≈ 76 (full-range BT.601) or 81 (limited). Either way far from base Y=0.
    Enum.each(:binary.bin_to_list(y_plane), fn y ->
      assert y in 60..100, "expected Y to reflect opaque red overlay, got #{y}"
    end)
  end

  test "RGBA alpha controls overlay blend strength" do
    base_spec = %FrameSpec{width: 4, height: 4, pixel_format: :I420, accepted_frame_size: 24}
    overlay_spec = %FrameSpec{width: 4, height: 4, pixel_format: :RGBA, accepted_frame_size: 64}
    out_spec = base_spec

    filter_graph =
      {"[1:v]format=yuva420p[ovl];[0:v][ovl]overlay=x=0:y=0:format=yuv420[out]", [0, 1]}

    assert {:ok, mixer} =
             VideoMixer.init_raw(
               filter_graph,
               [base_spec, overlay_spec],
               [:base, :overlay],
               out_spec
             )

    base = i420_frame(4, 4, 0, 128, 128)
    overlay = rgba_frame(4, 4, 255, 0, 0, 128)

    assert {:ok, output} = VideoMixer.mix(mixer, base: base, overlay: overlay)

    {y_plane, _u, _v} = split_i420(output, 4, 4)

    # 50% alpha blend of black (Y=0) and red (Y≈76) should land near 38.
    Enum.each(:binary.bin_to_list(y_plane), fn y ->
      assert y in 20..60, "expected blended Y between black and red, got #{y}"
    end)
  end
end
