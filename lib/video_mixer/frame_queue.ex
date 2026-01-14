defmodule VideoMixer.FrameQueue do
  alias VideoMixer.Error

  alias VideoMixer.Frame
  alias VideoMixer.FrameSpec

  defstruct [
    :current_spec,
    :known_specs,
    :stream_finished?,
    :spec_changed?,
    :received_first_frame?,
    :ready,
    :pending,
    :needs_spec_before_next_frame
  ]

  def new do
    %__MODULE__{
      spec_changed?: false,
      stream_finished?: false,
      received_first_frame?: false,
      # Erroneous condition in which a frame risks to be left behind in the
      # pending queue.
      needs_spec_before_next_frame: false,
      known_specs: [],
      current_spec: nil,
      ready: :queue.new(),
      # Frames that do not find a matching Spec are stored in this buffer.
      pending: :queue.new()
    }
  end

  def push(state, spec = %FrameSpec{}) do
    state = %{state | known_specs: [spec | state.known_specs]}

    if :queue.is_empty(state.pending) do
      state
    else
      frames = :queue.to_list(state.pending)

      pending_accepted? =
        frames
        |> Enum.map(fn x -> FrameSpec.compatible?(spec, x) end)
        |> Enum.all?()

      if pending_accepted? do
        state = %{
          state
          | spec_changed?: true,
            current_spec: spec,
            pending: :queue.new(),
            needs_spec_before_next_frame: false
        }

        Enum.reduce(frames, state, fn x, state -> push_compatible(state, spec, x) end)
      else
        %{state | needs_spec_before_next_frame: true}
      end
    end
  end

  def push(state = %__MODULE__{needs_spec_before_next_frame: true}, frame = %Frame{}) do
    raise Error,
          context: :frame_queue_shadowing,
          reason: :pending_frames_left_behind,
          details: %{
            pending_count: :queue.len(state.pending),
            frame: frame
          }
  end

  def push(state = %__MODULE__{current_spec: spec}, frame = %Frame{}) do
    if FrameSpec.compatible?(spec, frame) do
      # Common Case
      push_compatible(state, spec, frame)
    else
      spec = Enum.find(state.known_specs, &FrameSpec.compatible?(&1, frame))

      if spec != nil do
        state = %{state | spec_changed?: true, current_spec: spec}
        push_compatible(state, spec, frame)
      else
        %{state | pending: :queue.in(frame, state.pending)}
      end
    end
  end

  def push(state = %__MODULE__{}, :end_of_stream) do
    %{state | stream_finished?: true}
  end

  def ready?(%__MODULE__{received_first_frame?: value}), do: value

  def any?(%__MODULE__{ready: ready}), do: :queue.len(ready) > 0

  @doc "Returns the size of the ready queue"
  def size(%__MODULE__{ready: ready}), do: :queue.len(ready)

  def closed?(%__MODULE__{stream_finished?: stream_finished?, ready: ready}) do
    :queue.is_empty(ready) and stream_finished?
  end

  def pop!(state = %__MODULE__{ready: ready}) do
    case :queue.out(ready) do
      {{:value, value}, ready} ->
        {value, %{state | ready: ready}}

      {:empty, _ready} ->
        raise Error,
              context: :frame_queue_empty,
              reason: :empty_ready_queue
    end
  end

  defp push_compatible(state, spec, frame) do
    ready =
      :queue.in(%{
        frame: frame,
        spec: spec,
        spec_changed?: state.spec_changed?
      }, state.ready)

    %{state | ready: ready, spec_changed?: false, received_first_frame?: true}
  end
end
