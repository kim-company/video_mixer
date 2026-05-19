defmodule VideoMixer.FilterGraphTest do
  use ExUnit.Case, async: true

  alias VideoMixer.FilterGraph
  alias VideoMixer.FrameSpec

  test "builds primary_sidebar_cropped graph for 1920x1080 output" do
    output = frame_spec(1920, 1080)

    specs_by_role = %{
      primary: frame_spec(1280, 720, fit_mode: :fit),
      sidebar: frame_spec(720, 1280, fit_mode: :crop)
    }

    assert {:ok, result} = FilterGraph.build(:primary_sidebar_cropped, specs_by_role, output)

    assert result.filter_indexes == [0, 1]
    assert result.input_order == [:primary, :sidebar]
    assert result.mapping == [specs_by_role.primary, specs_by_role.sidebar]

    # content_h = round_even(1080 * 1280 / 1920) = 720
    assert result.graph ==
             "[0:v]scale=1280:720,pad=1280:1080:-1:-1,setsar=1[l];" <>
               "[1:v]scale=-1:720,crop=640:ih,pad=640:1080:-1:-1,setsar=1[r];" <>
               "[l][r]hstack=inputs=2,scale=1920:1080[out]"
  end

  test "primary_sidebar_cropped uses identical content_h for both halves" do
    # For any output resolution, both the primary scale height and the sidebar
    # scale height must be the same value so that pad centering is identical.
    for {ow, oh} <- [{1920, 1080}, {1280, 720}, {854, 480}, {640, 360}, {1366, 768}] do
      output = frame_spec(ow, oh)

      specs_by_role = %{
        primary: frame_spec(ow, oh, fit_mode: :fit),
        sidebar: frame_spec(480, 640, fit_mode: :crop)
      }

      assert {:ok, result} = FilterGraph.build(:primary_sidebar_cropped, specs_by_role, output),
             "failed to build for #{ow}x#{oh}"

      [primary_part, sidebar_part | _] = String.split(result.graph, ";")

      # Extract content height from primary: scale=<w>:<h>,pad
      [_, _, primary_h_str] = Regex.run(~r/scale=(\d+):(\d+),pad/, primary_part)
      primary_h = String.to_integer(primary_h_str)

      # Extract content height from sidebar: scale=-1:<h>
      [_, sidebar_h_str] = Regex.run(~r/scale=-1:(\d+)/, sidebar_part)
      sidebar_h = String.to_integer(sidebar_h_str)

      assert primary_h == sidebar_h,
             "#{ow}x#{oh}: primary content_h=#{primary_h} != sidebar content_h=#{sidebar_h}"

      # Both must use centered pad (y=-1)
      assert primary_part =~ ~r/pad=\d+:\d+:-1:-1/
      assert sidebar_part =~ ~r/pad=\d+:\d+:-1:-1/
    end
  end

  test "primary_sidebar_cropped aligns correctly for 1280x720 (previously 2px off)" do
    # This was the concrete bug: div(720,3)*2 = 480 but ffmpeg would produce
    # a 478px primary, causing a 1px vertical offset. Now both use 480.
    output = frame_spec(1280, 720)

    specs_by_role = %{
      primary: frame_spec(1280, 720, fit_mode: :fit),
      sidebar: frame_spec(640, 480, fit_mode: :crop)
    }

    assert {:ok, result} = FilterGraph.build(:primary_sidebar_cropped, specs_by_role, output)

    # primary_w = round_even(div(1280,3)*2) = 852
    # content_h = round_even(div(720*852, 1280)) = round_even(479) = 480
    # sidebar_w = round_even(1280 - 852) = 428
    assert result.graph ==
             "[0:v]scale=852:480,pad=852:720:-1:-1,setsar=1[l];" <>
               "[1:v]scale=-1:480,crop=428:ih,pad=428:720:-1:-1,setsar=1[r];" <>
               "[l][r]hstack=inputs=2,scale=1280:720[out]"
  end

  test "primary_sidebar_cropped requires both primary and sidebar roles" do
    output = frame_spec(1920, 1080)

    assert {:error, error} =
             FilterGraph.build(
               :primary_sidebar_cropped,
               %{primary: frame_spec(1280, 720)},
               output
             )

    assert error.context == :filter_graph
    assert error.reason == :missing_roles
  end

  defp frame_spec(width, height, opts \\ []) do
    %FrameSpec{
      width: width,
      height: height,
      pixel_format: :I420,
      accepted_frame_size: max(width * height, 1),
      fit_mode: Keyword.get(opts, :fit_mode, :crop)
    }
  end
end
