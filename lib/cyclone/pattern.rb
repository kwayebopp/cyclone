# typed: strict
# frozen_string_literal: true

require "pry"
require "sorbet-runtime"

# `Pattern` class, representing discrete and continuous `Event`s as a
# function of time.
module Cyclone
  extend T::Sig
  extend self

  # Identity function
  sig { returns(T.proc.params(value: T.untyped).returns(T.untyped)) }
  def id
    ->(value) { value }
  end
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
        span.span_cycles.flat_map(&self.query)
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to the `TimeSpan` of the query.
    sig { params(span_lambda: TimeSpan::SpanLambda).returns(Pattern) }
    def with_query_span(span_lambda)
      query = lambda do |span|
        self.query.call(span_lambda.call(span))
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to each `Event`
    # timespan.
    sig { params(span_lambda: TimeSpan::SpanLambda).returns(Pattern) }
    def with_event_span(span_lambda)
      query = lambda do |span|
        self.query.call(span).map { |event| event.with_span(span_lambda) }
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to both the `start`
    # and `stop` of the the query `TimeSpan`.
    sig { params(time_lambda: TimeSpan::TimeLambda).returns(Pattern) }
    def with_query_time(time_lambda)
      query = lambda do |span|
        self.query.call(span.with_time(time_lambda))
      end

      self.class.new(query)
    end

    # Returns a new `Pattern`, with the function applied to both the `start`
    # and `stop` of each event `TimeSpan`.
    sig { params(time_lambda: TimeSpan::TimeLambda).returns(Pattern) }
    def with_event_time(time_lambda)
      with_event_span(->(span) { span.with_time(time_lambda) })
    end

    # Returns a new `Pattern`, with the function applied to the value of
    # each `Event`. It has the alias 'fmap'
    sig { params(value_lambda: Event::ValueLambda).returns(Pattern) }
    def with_value(value_lambda)
      query = lambda do |span|
        self.query.call(span).map { |event| event.fmap(value_lambda) }
      end

      self.class.new(query)
    end
    alias fmap with_value

    # Returns a new pattern that will only return events where the start
    # of the 'whole' timespan matches the start of the 'part'
    # timespan, i.e. the events that include their 'onset'
    sig { returns(Pattern) }
    def onsets_only
      query = lambda do |span|
        self.query.call(span).select(&:has_onset?)
      end

      self.class.new(query)
    end

    sig { params(count: Integer, fun: T.proc.params(pattern: Pattern).returns(Pattern)).returns(Pattern) }
    def every(count, fun)
      self.class.slowcat([fun.call(self)] + ([self] * (count - 1)))
    end

    # Speeds up a `Pattern` by the given `factor``
    sig { params(factor: Numeric).returns(Pattern) }
    def faster(factor)
      fast_query = with_query_time(->(t) { t * factor })
      fast_query.with_event_time(->(t) { t / factor })
    end

    # Speeds up a `Pattern` by the given `Pattern` of `factors`
    sig { params(factor_pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def fast(factor_pattern)
      self.class.sequence(factor_pattern).fmap(->(factor) { faster(factor) }).outer_join
    end

    # Slow slows down a `Pattern` by the given `factor`
    sig { params(factor: Numeric).returns(Pattern) }
    def slower(factor)
      faster(1 / factor.to_f)
    end

    # Slows down a `Pattern` by the given `Pattern` of `factors`
    sig { params(factor_pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def slow(factor_pattern)
      self.class.sequence(factor_pattern).fmap(->(factor) { slower(factor) }).outer_join
    end

    # Equivalent of Tidal's `<~` operator
    sig { params(offset: Numeric).returns(Pattern) }
    def earlier(offset)
      with_query_time(->(t) { t + offset }).with_event_time(->(t) { t - offset })
    end

    sig { params(offset_pattern: T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def early(offset_pattern)
      self.class.sequence(offset_pattern).fmap(->(offset) { earlier(offset) }).outer_join
    end

    # Equivalent of Tidal's `~>` operator
    sig { params(offset: Numeric).returns(Pattern) }
    def later(offset)
      early(-offset)
    end

    sig { params(offset_pattern:  T.any(Pattern, Numeric, T::Array[Numeric])).returns(Pattern) }
    def late(offset_pattern)
      self.class.sequence(offset_pattern).fmap(->(offset) { later(offset) }).outer_join
    end

    sig { params(
      binary_pattern: T.any(Pattern, T.untyped, T::Array[T.untyped]), 
      fun: T.proc.params(pattern: Pattern).returns(Pattern)
    ).returns(Pattern) }
    def when(binary_pattern, fun)
      binary_pat = self.class.sequence(binary_pattern)
      true_pat = binary_pat.filter_values(Cyclone.id)
      false_pat = binary_pat.filter_values(->(v) { !v })
      with_pat = true_pat.fmap(->(_) { ->(y) { y } }).app_right(fun.call(self))
      without_pat = false_pat.fmap(->(_) { ->(y) { y } }).app_right(self)
      self.class.stack([with_pat, without_pat])
    end

    sig { params(
      time_pattern: RationalPattern,
      fun: T.proc.params(pattern: Pattern).returns(Pattern)
    ).returns(Pattern) }
    def off(time_pattern, fun)
      self.class.stack([self, fun.call(early(time_pattern))])
    end

    sig { 
      returns(Pattern)
    }
    def rev
      query = lambda do |span|
        cycle = span.start.sample
        next_cycle = span.start.next_sample
        reflect = lambda do |to_reflect|
          reflected = to_reflect.with_time(->(time) { cycle + (next_cycle - time) })
          TimeSpan.new(reflected.stop, reflected.start)
        end
        events = self.query.call(reflect.call(span))
        events.map { |event| event.with_span(reflect) }
      end

      self.class.new(query).split_queries
    end

    sig { override(allow_incompatible: true).params(
      func: T.proc.params(pattern: Pattern).returns(Pattern),
      by: Numeric
    ).returns(Pattern) }
    def jux(func, by: 1)
      by /= 2.0
      elem_or = lambda do |dict, key, default|
        dict.key?(key) ? dict[key] : default
      end

      left = self.fmap(->(val) { val.merge({"pan" => elem_or.call(val, "pan", 0.5) - by}) })
      right = self.fmap(->(val) { val.merge({"pan" => elem_or.call(val, "pan", 0.5) + by}) })

      self.class.stack([left, func.call(right)])
    end

    # sig { params(times: Integer).returns(Pattern) }
    # def ply(times)
    #   query = lambda do |span|
    #     self.query.call(span).map do |event| 
    #       ([event] * times).each_with_index.map { |e, i| e.with_span(->(t) { t.with_time { |t| t / times } })}
    #     end
    #   end

    #   self.class.new(query)
    # end

    sig { returns(T::Array[Event]) }
    def first_cycle
      query.call(TimeSpan.new(0, 1))
    end

    sig { params(_value: T.untyped).returns(T::Boolean) }
    def self.check_type(_value)
      true
    end

    sig { returns(Pattern) }
    def self.silence
      new(->(_) { [] })
    end

    # Returns a pattern that repeats the given value once per cycle
    sig { params(value: T.untyped).returns(Pattern) }
    def self.atom(value)
      raise ArgumentError unless check_type(value)

      query = lambda do |span|
        span.span_cycles.map do |s|
          Event.new(s.start.whole_cycle, s, value)
        end
      end

      new(query)
    end
    class << self
      alias pure atom
    end

    # Concatenation: combines a list of patterns, switching between them
    # successively, one per cycle.
    # (currently behaves slightly differently from Tidal)
    sig { params(patterns: T::Array[T.untyped]).returns(Pattern) }
    def self.slowcat(patterns)
      patterns.map! { |p| reify(p) }

      query = lambda do |span|
        pattern = patterns[span.start.floor % patterns.size]
        pattern.query.call(span)
      end

      new(query).split_queries
    end
    class << self
      alias cat slowcat
    end

    # Concatenation: as with slowcat, but squashes a cycle from each
    # pattern into one cycle
    sig { params(patterns: T::Array[T.untyped]).returns(Pattern) }
    def self.fastcat(patterns)
      slowcat(patterns).faster(patterns.size)
    end

    sig {
      params(
        other: Pattern
      ).returns(Pattern)
    }
    def slow_append(other)
      self.class.cat([self, other])
    end
    alias append slow_append

    sig {
      params(
        other: Pattern
      ).returns(Pattern)
    }
    def fast_append(other)
      self.class.fastcat([self, other])
    end

    # Pile up patterns
    sig { params(patterns: T::Array[T.untyped]).returns(Pattern) }
    def self.stack(patterns)
      patterns.map! { |p| reify(p) }
      query = lambda do |span|
        patterns.flat_map { |pattern| pattern.query.call(span) }
      end

      new(query)
    end

    # plays a modified version of a pattern 'on top of' the original pattern, resulting 
    # in the modified and original version of the patterns being played at the same time.
    sig { params(modifier: T.proc.params(pattern: Pattern).returns(Pattern), pattern: T.untyped).returns(Pattern) }
    def self.superimpose(modifier, pattern)
      stack([pattern, modifier.call(reify(pattern))])
    end

    # layer up multiple functions on one pattern
    sig { params(modifiers: T::Array[T.proc.params(pattern: Pattern).returns(Pattern)], pattern: T.untyped).returns(Pattern) }
    def self.layer(modifiers, pattern)
      stack(modifiers.map { |m| m.call(reify(pattern)) })
    end

    sig { params(thing: T.any(T::Array[T.untyped], Pattern, T.untyped)).returns(Pattern) }
    def self.sequence(thing)
      sequencer(thing).first
    end
    class << self
      alias sq sequence
    end

    sig { params(thing: T.any(T::Array[T.untyped], Pattern, T.untyped)).returns([Pattern, Integer]) }
    def self.sequencer(thing)
      case thing
      when Array
        [fastcat(thing.map { |x| sequence(x) }), thing.size]
      when Pattern
        [thing, 1]
      else
        [atom(thing), 1]
      end
    end

    sig { params(things: T::Array[T.untyped], steps: T.nilable(Integer)).returns(Pattern) }
    def self.polymeter(things, steps: nil)
      sequences = things.map { |thing| sequencer(thing) }
      return silence if sequences.empty?

      steps = T.cast(sequences[0], [Pattern, Integer])[1] if steps.nil?
      patterns = []
      sequences.each do |(pattern, sequence_length)|
        next if sequence_length.zero?

        patterns << pattern if steps == sequence_length
        patterns << pattern.faster(steps.to_r / sequence_length.to_r)
      end

      stack patterns
    end
    class << self
      alias pm polymeter
    end


    sig { params(things: T::Array[T.untyped]).returns(Pattern) }
    def self.polyrhythm(things)
      sequences = things.map { |thing| sequence(thing) }
      return silence if sequences.empty?

      stack sequences
    end
    class << self
      alias pr polyrhythm
    end

    sig { params(thing: T.untyped).returns(Pattern) }
    def self.reify(thing)
      return thing if thing.instance_of?(self)

      pure(thing)
    end

    # Assumes self is a pattern of functions, and given a function to
    # resolve wholes, applies a given pattern of values to that pattern
    # of functions.
    sig do
      params(
        whole_fun: T.proc.params(
          arg0: TimeSpan,
          arg1: TimeSpan
        ).returns(T.nilable(TimeSpan)),
        value_pattern: Pattern
      ).returns(Pattern)
    end
    def app_whole(whole_fun, value_pattern)
      func_pattern = self
      query = lambda do |span|
        func_events = func_pattern.query.call(span)
        value_events = value_pattern.query.call(span)
        apply = lambda do |func_event, value_event|
          intersection = func_event.part.maybe_intersect(value_event.part)
          unless intersection.nil?
            Event.new(
              whole_fun.call(func_event.whole, value_event.whole),
              intersection,
              func_event.value.call(value_event.value)
            )
          end
        end
        func_events.flat_map do |func_event|
          # .compact to eliminate `nil`s that may be returned from `apply`
          value_events.map { |value_event| apply.call(func_event, value_event) }.compact
        end
      end
      self.class.new(query)
    end

    #  Tidal's `<*>` operator
    sig { params(value_pattern: Pattern).returns(Pattern) }
    def app_both(value_pattern)
      whole_fun = lambda do |this, that|
        this.intersect(that) unless this.nil? || that.nil?
      end
      app_whole(whole_fun, value_pattern)
    end


    # Tidal's `<*` operator
    sig { params(value_pattern: Pattern).returns(Pattern) }
    def app_left(value_pattern)
      func_pattern = self
      query = lambda do |span|
        events = []
        func_pattern.query.call(span).each do |func_event|
          value_events = value_pattern.query.call(func_event.part)
          value_events.each do |value_event|
            new_whole = func_event.whole
            new_part = func_event.part.intersect(value_event.part)
            new_value = func_event.value.call(value_event.value)
            events << Event.new(new_whole, new_part, new_value)
          end
        end
        events
      end
      self.class.new(query)
    end

    # Tidal's `*>` operator
    sig { params(value_pattern: Pattern).returns(Pattern) }
    def app_right(value_pattern)
      func_pattern = self
      query = lambda do |span|
        events = []
        value_pattern.query.call(span).each do |value_event|
          func_events = func_pattern.query.call(value_event.part)
          func_events.each do |func_event|
            new_whole = value_event.whole
            new_part = func_event.part.intersect(value_event.part)
            new_value = func_event.value.call(value_event.value)
            events << Event.new(new_whole, new_part, new_value)
          end
        end
        events
      end
      self.class.new(query)
    end


    sig do
      params(
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def bind(fun)
      whole_fun = lambda do |this, that|
        return this.intersect(that) unless this.nil? || that.nil?
      end
      bind_whole(whole_fun, fun)
    end

    # Flattens a pattern of patterns into a pattern, where wholes are
    # the intersection of matched inner and outer events.
    sig { returns(Pattern) }
    def join
      bind(Cyclone.id)
    end

    sig do
      params(
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def inner_bind(fun)
      whole_fun = lambda do |this, that|
        return this unless this.nil? || that.nil?
      end
      bind_whole(whole_fun, fun)
    end

    # Flattens a pattern of patterns into a pattern, where wholes are
    # taken from inner events.
    sig { returns(Pattern) }
    def inner_join
      inner_bind(Cyclone.id)
    end

    sig do
      params(
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def outer_bind(fun)
      whole_fun = lambda do |this, that|
        return that unless this.nil? || that.nil?
      end
      bind_whole(whole_fun, fun)
    end

    # Flattens a pattern of patterns into a pattern, where wholes are
    #  taken from outer events.
    sig { returns(Pattern) }
    def outer_join
      outer_bind(Cyclone.id)
    end

    sig { params(other: T.untyped).returns(Pattern) }
    def +(other)
      self.fmap(->(x) { ->(y) { x + y } }).app_left(self.class.reify(other))
    end

    sig { params(other: T.untyped).returns(Pattern) }
    def -(other)
      self.fmap(->(x) { ->(y) { x - y } }).app_left(self.class.reify(other))
    end

    # Overrides the >> operator to support combining patterns of
    # hashes (AKA 'control patterns'). Produces the union of
    # two patterns of hashes, with values from right replacing
    # any with the same name from the left
    sig { params(other: Pattern).returns(Pattern) }
    def >>(other)
      self.fmap(->(this) { ->(that) { this.merge(that) } }).app_left(other)
    end

    # The union of two patterns of Hashes, with values from left
    # replacing any with the same name from the right
    sig { params(other: Pattern).returns(Pattern) }
    def <<(other)
      other.fmap(->(this) { ->(that) { this.merge(that) } }).app_left(self)
    end

    sig { returns(String) }
    def inspect
      query.call(TimeSpan.new(0, 1)).inspect
    end

    sig { params(event_test: T.proc.params(e: Event).returns(T::Boolean)).returns(Pattern) }
    def filter_events(event_test)
      query = lambda do |span|
        self.query.call(span).filter do |event|
          event_test.call(event)
        end
      end
      self.class.new(query)
    end

    sig { params(value_test: T.proc.params(v: T.untyped).returns(T::Boolean)).returns(Pattern) }
    def filter_values(value_test)
      query = lambda do |span|
        self.query.call(span).filter do |event|
          value_test.call(event.value)
        end
      end
      self.class.new(query)
    end

    private


    sig do
      params(
        choose_whole: T.proc.params(
          this_event: Event,
          that_event: Event
        ).returns(T.nilable(TimeSpan)),
        fun: T.proc.params(value: T.untyped).returns(Pattern)
      ).returns(Pattern)
    end
    def bind_whole(choose_whole, fun)
      value_pattern = self
      query = lambda do |span|
        # create a new event from the contents of two other events 
        with_whole = lambda do |this_event, that_event|
          Event.new(
            choose_whole.call(this_event.whole, that_event.whole),
            that_event.part,
            that_event.value
          )
        end
        # event has a Pattern value
        # fun does some work on the value
        # query at the event's part yields more events
        # map with_whole over each subevent and the parent event
        match = lambda do |event|
          fun.call(event.value).query.call(event.part).map do |evt|
            with_whole.call(event, evt)
          end
        end
        value_pattern.query.call(span).flat_map(&match)
      end

      self.class.new(query)
    end
  end

  ########### Pattern Classes

  class StringPattern < Pattern
    extend T::Sig

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(String)
    end
  end

  S = StringPattern
  class FloatPattern < Pattern
    extend T::Sig

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(Float) || value.instance_of?(Integer)
    end
  end

  F = FloatPattern

  class IntegerPattern < Pattern
    extend T::Sig

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(Integer) || value.respond_to?(:to_i)
    end
  end

  I = IntegerPattern

  class RationalPattern < Pattern
    extend T::Sig

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(Rational)
    end
  end

  R = RationalPattern


  class ControlPattern < Pattern
    extend T::Sig

    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.check_type(value)
      value.instance_of?(Hash)
    end
  end

  C = ControlPattern
end
