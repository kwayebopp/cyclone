# typed: true
# frozen_string_literal: true

require "pry"
require "sorbet-runtime"

module Cyclone
  # TimeSpan is simply an interval of time,
  # represented by two Rationals (`start` and `stop`)
  class TimeSpan
    extend T::Sig
    Time = T.type_alias { T.any(Integer, Float, Rational) }
    TimeLambda = T.type_alias { T.proc.params(rat: Rational).returns(Rational) }
    SpanLambda = T.type_alias { T.proc.params(span: TimeSpan).returns(TimeSpan) }

    sig { returns(Rational) }
    attr_accessor :start, :stop

    sig { params(start: Time, stop: Time).void }
    def initialize(start, stop)
      @start = start.to_r
      @stop = stop.to_r
    end

    # Splits a timespan at cycle boundaries
    sig { returns(T::Array[TimeSpan]) }
    def span_cycles
      # no cycles in the `TimeSpan`
      return [] if stop <= start

      # `TimeSpan` is all within one cycle
      return [self] if start.sample == stop.sample

      next_start = start.next_sample
      spans = self.class.new(next_start, stop).span_cycles
      spans.unshift(self.class.new(start, next_start))
    end

    # Applies given function to both the begin and end time value of the timespan
    sig { params(fun: TimeLambda).returns(TimeSpan) }
    def with_time(fun)
      self.class.new(fun.call(start), fun.call(stop))
    end

    # Intersection of two TimeSpans
    sig { params(other: TimeSpan).returns(TimeSpan) }
    def intersect(other)
      self.class.new([start, other.start].max, [stop, other.stop].min)
    end

    # Like intersect but returns `nil` if they don't intersect
    sig { params(other: TimeSpan).returns(T.nilable(TimeSpan)) }
    def maybe_intersect(other)
      intersection = intersect(other)
      intersection.stop > intersection.start ? intersection : nil
    end

    sig { params(thing: T.any(Time, TimeSpan)).returns(TimeSpan) }
    def self.reify(thing)
      return T.cast(thing, TimeSpan) if thing.instance_of?(TimeSpan)

      is_time = thing.instance_of?(Integer) || thing.instance_of?(Float) || thing.instance_of?(Rational)
      if is_time
        time = T.cast(thing, Time)
        return TimeSpan.new(time, time)
      end

      raise ArgumentError, "Cannot reify #{thing.class} as TimeSpan"
    end

    sig { params(other: T.untyped).returns(TimeSpan) }
    def +(other)
      other_timespan = self.class.reify(other)
      self.class.new(start + other_timespan.start, stop + other_timespan.stop)
    end

    sig { params(other: T.untyped).returns(TimeSpan) }
    def -(other)
      other_timespan = self.class.reify(other)
      self.class.new(start - other_timespan.start, stop - other_timespan.stop)
    end

    sig { returns(String) }
    def inspect
      "TimeSpan(#{start}, #{stop})"
    end
    alias_method :to_s, :inspect
  end
end
