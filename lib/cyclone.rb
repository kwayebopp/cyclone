# typed: strict
# frozen_string_literal: true

# require "pry"
require "sorbet-runtime"
require_relative "cyclone/version"

module Cyclone
  extend T::Sig

  include Kernel

  class Error < StandardError; end

  module_function

  # Better formatting for printing Tidal Patterns
  sig { params(pattern: Pattern, query_span: TimeSpan).void }
  def pattern_pretty_printing(pattern:, query_span:)
    pattern.query.call(query_span).each do |event|
      puts event.to_s
    end
    nil
  end

  sig { returns(T.untyped) }
  def check_test
    a = atom("hello")
    b = atom("world")
    c = fastcat([a, b])

    #  Printing the pattern
    puts("\n== TEST PATTERN ==\n")
    pattern_pretty_printing(
      pattern: c,
      query_span: TimeSpan.new(0.to_r, 2.to_r)
    )

    # Printing the pattern with fast
    puts("\n== SAME BUT FASTER==\n")
    pattern_pretty_printing(
      pattern: c.fast(2),
      query_span: TimeSpan.new(0.to_r, 1.to_r)
    )

    # Apply pattern of values to a pattern of functions
    puts("\n== APPLICATIVE ==\n")
    x = fastcat([atom(->(x) { x + 1 }), atom(->(x) { x + 2 })])
    y = fastcat([atom(3), atom(4), atom(5)])
    z = x.app(y)
    pattern_pretty_printing(
      pattern: z,
      query_span: TimeSpan.new(0.to_r, 1.to_r)
    )
  end

  # Fundamental patterns

  # Should this be a value or a function?
  sig { returns(Pattern) }
  def silence
    Pattern.new(->(_span) { [] })
  end

  # Repeat discrete value once per cycle
  sig { params(value: T.untyped).returns(Pattern) }
  def atom(value)
    query = lambda do |span|
      span.span_cycles.map do |s|
        Event.new(s.start.whole_cycle, s, value)
      end
    end

    Pattern.new(query)
  end

  # Concatenation: combines a list of patterns, switching between them
  # successively, one per cycle.
  # (currently behaves slightly differently from Tidal)
  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def slowcat(patterns)
    query = lambda do |span|
      pattern = patterns[span.start.floor % patterns.size]
      T.must(pattern).query.call(span)
    end
    pattern = Pattern.new(query)
    pattern.split_queries
  end

  # Concatenation: as with slowcat, but squashes a cycle from each
  # pattern into one cycle
  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def fastcat(patterns)
    slowcat(patterns).fast(patterns.size)
  end

  # Pile up patterns
  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def stack(patterns)
    query = lambda do |span|
      patterns.map { |pattern| pattern.query.call(span) }.flatten
    end

    Pattern.new(query)
  end

  # Event class, representing a value active during the timespan
  # `part`. This might be a fragment of an event, in which case the
  # timespan will be smaller than the `whole` timespan, otherwise the
  # two timespans will be the same. The `part` must never extend outside of the
  # `whole`. If the event represents a continuously changing value
  # then the `whole` will be returned as `nil`, in which case the given
  # value will have been sampled from the point halfway between the
  # start and end of the `part` timespan.
  class Event
    extend T::Sig

    sig { returns(T.nilable(TimeSpan)) }
    attr_accessor :whole
    sig { returns(TimeSpan) }
    attr_accessor :part

    sig { returns(T.untyped) }
    attr_accessor :value

    sig { params(whole: T.nilable(TimeSpan), part: TimeSpan, value: T.untyped).void }
    def initialize(whole, part, value)
      @whole = whole
      @part = part
      @value = value
    end

    # Returns a new `Event` with the function fun applied to the event `TimeSpan`s.
    # I'd use a `SpanLambda` here, but need to allow for `nil` for the event `whole`
    sig { params(fun: T.proc.params(span: T.nilable(TimeSpan)).returns(TimeSpan)).returns(Event) }
    def with_span(fun)
      Event.new(
        whole.nil? ? nil : fun.call(whole),
        fun.call(part),
        value
      )
    end

    # Returns a new `Event` with the function `fun` applies to the event `value`.
    sig { params(fun: T.proc.params(value: T.untyped).returns(T.untyped)).returns(Event) }
    def with_value(fun)
      Event.new(whole, part, fun.call(value))
    end

    sig { returns(String) }
    def to_s
      "Event(#{whole}, #{part}, #{value})"
    end
  end

  # `Pattern` class, representing discrete and continuous `Event`s as a
  # function of time.
  class Pattern
    extend T::Sig
    Query = T.type_alias { T.proc.params(span: TimeSpan).returns(T::Array[Event]) }

    sig { returns(Query) }
    attr_accessor :query

    sig { params(query: Query).void }
    def initialize(query)
      @query = query
    end

    # Splits queries at cycle boundaries. Makes some calculations easier
    # to express, as everything then happens within a cycle.
    sig { returns(Pattern) }
    def split_queries
      query = lambda do |span|
        span.span_cycles.map { |s| self.query.call(s) }.flatten
      end

      Pattern.new(query)
    end

    # Returns a new `Pattern`, with the function applied to the `TimeSpan` of the query.
    sig { params(span_lambda: TimeSpan::SpanLambda).returns(Pattern) }
    def with_query_span(span_lambda)
      query = lambda do |span|
        self.query.call(span_lambda.call(span))
      end

      Pattern.new(query)
    end

    # Returns a new `Pattern`, with the function applied to both the `start`
    # and `stop` of the the query `TimeSpan`.
    sig { params(rational_lambda: TimeSpan::TimeLambda).returns(Pattern) }
    def with_query_time(rational_lambda)
      query = lambda do |span|
        self.query.call(span.with_time(rational_lambda))
      end

      Pattern.new(query)
    end

    # Returns a new `Pattern`, with the function applied to each `Event`
    # timespan.
    sig { params(fun: T.proc.params(span: T.nilable(TimeSpan)).returns(TimeSpan)).returns(Pattern) }
    def with_event_span(fun)
      query = lambda do |span|
        self.query.call(span).map { |event| event.with_span(fun) }
      end

      Pattern.new(query)
    end

    # Returns a new `Pattern`, with the function applied to both the `start`
    # and `stop` of each event `TimeSpan`.
    sig { params(rational_lambda: TimeSpan::TimeLambda).returns(Pattern) }
    def with_event_time(rational_lambda)
      with_event_span(->(span) { span.with_time(rational_lambda) })
    end

    # Returns a new `Pattern`, with the function applied to the value of
    # each `Event`. It has the alias 'fmap'
    sig { params(fun: T.proc.params(value: T.untyped).returns(T.untyped)).returns(Pattern) }
    def with_value(fun)
      query = lambda do |span|
        self.query.call(span).map { |event| event.with_value(fun) }
      end

      Pattern.new(query)
    end

    alias_method :fmap, :with_value

    # Speeds up a `Pattern` by the given `factor``
    sig { params(factor: Numeric).returns(Pattern) }
    def fast(factor)
      fast_query = with_query_time(->(t) { t * factor })
      fast_query.with_event_time(->(t) { t / factor })
    end

    # Slow slows down a `Pattern` by the given `factor`
    sig { params(factor: Numeric).returns(Pattern) }
    def slow(factor)
      fast(1 / factor.to_f)
    end

    # Equivalent of Tidal's `<~` operator
    sig { params(offset: Numeric).returns(Pattern) }
    def early(offset)
      with_query_time(->(t) { t + offset }).with_event_time(->(t) { t - offset })
    end

    # Equivalent of Tidal's `~>` operator
    sig { params(offset: Numeric).returns(Pattern) }
    def late(offset)
      early(-offset)
    end

    sig { returns(T::Array[Event]) }
    def first_cycle
      query.call(TimeSpan.new(0.to_r, 1.to_r))
    end

    # Tidal's `<*>` operator
    sig { params(pattern_of_vals: Pattern).returns(Pattern) }
    def app(pattern_of_vals)
      whole_fun = lambda do |this, that|
        return this.intersect(that) unless this.nil? || that.nil?
      end
      _app(whole_fun, pattern_of_vals)
    end

    # Tidal's `<*` operator
    sig { params(pattern_of_vals: Pattern).returns(Pattern) }
    def appl(pattern_of_vals)
      whole_fun = lambda do |this, that|
        return this unless this.nil? || that.nil?
      end
      _app(whole_fun, pattern_of_vals)
    end

    # Tidal's `*>` operator
    sig { params(pattern_of_vals: Pattern).returns(Pattern) }
    def appr(pattern_of_vals)
      whole_fun = lambda do |this, that|
        return that unless this.nil? || that.nil?
      end
      _app(whole_fun, pattern_of_vals)
    end

    private

    # Assumes self is a pattern of functions, and given a function to
    # resolve wholes, applies a given pattern of values to that pattern
    # of functions.
    sig { params(whole_fun: T.proc.params(arg0: TimeSpan, arg1: TimeSpan).returns(T.nilable(TimeSpan)), pattern_of_vals: Pattern).returns(Pattern) }
    def _app(whole_fun, pattern_of_vals)
      pattern_of_funs = self
      query = lambda do |span|
        event_funs = pattern_of_funs.query.call(span)
        event_vals = pattern_of_vals.query.call(span)
        apply = lambda do |event_fun, event_val|
          intersection = event_fun.part.maybe_intersect(event_val.part)
          unless intersection.nil?
            Event.new(
              whole_fun.call(event_fun.whole, event_val.whole),
              intersection,
              event_fun.value.call(event_val.value)
            )
          end
        end
        events = event_funs.map do |event_fun|
          # .compact to eliminate `nil`s that may be returned from `apply`
          event_vals.map { |event_val| apply.call(event_fun, event_val) }.compact
        end
        events.flatten
      end
      Pattern.new(query)
    end
  end

  # TimeSpan is simply an interval of time,
  # represented by two Rationals (`start` and `stop`)
  class TimeSpan
    extend T::Sig
    TimeLambda = T.type_alias { T.proc.params(rat: Rational).returns(Rational) }
    SpanLambda = T.type_alias { T.proc.params(span: TimeSpan).returns(TimeSpan) }

    sig { returns(Rational) }
    attr_accessor :start, :stop

    sig { params(start: Rational, stop: Rational).void }
    def initialize(start, stop)
      @start = start
      @stop = stop
    end

    # Splits a timespan at cycle boundaries
    sig { returns(T::Array[TimeSpan]) }
    def span_cycles
      return [] if stop <= start
      return [self] if start.sample == stop.sample

      next_start = start.next_sample
      spans = TimeSpan.new(next_start, stop).span_cycles
      spans.unshift(TimeSpan.new(start, next_start))
    end

    # Applies given function to both the begin and end time value of the timespan
    sig { params(fun: TimeLambda).returns(TimeSpan) }
    def with_time(fun)
      TimeSpan.new(fun.call(start), fun.call(stop))
    end

    # Intersection of two TimeSpans
    sig { params(other: TimeSpan).returns(TimeSpan) }
    def intersect(other)
      TimeSpan.new([start, other.start].max, [stop, other.stop].min)
    end

    # Like intersect but returns `nil` if they don't intersect
    sig { params(other: TimeSpan).returns(T.nilable(TimeSpan)) }
    def maybe_intersect(other)
      intersection = intersect(other)
      intersection.stop > intersection.start ? intersection : nil
    end

    sig { returns(String) }
    def to_s
      "TimeSpan(#{start}, #{stop})"
    end
  end
end
