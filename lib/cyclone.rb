# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "cyclone/version"

module Cyclone
  extend T::Sig

  include Kernel

  class Error < StandardError; end

  module_function

  sig { returns(T.untyped) }
  def check_test
    a = atom("hello")
    b = atom("world")
    c = slowcat([a, b])
    c.query.call(TimeSpan.new(Rational(0), Rational(2)))
  end

  # Fundamental patterns

  # Should this be a value or a function?
  sig { returns(Pattern) }
  def silence
    Pattern.new(T.let(->(_span) { [] }, Pattern::Query))
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

  sig { params(patterns: T::Array[Pattern]).returns(Pattern) }
  def slowcat(patterns)
    query = lambda do |span|
      pattern = patterns[span.start.floor % patterns.size]
      T.must(pattern).query.call(span)
    end
    pattern = Pattern.new(query)
    pattern.split_queries
  end

  class Event
    extend T::Sig

    sig { returns(TimeSpan) }
    attr_accessor :whole, :part

    sig { returns(T.untyped) }
    attr_accessor :value

    sig { params(whole: TimeSpan, part: TimeSpan, value: T.untyped).void }
    def initialize(whole, part, value)
      @whole = T.let(whole, TimeSpan)
      @part = T.let(part, TimeSpan)
      @value = value
    end

    sig { returns(String) }
    def to_s
      "Event(#{whole}, #{part}, #{value})"
    end
  end

  class Pattern
    extend T::Sig
    Query = T.type_alias { T.proc.params(span: TimeSpan).returns(T::Array[T.untyped]) }

    sig { returns(Query) }
    attr_accessor :query

    sig { params(query: Query).void }
    def initialize(query)
      @query = T.let(query, Query)
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

    sig { params(fun: T.proc.params(span: TimeSpan).returns(TimeSpan)).returns(Pattern) }
    def with_query_span(fun)
      query = lambda do |span|
        self.query.call(fun.call(span))
      end

      Pattern.new(query)
    end

    sig { params(fun: T.proc.params(arg0: Rational).returns(Rational)).returns(Pattern) }
    def with_query_time(fun)
      query = lambda do |span|
        self.query.call(span.with_time(fun))
      end

      Pattern.new(query)
    end
  end

  class TimeSpan
    extend T::Sig

    sig { returns(Rational) }
    attr_accessor :start, :stop

    sig { params(start: Rational, stop: Rational).void }
    def initialize(start, stop)
      @start = T.let(start, Rational)
      @stop = T.let(stop, Rational)
    end

    sig { returns(T::Array[TimeSpan]) }
    def span_cycles
      return [] if stop <= start
      return [self] if start.sample == stop.sample

      next_start = start.next_sample
      spans = Cyclone::TimeSpan.new(next_start, stop).span_cycles
      spans.unshift(Cyclone::TimeSpan.new(start, next_start))
    end

    sig { params(fun: T.proc.params(arg0: Rational).returns(Rational)).returns(TimeSpan) }
    def with_time(fun)
      TimeSpan.new(fun.call(start), fun.call(stop))
    end

    sig { returns(String) }
    def to_s
      "TimeSpan(#{start}, #{stop})"
    end
  end
end
