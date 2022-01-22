# typed: ignore
# frozen_string_literal: true

require "pry"
require "pycall"
require_relative "./cyclone/pattern"
require_relative "./cyclone/event"
require_relative "./cyclone/time_span"
require_relative "./rational"
require_relative "./cyclone"

include Cyclone

def import(lib)
  PyCall.import_module lib
end

os = import "os"
time = import "time"
liblo = import "liblo"

superdirt = liblo.Address.new(57120)

lib_dir = os.path.normpath(os.path.dirname(os.path.realpath(__FILE__)))
$LOAD_PATH.unshift(lib_dir)

link = import "link"

l = link.Link.new(135)

l.enabled = true
l.startStopSyncEnabled = true

start = l.clock.micros
MILL = 1_000_000
start_beat = l.captureSessionState.beatAtTime(start, 4)
puts("start: " + start_beat.to_s)
ticks = 0
frame = 1.fdiv(20) * MILL
bpc = 4
latency = 0.2

pattern = (
  S.sound(
    stack(
      [
        pure("gabba").fast(pure(4)),
        pure("cp").fast(pure(3))
      ]
    )
  ) >>
  F.speed(sequence([pure(2), pure(3)])) >>
  F.room(pure(0.5)) >>
  F.size(pure(0.8))
)

puts(l.captureSessionState)

begin
  while true
    ticks += 1

    logical_now = (start + (ticks * frame)).floor
    logical_next = (start + ((ticks + 1) * frame)).floor

    # wait until start of next frame
    wait = (logical_now - l.clock.micros).fdiv(MILL)
    time.sleep(wait) if wait.positive?

    session_state = l.captureSessionState
    cps = (session_state.tempo.fdiv(bpc)).fdiv(60)
    cycle_from = session_state.beatAtTime(logical_now, 0).fdiv(bpc)
    cycle_to = session_state.beatAtTime(logical_next, 0).fdiv(bpc)
    events = pattern.onsets_only.query.call(TimeSpan.new(cycle_from, cycle_to))

    puts("\n#{events.map(&:value)}") unless events.empty?

    events.each do |event|
      cycle_on = event.whole.start
      cycle_off = event.whole.stop

      link_on = session_state.timeAtBeat((cycle_on * bpc).to_f, 0)
      link_off = session_state.timeAtBeat((cycle_off * bpc).to_f, 0)
      delta_secs = (link_off - link_on).fdiv(MILL)

      link_secs = l.clock.micros.fdiv(MILL)
      liblo_diff = liblo.time - link_secs
      ts = link_on.fdiv(MILL) + liblo_diff + latency

      value = event.value
      value["cps"] = cps.to_f
      value["cycle"] = cycle_on.to_f
      value["delta"] = delta_secs.to_f

      msg = []
      value.to_a.each do |k, v|
        msg << k
        msg << v
      end

      puts(msg.join(" "))
      bundle = liblo.Bundle.new(ts, liblo.Message.new("/dirt/play", *msg))
      PyCall.getattr(liblo, :send).call(superdirt, bundle)
    end

    $stdout.puts format(
      "cps %<cps>.2f | playing %<playing>s | cycle %<cycle>.2f\r",
      cps: cps, playing: session_state.isPlaying, cycle: cycle_from
    )
  end
rescue Interrupt => _e
  nil
else
  nil
end
