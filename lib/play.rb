#!/usr/bin/env ruby
# typed: ignore

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

Dir[File.join(__dir__, "cyclone", "*.rb")].each { |file| require file }
Dir[File.join(__dir__, "stream", "*.rb")].each { |file| require file }
require_relative "./rational"
require_relative "./proc"
require "cyclone"

include Cyclone

clock = LinkClock.new(120)
clock.start

stream = SuperDirtStream.new
clock.subscribe(stream)

puts("> wait a sec")
sleep(1)

puts("> set pattern and play for 2 seconds")
stream.pattern = (
   s(
     stack(
       [
         fast[4] < "gabba",
         fast[3] < "cp"
       ]
     )
   ).every(3, fast[2]) >>
   speed([2, 3]) >>
   room(0.5) >>
   size(0.8)
 )
sleep(2)

puts("> stop the clock for a bit")
clock.stop

puts("> now wait 3 secs")
sleep(3)

puts("> start again...")
clock.start

sleep(2)

puts("> stop the clock")
clock.stop
puts("> done")
