defmodule VideoMixer.FilterGraph do
  alias VideoMixer.Error
  alias VideoMixer.FrameSpec

  @type layout ::
          :single_fit
          | :hstack
          | :vstack
          | :xstack
          | :primary_sidebar

  @type input_def :: %{name: atom(), spec: FrameSpec.t()}

  @spec build(layout(), [input_def()], FrameSpec.t() | map(), keyword()) ::
          {:ok,
           %{
             graph: String.t(),
             filter_indexes: [non_neg_integer()],
             input_order: [atom()],
             mapping: [FrameSpec.t()]
           }}
          | {:error, Error.t()}
  def build(layout, inputs, output_spec, opts \\ []) do
    with :ok <- validate_inputs(inputs),
         {:ok, output_dims} <- output_dims(output_spec),
         {:ok, pixel_format} <- pixel_format(output_spec, opts),
         :ok <- validate_specs(inputs, pixel_format) do
      input_order = Enum.map(inputs, & &1.name)
      mapping = Enum.map(inputs, & &1.spec)

      do_build(layout, inputs, output_dims, pixel_format, opts, input_order, mapping)
    end
  end

  defp do_build(:single_fit, inputs, output_dims, _pixel_format, _opts, input_order, mapping) do
    with :ok <- require_input_count(inputs, 1, :single_fit) do
      graph = single_fit_graph(output_dims)

      {:ok,
       %{
         graph: graph,
         filter_indexes: [0],
         input_order: input_order,
         mapping: mapping
       }}
    end
  end

  defp do_build(:hstack, inputs, output_dims, _pixel_format, _opts, input_order, mapping) do
    with :ok <- require_input_count(inputs, 2, :hstack),
         {:ok, tile_width} <- even_div(output_dims.width, 2, :output_width) do
      graph = hstack_graph(output_dims, tile_width)

      {:ok,
       %{
         graph: graph,
         filter_indexes: [0, 1],
         input_order: input_order,
         mapping: mapping
       }}
    end
  end

  defp do_build(:vstack, inputs, output_dims, _pixel_format, _opts, input_order, mapping) do
    with :ok <- require_input_count(inputs, 2, :vstack),
         {:ok, tile_height} <- even_div(output_dims.height, 2, :output_height) do
      graph = vstack_graph(output_dims, tile_height)

      {:ok,
       %{
         graph: graph,
         filter_indexes: [0, 1],
         input_order: input_order,
         mapping: mapping
       }}
    end
  end

  defp do_build(:xstack, inputs, output_dims, _pixel_format, _opts, input_order, mapping) do
    with :ok <- require_input_count(inputs, 4, :xstack),
         {:ok, tile_width} <- even_div(output_dims.width, 2, :output_width),
         {:ok, tile_height} <- even_div(output_dims.height, 2, :output_height) do
      graph = xstack_graph(tile_width, tile_height)

      {:ok,
       %{
         graph: graph,
         filter_indexes: [0, 1, 2, 3],
         input_order: input_order,
         mapping: mapping
       }}
    end
  end

  defp do_build(:primary_sidebar, _inputs, output_dims, _pixel_format, opts, input_order, mapping) do
    sidebar_name = Keyword.get(opts, :sidebar)
    primary_name = Keyword.get(opts, :primary, hd(input_order))

    sidebar_idx = if sidebar_name, do: Enum.find_index(input_order, &(&1 == sidebar_name))
    primary_idx = Enum.find_index(input_order, &(&1 == primary_name))

    cond do
      is_nil(primary_idx) ->
        {:error, Error.new(:filter_graph, :unknown_primary_input, %{primary: primary_name})}

      is_nil(sidebar_name) or is_nil(sidebar_idx) ->
        graph = single_fit_graph(output_dims)

        {:ok,
         %{
           graph: graph,
           filter_indexes: [primary_idx],
           input_order: input_order,
           mapping: mapping
         }}

      sidebar_idx == primary_idx ->
        {:error, Error.new(:filter_graph, :sidebar_equals_primary, %{sidebar: sidebar_name})}

      true ->
        with {:ok, %{left_width: left_width, right_width: right_width}} <-
               primary_sidebar_dimensions(output_dims) do
          graph = primary_sidebar_graph(output_dims, left_width, right_width)

          {:ok,
           %{
             graph: graph,
             filter_indexes: [primary_idx, sidebar_idx],
             input_order: input_order,
             mapping: mapping
           }}
        end
    end
  end

  defp do_build(other, _inputs, _output_dims, _pixel_format, _opts, _input_order, _mapping) do
    {:error, Error.new(:filter_graph, :unsupported_layout, %{layout: other})}
  end

  defp validate_inputs(inputs) when is_list(inputs) and inputs != [] do
    names = Enum.map(inputs, & &1.name)

    cond do
      Enum.any?(inputs, &(!is_atom(&1.name))) ->
        {:error, Error.new(:filter_graph, :invalid_input_name)}

      Enum.any?(names, &is_nil/1) ->
        {:error, Error.new(:filter_graph, :invalid_input_name)}

      length(Enum.uniq(names)) != length(names) ->
        {:error, Error.new(:filter_graph, :duplicate_input_names, %{names: names})}

      true ->
        :ok
    end
  end

  defp validate_inputs(_inputs) do
    {:error, Error.new(:filter_graph, :invalid_inputs)}
  end

  defp output_dims(%FrameSpec{width: width, height: height}) do
    output_dims(%{width: width, height: height})
  end

  defp output_dims(%{width: width, height: height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    {:ok, %{width: width, height: height}}
  end

  defp output_dims(_output_spec) do
    {:error, Error.new(:filter_graph, :invalid_output_dimensions)}
  end

  defp pixel_format(%FrameSpec{pixel_format: pixel_format}, opts) do
    pixel_format(%{pixel_format: pixel_format}, opts)
  end

  defp pixel_format(%{pixel_format: pixel_format}, opts) when is_atom(pixel_format) do
    requested = Keyword.get(opts, :pixel_format, :I420)

    if requested == pixel_format do
      {:ok, requested}
    else
      {:error,
       Error.new(:filter_graph, :pixel_format_mismatch, %{
         expected: requested,
         got: pixel_format
       })}
    end
  end

  defp pixel_format(_output_spec, opts) do
    {:ok, Keyword.get(opts, :pixel_format, :I420)}
  end

  defp validate_specs(inputs, pixel_format) do
    invalid =
      Enum.find(inputs, fn %{spec: spec} ->
        not valid_spec?(spec, pixel_format)
      end)

    if invalid do
      {:error,
       Error.new(:filter_graph, :invalid_input_spec, %{input: invalid.name, spec: invalid.spec})}
    else
      :ok
    end
  end

  defp valid_spec?(%FrameSpec{} = spec, pixel_format) do
    is_integer(spec.width) and spec.width > 0 and is_integer(spec.height) and spec.height > 0 and
      is_atom(spec.pixel_format) and spec.pixel_format == pixel_format and
      is_integer(spec.accepted_frame_size) and spec.accepted_frame_size > 0
  end

  defp valid_spec?(_spec, _pixel_format), do: false

  defp require_input_count(inputs, count, layout) do
    if length(inputs) == count do
      :ok
    else
      {:error,
       Error.new(:filter_graph, :invalid_input_count, %{
         layout: layout,
         expected: count,
         got: length(inputs)
       })}
    end
  end

  defp even_div(value, divisor, label) do
    if rem(value, divisor) == 0 do
      {:ok, div(value, divisor)}
    else
      {:error,
       Error.new(:filter_graph, :invalid_output_dimension, %{
         dimension: label,
         value: value
       })}
    end
  end

  defp single_fit_graph(%{width: ow, height: oh}) do
    "[0:v]scale=#{ow}:#{oh}:force_original_aspect_ratio=decrease," <>
      "pad=#{ow}:#{oh}:-1:-1,setsar=1[out]"
  end

  defp hstack_graph(%{height: oh}, tile_width) do
    [
      "[0:v]scale=#{tile_width}:#{oh}:force_original_aspect_ratio=decrease," <>
        "pad=#{tile_width}:#{oh}:-1:-1,setsar=1[l]",
      "[1:v]scale=#{tile_width}:#{oh}:force_original_aspect_ratio=decrease," <>
        "pad=#{tile_width}:#{oh}:-1:-1,setsar=1[r]",
      "[l][r]hstack=inputs=2[out]"
    ]
    |> Enum.join(";")
  end

  defp vstack_graph(%{width: ow}, tile_height) do
    [
      "[0:v]scale=#{ow}:#{tile_height}:force_original_aspect_ratio=decrease," <>
        "pad=#{ow}:#{tile_height}:-1:-1,setsar=1[t]",
      "[1:v]scale=#{ow}:#{tile_height}:force_original_aspect_ratio=decrease," <>
        "pad=#{ow}:#{tile_height}:-1:-1,setsar=1[b]",
      "[t][b]vstack=inputs=2[out]"
    ]
    |> Enum.join(";")
  end

  defp xstack_graph(tile_width, tile_height) do
    [
      "[0:v]scale=#{tile_width}:#{tile_height}:force_original_aspect_ratio=decrease," <>
        "pad=#{tile_width}:#{tile_height}:-1:-1,setsar=1[a]",
      "[1:v]scale=#{tile_width}:#{tile_height}:force_original_aspect_ratio=decrease," <>
        "pad=#{tile_width}:#{tile_height}:-1:-1,setsar=1[b]",
      "[2:v]scale=#{tile_width}:#{tile_height}:force_original_aspect_ratio=decrease," <>
        "pad=#{tile_width}:#{tile_height}:-1:-1,setsar=1[c]",
      "[3:v]scale=#{tile_width}:#{tile_height}:force_original_aspect_ratio=decrease," <>
        "pad=#{tile_width}:#{tile_height}:-1:-1,setsar=1[d]",
      "[a][b][c][d]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0[out]"
    ]
    |> Enum.join(";")
  end

  defp primary_sidebar_graph(%{height: oh}, left_width, right_width) do
    [
      "[0:v]scale=#{left_width}:#{oh}:force_original_aspect_ratio=decrease," <>
        "pad=#{left_width}:#{oh}:-1:-1,setsar=1[l]",
      "[1:v]scale=#{right_width}:#{oh}:force_original_aspect_ratio=decrease," <>
        "pad=#{right_width}:#{oh}:-1:-1,setsar=1[r]",
      "[l][r]hstack=inputs=2[out]"
    ]
    |> Enum.join(";")
  end

  defp primary_sidebar_dimensions(%{width: ow, height: oh}) do
    cond do
      rem(ow, 2) != 0 or rem(oh, 2) != 0 ->
        {:error,
         Error.new(:filter_graph, :invalid_output_dimension, %{
           dimension: :output_size,
           value: {ow, oh}
         })}

      true ->
        left_width = div(ow * 2, 3)
        right_width = ow - left_width

        if rem(left_width, 2) == 0 and rem(right_width, 2) == 0 do
          {:ok, %{left_width: left_width, right_width: right_width}}
        else
          {:error,
           Error.new(:filter_graph, :invalid_output_dimension, %{
           dimension: :primary_sidebar_widths,
           value: {left_width, right_width}
         })}
        end
    end
  end
end
