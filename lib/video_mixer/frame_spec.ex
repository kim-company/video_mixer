defmodule VideoMixer.FrameSpec do
  @type t :: %__MODULE__{
          reference: any(),
          width: pos_integer(),
          height: pos_integer(),
          pixel_format: atom(),
          accepted_frame_size: integer()
        }
  defstruct [:reference, :width, :height, :pixel_format, :accepted_frame_size]

  @doc "Returns true if `frame` is compatible with the provided specification."
  @spec compatible?(t(), VideoMixer.Frame.t()) :: boolean()
  def compatible?(nil, _frame), do: false

  def compatible?(%__MODULE__{accepted_frame_size: accepted}, %VideoMixer.Frame{size: actual}) do
    accepted == actual
  end
end
