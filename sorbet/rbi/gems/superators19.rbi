# This file is autogenerated. Do not edit it by hand. Regenerate it with:
#   srb rbi gems

# typed: strict
#
# If you would like to make changes to this file, great! Please create the gem's shim here:
#
#   https://github.com/sorbet/sorbet-typed/new/master?filename=lib/superators19/all/superators19.rbi
#
# superators19-0.9.3

module Superators
end
module SuperatorMixin
  def defined_superators; end
  def real_operator_from_superator(sup); end
  def respond_to_superator?(sup); end
  def superator(operator, &block); end
  def superator_alias_for(name); end
  def superator_decode(str); end
  def superator_definition_name_for(sup); end
  def superator_encode(str); end
  def superator_send(sup, operand); end
  def superator_valid?(operator); end
end
module SuperatorFlag
end
class Object < BasicObject
  def +@; end
  def -@; end
  def superator_queue; end
  def ~; end
end