# frozen_string_literal: true
#
# Tree -- turns a flat list of entry names into a folder/file tree and
# flattens it back into the rows the TreeView draws.
#
#   tree = PassTui::Tree.new(%w[web/example.com web/foo db])
#   tree.rows(collapsed: tree.folder_paths)   # folders only
#   tree.rows(collapsed: [], filter: 'foo')   # flat matches
#
# A Row carries the node, its indentation depth and whether a folder is
# currently expanded, so the view never has to know about the model.

require 'set'

module PassTui
  class Tree
    Node = Struct.new(:name, :path, :children, :folder) do
      def folder?
        folder
      end

      def leaf?
        !folder
      end
    end

    Row = Struct.new(:node, :depth, :expanded)

    attr_reader :root

    def initialize(entries = [])
      @root = Node.new('', '', [], true)
      entries.each { |name| insert(name) }
      sort_children(@root)
    end

    def insert(name)
      parts = name.to_s.split('/').reject(&:empty?)
      return self if parts.empty?

      current = @root
      parts.each_with_index do |part, index|
        leaf = index == parts.length - 1
        child = current.children.find { |candidate| candidate.name == part }
        unless child
          path = current.path.empty? ? part : "#{current.path}/#{part}"
          child = Node.new(part, path, [], !leaf)
          current.children << child
        end
        current = child
      end
      self
    end

    # Every folder path, deepest included; the UI starts with all of them
    # collapsed.
    def folder_paths
      paths = []
      collect_folder_paths(@root, paths)
      paths
    end

    def rows(collapsed: [], filter: nil)
      needle = filter.to_s.strip.downcase
      return flattened(collapsed) if needle.empty?

      leaves.select { |node| node.path.downcase.include?(needle) }
            .map { |node| Row.new(node, 0, false) }
    end

    def leaves
      acc = []
      collect_leaves(@root, acc)
      acc
    end

    def count(node)
      return 0 if node.nil?
      return 1 if node.leaf?

      node.children.sum { |child| count(child) }
    end

    private

    def flattened(collapsed)
      out = []
      flatten(@root.children, 0, collapsed, out)
      out
    end

    def sort_children(node)
      node.children.sort_by! { |child| [child.folder? ? 0 : 1, child.name.downcase] }
      node.children.each { |child| sort_children(child) }
    end

    def flatten(nodes, depth, collapsed, out)
      nodes.each do |node|
        expanded = node.folder? && !collapsed.include?(node.path)
        out << Row.new(node, depth, expanded)
        flatten(node.children, depth + 1, collapsed, out) if expanded
      end
    end

    def collect_folder_paths(node, acc)
      node.children.each do |child|
        next unless child.folder?

        acc << child.path
        collect_folder_paths(child, acc)
      end
    end

    def collect_leaves(node, acc)
      node.children.each do |child|
        if child.leaf?
          acc << child
        else
          collect_leaves(child, acc)
        end
      end
    end
  end
end
