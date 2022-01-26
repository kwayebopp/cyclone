# This file is autogenerated. Do not edit it by hand. Regenerate it with:
#   srb rbi gems

# typed: true
#
# If you would like to make changes to this file, great! Please create the gem's shim here:
#
#   https://github.com/sorbet/sorbet-typed/new/master?filename=lib/pycall/all/pycall.rbi
#
# pycall-1.4.1

module PyCall
  def builtins; end
  def callable?(obj); end
  def check_isclass(pyptr); end
  def check_ismodule(pyptr); end
  def dir(obj); end
  def eval(expr, globals: nil, locals: nil); end
  def exec(code, globals: nil, locals: nil); end
  def getattr(*args); end
  def hasattr?(obj, name); end
  def import_module(name); end
  def iterable(obj); end
  def len(obj); end
  def same?(left, right); end
  def self.builtins; end
  def self.callable?(obj); end
  def self.check_isclass(pyptr); end
  def self.check_ismodule(pyptr); end
  def self.const_missing(name); end
  def self.dir(obj); end
  def self.eval(expr, globals: nil, locals: nil); end
  def self.exec(code, globals: nil, locals: nil); end
  def self.getattr(*args); end
  def self.hasattr?(obj, name); end
  def self.import_module(name); end
  def self.init(python = nil); end
  def self.iterable(obj); end
  def self.len(obj); end
  def self.same?(left, right); end
  def self.sys; end
  def self.tuple(iterable = nil); end
  def self.with(ctx); end
  def self.wrap_class(pytypeptr); end
  def self.wrap_module(pymodptr); end
  def sys; end
  def tuple(iterable = nil); end
  def with(ctx); end
  def wrap_class(pytypeptr); end
  def wrap_module(pymodptr); end
end
module PyCall::Version
end
class PyCall::Error < StandardError
end
class PyCall::PythonNotFound < PyCall::Error
end
class PyCall::LibPythonFunctionNotFound < PyCall::Error
end
module PyCall::LibPython
  def self.const_missing(name); end
  def self.handle; end
end
module PyCall::LibPython::Finder
  def self.apple?; end
  def self.candidate_names(python_config); end
  def self.candidate_paths(python_config); end
  def self.debug?; end
  def self.debug_report(message); end
  def self.dlopen(libname); end
  def self.find_libpython(python = nil); end
  def self.find_python_config(python = nil); end
  def self.investigate_python_config(python); end
  def self.make_libpaths(python_config); end
  def self.normalize_path(path, suffix, apple_p = nil); end
  def self.python_investigator_py; end
  def self.remove_suffix_apple(path); end
  def self.windows?; end
end
class PyCall::PyError < PyCall::Error
  def format_traceback; end
  def initialize(type, value, traceback); end
  def to_s; end
  def traceback; end
  def type; end
  def value; end
end
class PyCall::WrapperObjectCache
  def check_wrapper_object(wrapper_object); end
  def initialize(*restricted_pytypes); end
  def lookup(pyptr); end
  def self.get_key(pyptr); end
end
module PyCall::PyObjectWrapper
  def !=(other); end
  def <(other); end
  def <=(other); end
  def ==(other); end
  def >(other); end
  def >=(other); end
  def [](*key); end
  def []=(*key, value); end
  def __pyptr__; end
  def call(*args); end
  def coerce(other); end
  def dup; end
  def inspect; end
  def kind_of?(cls); end
  def method_missing(name, *args); end
  def respond_to_missing?(name, include_private); end
  def self.extend_object(obj); end
  def to_f; end
  def to_i; end
  def to_s; end
end
class PyCall::PyObjectWrapper::SwappedOperationAdapter
  def %(other); end
  def &(other); end
  def *(other); end
  def **(other); end
  def +(other); end
  def -(other); end
  def /(other); end
  def <<(other); end
  def >>(other); end
  def ^(other); end
  def initialize(obj); end
  def obj; end
  def |(other); end
end
module PyCall::PyTypeObjectWrapper
  def <(other); end
  def ===(other); end
  def inherited(subclass); end
  def new(*args); end
  def register_python_type_mapping; end
  def self.extend_object(cls); end
  def wrap_pyptr(pyptr); end
  include PyCall::PyObjectWrapper
end
class PyCall::WrapperClassCache < PyCall::WrapperObjectCache
  def check_wrapper_object(wrapper_object); end
  def initialize; end
  def self.instance; end
end
module PyCall::PyModuleWrapper
  def [](*args); end
  include PyCall::PyObjectWrapper
end
class PyCall::WrapperModuleCache < PyCall::WrapperObjectCache
  def check_wrapper_object(wrapper_object); end
  def initialize; end
  def self.instance; end
end
class PyCall::IterableWrapper
  def check_iterable(obj); end
  def each; end
  def initialize(obj); end
  include Enumerable
end