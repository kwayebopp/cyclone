# typed: ignore
# frozen_string_literal: true

require "pry"
require "pycall"

class SuperDirtStream
  attr_accessor :latency, :pattern

  def initialize(port = 57120, latency = 0.2)
    @liblo = PyCall.import_module "liblo"

    @pattern = nil
    @latency = latency

    @port = port
    @address = @liblo.Address.new(port)

    @is_playing = true
  end

  def play
    @is_playing = true
  end

  def stop
    @is_playing = false
  end

  def playing?
    @is_playing
  end

  def notify_tick(cycle, session_state, cps, bpc, mill, now)
    return unless playing? && pattern

    cycle_from, cycle_to = cycle
    events = pattern.onsets_only.query.call(TimeSpan.new(cycle_from, cycle_to))
    puts("\n#{events.map(&:value)}") unless events.empty?

    events.each do |event|
      cycle_on = event.whole.start
      cycle_off = event.whole.stop

      puts([cycle_on, cycle_off, bpc].join(" "))
      puts([cycle_on * bpc, cycle_off * bpc].join(" "))

      link_on = session_state.timeAtBeat((cycle_on * bpc).to_f, 0)
      link_off = session_state.timeAtBeat((cycle_off * bpc).to_f, 0)
      delta_secs = (link_off - link_on).fdiv(mill)

      link_secs = now.fdiv(mill)
      liblo_diff = @liblo.time - link_secs
      ticks = link_on.fdiv(mill) + liblo_diff + latency

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
      bundle = @liblo.Bundle.new(ticks, @liblo.Message.new("/dirt/play", *msg))
      PyCall.getattr(@liblo, :send).call(@address, bundle)
    end
  end
end
