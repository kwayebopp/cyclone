# typed: strict
# frozen_string_literal: true

require "pry"
require "sorbet-runtime"

# TimeSpan is simply an interval of time,
# represented by two Rationals (`start` and `stop`)
module Cyclone
  class TimeSpan
    extend T::Sig
    Time = T.type_alias { T.any(Integer, Float, String, Rational) }
    TimeLambda = T.type_alias { T.proc.params(rat: Rational).returns(Rational) }
    SpanLambda = T.type_alias { T.proc.params(span: T.nilable(TimeSpan)).returns(TimeSpan) }

    sig { returns(Rational) }
    attr_accessor :start, :stop

    sig { params(start: Time, stop: Time).void }
    def initialize(start, stop)
      raise ArgumentError, "#{start} cannot be converted into a Rational value" unless start.respond_to?(:to_r)
      raise ArgumentError, "#{stop} cannot be converted into a Rational value" unless stop.respond_to?(:to_r)

      @start = T.let(start.to_r, Rational)
      @stop = T.let(stop.to_r, Rational)
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

    sig { returns(Numeric) }
    def midpoint
      (start + ((stop - start) / 2))
    end

    sig { params(thing: T.any(Time, TimeSpan)).returns(TimeSpan) }
    def self.reify(thing)
      return T.cast(thing, TimeSpan) if thing.instance_of?(TimeSpan)

      if thing.respond_to?(:to_r)
        time = T.cast(thing, Time)
        return TimeSpan.new(time, time)
      end

      raise ArgumentError, "Cannot reify #{thing.class.name} as TimeSpan"
    end

    sig { params(other: T.any(Time, TimeSpan)).returns(T::Boolean) }
    def include?(other)
      other_timespan = self.class.reify(other)
      start <= other_timespan.start && stop >= other_timespan.stop
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
      "TimeSpan(#{show_fraction(start)}, #{show_fraction(stop)})"
    end
    alias_method :to_s, :inspect

    sig { params(frac: Rational).returns(String) }
    def show_fraction(frac)
      return "nil" if frac == nil
      return "0"  if frac == 0
      return "#{frac.numerator}" if frac.denominator == 1

      lookup = {Rational(1, 2) => "½",
                Rational(1, 3) => "⅓",
                Rational(2, 3) => "⅔",
                Rational(1, 4) => "¼",
                Rational(3, 4) => "¾",
                Rational(1, 5) => "⅕",
                Rational(2, 5) => "⅖",
                Rational(3, 5) => "⅗",
                Rational(4, 5) => "⅘",
                Rational(1, 6) => "⅙",
                Rational(5, 6) => "⅚",
                Rational(1, 7) => "⅐",
                Rational(1, 8) => "⅛",
                Rational(3, 8) => "⅜",
                Rational(5, 8) => "⅝",
                Rational(7, 8) => "⅞",
                Rational(1, 9) => "⅑",
                Rational(1,10) => "⅒"}

      return lookup[frac] if lookup.key?(frac)  
      "#{frac.numerator}/#{frac.denominator}"
    end
  end
end
