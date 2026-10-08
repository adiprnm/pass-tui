# frozen_string_literal: true
#
# PassTui -- a terminal UI for the standard unix password manager, built on
# the ruby-tui toolkit.
#
#   require 'pass_tui'
#   PassTui::UI.new.run

require 'tui'

require_relative 'pass_tui/version'
require_relative 'pass_tui/theme'
require_relative 'pass_tui/config'
require_relative 'pass_tui/entry'
require_relative 'pass_tui/tree'
require_relative 'pass_tui/shell'
require_relative 'pass_tui/store'
require_relative 'pass_tui/clipboard'
require_relative 'pass_tui/editing'

require_relative 'pass_tui/ui/tree_view'
require_relative 'pass_tui/ui/fieldset'
require_relative 'pass_tui/ui/app'

module PassTui
end
