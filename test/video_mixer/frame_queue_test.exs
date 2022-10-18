defmodule VideoMixer.FrameQueueTest do
  use ExUnit.Case

  alias VideoMixer.Frame
  alias VideoMixer.FrameQueue, as: Queue
  alias VideoMixer.FrameSpec, as: Spec

  test "handles frame-spec pairs delivered out-of-order" do
    queue = Queue.new(0)
    input = [
      %Frame{size: 100},
      %Spec{accepted_frame_size: 100},
      %Frame{size: 100},
      %Spec{accepted_frame_size: 200},
      %Frame{size: 100}, # After spec change.
      %Frame{size: 200},
      %Spec{accepted_frame_size: 300},
      %Frame{size: 300},
      %Frame{size: 200}, # Should not happen but still we prefer to handle it.
      %Frame{size: 300},
      %Frame{size: 400}, # Buffer received before associated specs.
      %Spec{accepted_frame_size: 400},
    ]
    want = [
      %{frame: %Frame{size: 100}, spec: %Spec{accepted_frame_size: 100}, spec_changed?: true},
      %{frame: %Frame{size: 100}, spec: %Spec{accepted_frame_size: 100}, spec_changed?: false},
      %{frame: %Frame{size: 100}, spec: %Spec{accepted_frame_size: 100}, spec_changed?: false},
      %{frame: %Frame{size: 200}, spec: %Spec{accepted_frame_size: 200}, spec_changed?: true},
      %{frame: %Frame{size: 300}, spec: %Spec{accepted_frame_size: 300}, spec_changed?: true},
      %{frame: %Frame{size: 200}, spec: %Spec{accepted_frame_size: 200}, spec_changed?: true},
      %{frame: %Frame{size: 300}, spec: %Spec{accepted_frame_size: 300}, spec_changed?: true},
      %{frame: %Frame{size: 400}, spec: %Spec{accepted_frame_size: 400}, spec_changed?: true},
    ]

    # Load the queue
    queue = Enum.reduce(input, queue, fn frame_or_spec, queue -> Queue.push(queue, frame_or_spec) end)

    # Assert its contents
    Enum.reduce(want, queue, fn want, queue ->
      {have, queue} = Queue.pop!(queue)

      assert have.frame == want.frame
      assert have.spec == want.spec
      assert have.spec_changed? == want.spec_changed?

      queue
    end)
  end

  test "does not allow pending frames to be left behind" do
    queue = Queue.new(0)
    input = [
      %Frame{size: 100},
      %Spec{accepted_frame_size: 200},
      # This frame cannot become ready, the 100 one is still pending and will
      # never exit that state.
      %Frame{size: 200},
    ]

    assert_raise(VideoMixer.FrameQueue.ShadowingError, fn ->
      Enum.reduce(input, queue, fn frame_or_spec, queue -> Queue.push(queue, frame_or_spec) end)
    end)
  end
end
