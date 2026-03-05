defmodule VideoMixer.FilterGraphTest do
  use ExUnit.Case, async: true

  alias VideoMixer.FilterGraph
  alias VideoMixer.FrameSpec

  test "builds primary_sidebar_cropped graph with fixed sidebar crop and pad" do
    output = frame_spec(1920, 1080)

    specs_by_role = %{
      primary: frame_spec(1280, 720, fit_mode: :fit),
      sidebar: frame_spec(720, 1280, fit_mode: :crop)
    }

    assert {:ok, result} = FilterGraph.build(:primary_sidebar_cropped, specs_by_role, output)

    assert result.filter_indexes == [0, 1]
    assert result.input_order == [:primary, :sidebar]
    assert result.mapping == [specs_by_role.primary, specs_by_role.sidebar]

    assert result.graph ==
             "[0:v]scale=1280:1080:force_original_aspect_ratio=decrease,pad=1280:1080:-1:-1,setsar=1[l];" <>
               "[1:v]scale=-1:720,crop=640:ih,pad=640:1080:-1:-1,setsar=1[r];" <>
               "[l][r]hstack=inputs=2,scale=1920:1080[out]"
  end

  test "primary_sidebar_cropped requires both primary and sidebar roles" do
    output = frame_spec(1920, 1080)

    assert {:error, error} =
             FilterGraph.build(:primary_sidebar_cropped, %{primary: frame_spec(1280, 720)}, output)

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
