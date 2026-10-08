# frozen_string_literal: true
#
# Runs every test/*_test.rb in one process:  ruby test/run.rb
Dir[File.expand_path('*_test.rb', __dir__)].sort.each { |file| require file }
