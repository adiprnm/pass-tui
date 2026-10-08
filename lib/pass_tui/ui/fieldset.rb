# frozen_string_literal: true
#
# Widgets::Fieldset -- a field wrapped the way HTML wraps an input:
# a bordered box whose *legend* names the field, with an optional hint on
# the right of the legend (the key that acts on it).
#
#   Fieldset.build(title: 'Password', lines: ['••••••'], hint: 'r reveal')
#
#   ╭ Password ─────────────────────── r reveal ─╮
#   │ ••••••                                     │
#   ╰────────────────────────────────────────────╯
#
# It is a thin factory over Layout::Box (which already places a title on the
# top border), so it composes with the rest of the toolkit.

require 'tui'

module PassTui
  module Widgets
    module Fieldset
      module_function

      def build(title:, lines:, hint: nil, legend: :legend, border: :field_border,
                value_style: :value, hint_style: :hint)
        body = TUI::Layout::Stack.new(direction: :vertical)
        lines.each do |line|
          body.add(TUI::Label.new(" #{line}", style: value_style), size: TUI.fixed(1))
        end

        box = TUI::Layout::Box.new(
          title: title.to_s,
          title_right: hint && " #{hint} ",
          border_style: border,
          title_style: legend,
          title_right_style: hint_style,
          highlight: false
        )
        box.add(body)
        box
      end
    end
  end
end
