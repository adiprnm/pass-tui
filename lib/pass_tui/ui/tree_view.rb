# frozen_string_literal: true
#
# UI::TreeView -- the expandable folder/entry tree.
#
# It is a plain TUI::Component: the model hands it a list of Tree::Row
# objects and it draws them, keeps a cursor, scrolls, and emits events.
# Folder expansion is *not* its job -- it emits :expand / :collapse /
# :select and the application decides, because the application owns the
# collapsed set and rebuilds the rows.
#
#   view.set_rows(tree.rows(collapsed: collapsed))
#   view.on(:change)   { |node, index| ... }
#   view.on(:select)   { |node, index| ... }   # enter / space

require 'tui'

module PassTui
  module Widgets
    class TreeView < TUI::Component
      attr_reader :rows, :cursor, :scroll
      attr_accessor :filtering

      def initialize(rows: [], padding: 1, **opts)
        super(**opts)
        @rows = rows
        @cursor = 0
        @scroll = 0
        @padding = padding
        @filtering = false
      end

      def focusable?
        true
      end

      def set_rows(rows)
        @rows = rows
        @cursor = @cursor.clamp(0, [@rows.length - 1, 0].max)
        self
      end

      def selected_node
        row = @rows[@cursor]
        row && row.node
      end

      def selected_path
        node = selected_node
        node && node.path
      end

      def select(index, notify: true)
        return self if @rows.empty?

        target = index.clamp(0, @rows.length - 1)
        moved = target != @cursor
        @cursor = target
        emit(TUI::Events::CHANGE, selected_node, @cursor) if notify && moved
        self
      end

      def select_path(path, notify: true)
        index = @rows.index { |row| row.node.path == path }
        return self if index.nil?

        select(index, notify: notify)
      end

      def measure(max_w, max_h)
        width = @rows.map { |row| TUI::Text.width(row_text(row)) }.max.to_i
        [[width + (@padding * 2), max_w].min, [@rows.length, max_h].min]
      end

      def render(canvas)
        area = content_rect
        visible_h = area.h
        @scroll = TUI::Scroll.ensure_visible(@scroll, @cursor, visible_h)
        @scroll = TUI::Scroll.clamp(@scroll, @rows.length, visible_h)

        visible = [visible_h, @rows.length - @scroll].min
        visible = 0 if visible.negative?
        visible.times do |i|
          index = @scroll + i
          row = @rows[index]
          rect = TUI::Rect.new(area.x, area.y + i, area.w, 1)
          selected = index == @cursor
          if selected
            style = focused? ? :selection : :selection_dim
            # Highlight only what the row says (plus the marker and one
            # trailing cell), not the whole pane -- a folder row is short.
            width = TUI::Text.width(row_text(row)) + 2
            width = @rect.w if width > @rect.w
            canvas.fill(@rect.x, rect.y, width, 1, ' ', style)
            canvas.put(@rect.x, rect.y, '▌', :marker)
          end
          canvas.text(rect, row_text(row), selected ? style : row_style(row, false))
        end

        if area.right + 1 <= @rect.right
          TUI::Scroll.draw(canvas, TUI::Rect.new(area.right + 1, area.y, 1, area.h),
                           @rows.length, visible_h, @scroll)
        end
        self
      end

      def handle_key(key)
        case key.name
        when :up, 'k'    then select(@cursor - 1)
        when :down, 'j'  then select(@cursor + 1)
        when :home       then select(0)
        when :end        then select(@rows.length - 1)
        when :page_up    then select(@cursor - @rect.h)
        when :page_down  then select(@cursor + @rect.h)
        when :right, 'l' then emit(:expand, selected_node)
        when :left, 'h'  then emit(:collapse, selected_node)
        when :enter      then emit(TUI::Events::SELECT, selected_node, @cursor)
        else
          return false unless key.space?

          emit(TUI::Events::SELECT, selected_node, @cursor)
        end
        true
      end

      private

      def content_rect
        @padding.positive? ? @rect.inset(0, left: @padding, right: @padding) : @rect
      end

      def row_text(row)
        if @filtering && row.node.leaf?
          " #{row.node.path}"
        elsif row.node.folder?
          " #{indent(row.depth)}#{row.expanded ? '▾' : '▸'} #{row.node.name}/"
        else
          " #{indent(row.depth)}  #{row.node.name}"
        end
      end

      def indent(depth)
        '  ' * [depth, 0].max
      end

      def row_style(row, _selected)
        row.node.folder? ? :folder : :text
      end
    end
  end
end
