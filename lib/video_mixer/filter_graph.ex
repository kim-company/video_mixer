defmodule VideoMixer.FilterGraph do
  alias VideoMixer.Error
  alias VideoMixer.FrameSpec

  @type layout ::
          :single_fit
          | :hstack
          | :vstack
          | :xstack
          | :primary_sidebar

  @type role ::
          :primary
          | :sidebar
          | :left
          | :right
          | :top
          | :bottom
          | :top_left
          | :top_right
          | :bottom_left
          | :bottom_right

  @spec build(layout(), keyword(FrameSpec.t()) | map(), FrameSpec.t() | map(), keyword()) ::
          {:ok,
           %{
             graph: String.t(),
             filter_indexes: [non_neg_integer()],
             input_order: [role()],
             mapping: [FrameSpec.t()]
           }}
          | {:error, Error.t()}
  def build(layout, specs_by_role, output_spec, opts \\ []) do
    with {:ok, specs_by_role} <- normalize_specs(specs_by_role),
         {:ok, output_dims} <- output_dims(output_spec),
         {:ok, pixel_format} <- pixel_format(output_spec, opts),
         {:ok, role_order} <- role_order(layout),
         :ok <- validate_roles(specs_by_role, role_order),
         :ok <- validate_specs(specs_by_role, pixel_format) do
      mapping = Enum.map(role_order, &Map.fetch!(specs_by_role, &1))

      do_build(layout, output_dims, role_order, mapping)
    end
  end

  defp do_build(:single_fit, output_dims, role_order, mapping) do
    graph = single_fit_graph(output_dims)

    {:ok,
     %{
       graph: graph,
       filter_indexes: [0],
       input_order: role_order,
       mapping: mapping
     }}
  end

  defp do_build(:hstack, output_dims, role_order, mapping) do
    with {:ok, tile_width} <- even_div(output_dims.width, 2, :output_width) do
      graph = hstack_graph(output_dims, tile_width)

      {:ok,
       %{
         graph: graph,
         filter_indexes: [0, 1],
         input_order: role_order,
         mapping: mapping
       }}
    end
  end

  defp do_build(:vstack, output_dims, role_order, mapping) do
    with {:ok, tile_height} <- even_div(output_dims.height, 2, :output_height) do
      graph = vstack_graph(output_dims, tile_height)

      {:ok,
       %{
         graph: graph,
         filter_indexes: [0, 1],
         input_order: role_order,
         mapping: mapping
       }}
    end
  end

  defp do_build(:xstack, output_dims, role_order, mapping) do
    with {:ok, tile_width} <- even_div(output_dims.width, 2, :output_width),
         {:ok, tile_height} <- even_div(output_dims.height, 2, :output_height) do
      graph = xstack_graph(tile_width, tile_height)

      {:ok,
       %{
         graph: graph,
         filter_indexes: [0, 1, 2, 3],
         input_order: role_order,
         mapping: mapping
       }}
    end
  end

  defp do_build(:primary_sidebar, output_dims, role_order, mapping) do
    with {:ok, %{left_width: left_width, right_width: right_width}} <-
           primary_sidebar_dimensions(output_dims) do
      graph = primary_sidebar_graph(output_dims, left_width, right_width)

      {:ok,
       %{
         graph: graph,
         filter_indexes: [0, 1],
         input_order: role_order,
         mapping: mapping
       }}
    end
  end

  defp do_build(other, _output_dims, _role_order, _mapping) do
    {:error, Error.new(:filter_graph, :unsupported_layout, %{layout: other})}
  end

  defp normalize_specs(specs_by_role) when is_map(specs_by_role) do
    {:ok, specs_by_role}
  end

  defp normalize_specs(specs_by_role) when is_list(specs_by_role) do
    if Keyword.keyword?(specs_by_role) do
      keys = Keyword.keys(specs_by_role)

      if length(keys) != length(Enum.uniq(keys)) do
        {:error, Error.new(:filter_graph, :duplicate_roles, %{roles: keys})}
      else
        {:ok, Map.new(specs_by_role)}
      end
    else
      {:error, Error.new(:filter_graph, :invalid_specs)}
    end
  end

  defp normalize_specs(_specs_by_role) do
    {:error, Error.new(:filter_graph, :invalid_specs)}
  end

  defp output_dims(%FrameSpec{width: width, height: height}) do
    output_dims(%{width: width, height: height})
  end

  defp output_dims(%{width: width, height: height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    if rem(width, 2) == 0 and rem(height, 2) == 0 do
      {:ok, %{width: width, height: height}}
    else
      {:error, Error.new(:filter_graph, :invalid_output_dimensions)}
    end
  end

  defp output_dims(_output_spec) do
    {:error, Error.new(:filter_graph, :invalid_output_dimensions)}
  end

  defp pixel_format(%FrameSpec{pixel_format: pixel_format}, opts),
    do: pixel_format(%{pixel_format: pixel_format}, opts)

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

  defp validate_specs(specs_by_role, pixel_format) do
    invalid =
      Enum.find(specs_by_role, fn {_role, spec} -> not valid_spec?(spec, pixel_format) end)

    if invalid do
      {role, spec} = invalid

      {:error,
       Error.new(:filter_graph, :invalid_input_spec, %{role: role, spec: spec})}
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

  defp role_order(:single_fit), do: {:ok, [:primary]}
  defp role_order(:hstack), do: {:ok, [:left, :right]}
  defp role_order(:vstack), do: {:ok, [:top, :bottom]}
  defp role_order(:xstack), do: {:ok, [:top_left, :top_right, :bottom_left, :bottom_right]}
  defp role_order(:primary_sidebar), do: {:ok, [:primary, :sidebar]}
  defp role_order(layout), do: {:error, Error.new(:filter_graph, :unsupported_layout, %{layout: layout})}

  defp validate_roles(specs_by_role, role_order) do
    roles = Map.keys(specs_by_role)
    missing = role_order -- roles
    extra = roles -- role_order

    cond do
      missing != [] ->
        {:error, Error.new(:filter_graph, :missing_roles, %{missing: missing})}

      extra != [] ->
        {:error, Error.new(:filter_graph, :unexpected_roles, %{unexpected: extra})}

      true ->
        :ok
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
