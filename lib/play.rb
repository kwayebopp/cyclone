#!/usr/bin/env ruby
# typed: ignore

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

Dir[File.join(__dir__, "cyclone", "*.rb")].each { |file| require file }
Dir[File.join(__dir__, "stream", "*.rb")].each { |file| require file }
require_relative "./rational"
require "cyclone"

include Cyclone

clock = LinkClock.new(120)
clock.play

stream = SuperDirtStream.new
clock.subscribe(stream)

puts("wait a sec")
sleep(0.5)

puts("set pattern")
stream.pattern = (
   s(
     stack(
       [
         pure("gabba").fast(pure(4)),
         pure("cp").fast(pure(3))
       ]
     )
   ) >>
   speed(sequence([pure(2), pure(3)])) >>
   room(pure(0.5)) >>
   size(pure(0.8))
 )
sleep(3)

puts("unset pattern")
stream.pattern = nil
sleep(2)

clock.stop
puts("done")
