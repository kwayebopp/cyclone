# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "cyclone/version"

module Cyclone
  extend T::Sig

  include Kernel

  class Error < StandardError; end

  module_function

  # flatten list of lists
  sig { params(cycles: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
  def concat(cycles)
    cycles.flatten
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
      span.span_cycles.map { |s| [s.start.whole_cycle, s, value] }
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

  class TimeSpan
    extend T::Sig

    sig { returns(Rational) }
    attr_accessor :start, :stop

    sig { params(start: Rational, stop: Rational).void }
    def initialize(start, stop)
      @start = start
      @stop = stop
    end

    sig { returns(T::Array[TimeSpan]) }
    def span_cycles
      return [] if stop <= start
      return [self] if start.sample == stop.sample

      next_start = start.next_sample
      spans = Cyclone::TimeSpan.new(next_start, stop).span_cycles
      spans.unshift(Cyclone::TimeSpan.new(start, next_start))
    end

    sig { returns(String) }
    def to_s
      "TimeSpan(#{start}, #{stop})"
    end
  end

  class Pattern
    extend T::Sig
    Query = T.type_alias { T.proc.params(span: TimeSpan).returns(T.untyped) }

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
        span.span_cycles.map { |s| self.query.call(s) }
      end

      Pattern.new(T.let(query, Query))
    end
  end
end
