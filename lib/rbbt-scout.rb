$LOAD_PATH.unshift File.join(__dir__, '../modules/rbbt-util/lib')
module Rbbt
  extend Resource
  self.pkgdir = 'rbbt'
end
