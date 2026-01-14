defmodule VideoMixer do
  alias VideoMixer.Error
  alias VideoMixer.FilterGraph
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
  @type input_name :: atom()

  @type t :: %__MODULE__{
          mapping: spec_mapping_t(),
          ref: reference(),
          filter_indexes: [non_neg_integer()],
          input_order: [input_name()]
        }
  defstruct [:mapping, :ref, :filter_indexes, :input_order]

  @doc """
  Initializes the mixer using a constrained layout with safe defaults.
  """
  @spec init(FilterGraph.layout(), keyword(FrameSpec.t()) | map(), FrameSpec.t(), keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  def init(layout, specs_by_role, output_frame_spec, opts \\ []) do
    with {:ok, %{graph: filter_graph, filter_indexes: filter_indexes, input_order: input_order,
                mapping: mapping}} <-
           FilterGraph.build(layout, specs_by_role, output_frame_spec, opts) do
      init_raw({filter_graph, filter_indexes}, mapping, input_order, output_frame_spec)
    end
  end

  @doc """
  Initializes the mixer with a custom filter graph.
  """
  @spec init_raw(filter_graph_t(), spec_mapping_t(), [input_name()], FrameSpec.t()) ::
          {:ok, t()} | {:error, Error.t()}
  def init_raw({filter_graph, filter_indexes}, mapping, input_order, output_frame_spec) do
    with :ok <- validate_filter_indexes(filter_indexes, mapping) do
      [widths, heights, formats] =
        filter_indexes
        |> Enum.map(&Enum.at(mapping, &1))
        |> Enum.map(fn %FrameSpec{width: w, height: h, pixel_format: f} -> [w, h, f] end)
        |> Enum.zip()
        |> Enum.map(fn x -> Tuple.to_list(x) end)

      %FrameSpec{width: out_width, height: out_height, pixel_format: out_format} =
        output_frame_spec

      case Native.init(widths, heights, formats, filter_graph, out_width, out_height, out_format) do
        {:ok, ref} ->
          {:ok,
           %__MODULE__{
             ref: ref,
             mapping: mapping,
             filter_indexes: filter_indexes,
             input_order: input_order
           }}

        {:error, reason} ->
          {:error, Error.new(:native_init, reason)}
      end
    end
  end

  @spec mix(t(), keyword(Frame.t()) | map()) :: {:ok, binary()} | {:error, Error.t()}
  def mix(%__MODULE__{ref: ref, mapping: mapping, filter_indexes: filter_indexes,
                      input_order: input_order}, frames_by_name) do
    with {:ok, frames} <- normalize_frames(frames_by_name, input_order),
         :ok <- assert_spec_compatibility(mapping, frames, 0) do
      frames
      |> Enum.with_index()
      |> Enum.filter(fn {_frame, index} -> Enum.member?(filter_indexes, index) end)
      |> Enum.map(fn {frame, _index} -> frame end)
      |> Enum.map(fn %Frame{data: x} -> x end)
      |> Native.mix(ref)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, Error.new(:native_mix, reason)}
      end
    end
  end

  defp assert_spec_compatibility([], [], _), do: :ok

  defp assert_spec_compatibility(specs, frames, _) when length(specs) != length(frames) do
    {:error,
     Error.new(:mix_input_validation, :frame_count_mismatch, %{
       expected: length(specs),
       got: length(frames)
     })}
  end

  defp assert_spec_compatibility([spec | spec_rest], [frame | frame_rest], index) do
    if FrameSpec.compatible?(spec, frame) do
      assert_spec_compatibility(spec_rest, frame_rest, index + 1)
    else
      {:error,
       Error.new(:mix_input_validation, :frame_spec_mismatch, %{
         index: index,
         frame_size: frame.size,
         spec: spec
       })}
    end
  end

  defp normalize_frames(frames_by_name, input_order) when is_map(frames_by_name) do
    keys = Map.keys(frames_by_name)
    normalize_frame_keys(frames_by_name, input_order, keys)
  end

  defp normalize_frames(frames_by_name, input_order) when is_list(frames_by_name) do
    if Keyword.keyword?(frames_by_name) do
      keys = Keyword.keys(frames_by_name)

      if length(keys) != length(Enum.uniq(keys)) do
        {:error, Error.new(:mix_input_validation, :duplicate_inputs, %{inputs: keys})}
      else
        frames_by_name
        |> Map.new()
        |> normalize_frame_keys(input_order, keys)
      end
    else
      {:error, Error.new(:mix_input_validation, :invalid_inputs)}
    end
  end

  defp normalize_frames(_frames_by_name, _input_order) do
    {:error, Error.new(:mix_input_validation, :invalid_inputs)}
  end

  defp normalize_frame_keys(frames_by_name, input_order, keys) do
    missing = input_order -- keys
    extra = keys -- input_order

    cond do
      missing != [] ->
        {:error, Error.new(:mix_input_validation, :missing_inputs, %{missing: missing})}

      extra != [] ->
        {:error, Error.new(:mix_input_validation, :unexpected_inputs, %{unexpected: extra})}

      true ->
        {:ok, Enum.map(input_order, &Map.fetch!(frames_by_name, &1))}
    end
  end

  defp validate_filter_indexes(filter_indexes, mapping) do
    max_index = length(mapping) - 1

    if Enum.all?(filter_indexes, &(&1 in 0..max_index)) do
      :ok
    else
      {:error,
       Error.new(:mix_input_validation, :invalid_filter_indexes, %{
         filter_indexes: filter_indexes,
         mapping_size: length(mapping)
       })}
    end
  end
end
