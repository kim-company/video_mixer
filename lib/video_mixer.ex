defmodule VideoMixer do
  alias VideoMixer.Native
  alias VideoMixer.FrameSpec
  alias VideoMixer.Frame

  # Libavfilter definition in textual format, to be parsed by
  # avfilter_graph_parse().
  #
  # `[0:v]scale=w=iw/2[left],[1:v]scale=w=iw/2[right],[left][right]framepack=sbs`
  # Taken from https://libav.org/documentation/libavfilter.html#toc-framepack,
  # this filter graph example packs two different video streams into a
  # stereoscopic video, setting proper metadata on supported codecs.
  @type filter_graph_t :: {String.t(), [non_neg_integer()]}

  # Specifies the expected FrameSpec of each Frame the mixer is going to
  # receive.
  @type spec_mapping_t :: [FrameSpec.t()]

  @type t :: %__MODULE__{mapping: spec_mapping_t(), ref: reference()}
  defstruct [:mapping, :ref, :filter_indexes]

  @doc """
  Initializes the mixer. `mapping` frames must be numbered from 0 to
  length(mapping)-1. Ordering is not important.
  """
  @spec init(filter_graph_t(), spec_mapping_t(), FrameSpec.t()) :: {:ok, t()} | {:error, any}
  def init({filter_graph, filter_indexes}, mapping, output_frame_spec) do
    [widths, heights, formats] =
      mapping
      |> Enum.with_index()
      |> Enum.filter(fn {_x, index} -> Enum.member?(filter_indexes, index) end)
      |> Enum.map(fn {x, _index} -> x end)
      |> Enum.map(fn %FrameSpec{width: w, height: h, pixel_format: f} -> [w, h, f] end)
      |> Enum.zip()
      |> Enum.map(fn x -> Tuple.to_list(x) end)

    %FrameSpec{width: out_width, height: out_height, pixel_format: out_format} = output_frame_spec

    case Native.init(widths, heights, formats, filter_graph, out_width, out_height, out_format) do
      {:ok, ref} ->
        {:ok, %__MODULE__{ref: ref, mapping: mapping, filter_indexes: filter_indexes}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec mix(t(), [Frame.t()]) :: {:ok, binary()} | {:error, any()}
  def mix(%__MODULE__{ref: ref, mapping: mapping, filter_indexes: filter_indexes}, frames) do
    with :ok <- assert_spec_compatibility(mapping, frames, 0) do
      frames
      |> Enum.with_index()
      |> Enum.filter(fn {_frame, index} -> Enum.member?(filter_indexes, index) end)
      |> Enum.map(fn {frame, _index} -> frame end)
      |> Enum.map(fn %Frame{data: x} -> x end)
      |> Native.mix(ref)
    end
  end

  defp assert_spec_compatibility([], [], _), do: :ok

  defp assert_spec_compatibility(specs, frames, _) when length(specs) != length(frames) do
    {:error, "mixer needs ##{length(specs)} frames for mixing, got ##{length(frames)}"}
  end

  defp assert_spec_compatibility([spec | spec_rest], [frame | frame_rest], index) do
    if FrameSpec.compatible?(spec, frame) do
      assert_spec_compatibility(spec_rest, frame_rest, index + 1)
    else
      {:error,
       "frame with index #{index} and size #{frame.size} is incompatible with spec #{inspect(spec)}"}
    end
  end
end
