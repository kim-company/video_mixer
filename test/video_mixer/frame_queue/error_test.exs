defmodule VideoMixer.FrameQueue.ErrorTest do
  use ExUnit.Case, async: true

  alias VideoMixer.Error
  alias VideoMixer.Frame
  alias VideoMixer.FrameQueue, as: Queue
  alias VideoMixer.FrameSpec, as: Spec

  test "raises when pending frames would be left behind" do
    queue = Queue.new()

    input = [
      %Frame{size: 100},
      %Spec{accepted_frame_size: 200},
      %Frame{size: 200}
    ]

    error =
      assert_raise Error, fn ->
        Enum.reduce(input, queue, fn frame_or_spec, queue -> Queue.push(queue, frame_or_spec) end)
      end

    assert error.context == :frame_queue_shadowing
    assert error.reason == :pending_frames_left_behind
    assert error.details.pending_count == 1
  end

  test "raises when popping from an empty queue" do
    queue = Queue.new()

    error = assert_raise Error, fn -> Queue.pop!(queue) end

    assert error.context == :frame_queue_empty
    assert error.reason == :empty_ready_queue
  end
end
