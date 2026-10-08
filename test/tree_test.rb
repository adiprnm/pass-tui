# frozen_string_literal: true
require_relative 'test_helper'

puts 'Tree'

test 'folder_paths lists every folder' do
  tree = PassTui::Tree.new(%w[a/q x/y/z x/y/w b/c])
  assert_equal %w[a b x x/y], tree.folder_paths.sort
end

test 'rows show only top-level folders when all are collapsed' do
  tree = PassTui::Tree.new(%w[web/a web/b db])
  rows = tree.rows(collapsed: tree.folder_paths)
  assert_equal %w[web db], rows.map { |row| row.node.name }
  assert_equal [true, false], rows.map { |row| row.node.folder? }
end

test 'expanding a folder reveals its children one level at a time' do
  tree = PassTui::Tree.new(%w[web/a web/sub/b])
  collapsed = tree.folder_paths - ['web']
  names = tree.rows(collapsed: collapsed).map { |row| row.node.name }
  assert_includes names, 'web'
  assert_includes names, 'a'
  assert_includes names, 'sub'
  refute names.include?('b'), 'the nested folder stays collapsed'
end

test 'a filter flattens the matching leaves' do
  tree = PassTui::Tree.new(%w[web/a web/sub/b db])
  rows = tree.rows(collapsed: tree.folder_paths, filter: 'sub')
  assert_equal ['web/sub/b'], rows.map { |row| row.node.path }
  assert_equal 0, rows.first.depth
end

test 'count counts the leaves under a folder' do
  tree = PassTui::Tree.new(%w[web/a web/sub/b db])
  web = tree.root.children.find { |child| child.name == 'web' }
  assert_equal 2, tree.count(web)
  assert_equal 3, tree.count(tree.root)
end

test 'folders sort before leaves in a folder' do
  tree = PassTui::Tree.new(%w[top/z-leaf top/a-folder/x top/m-folder/y])
  names = tree.root.children.first.children.map(&:name)
  assert_equal %w[a-folder m-folder z-leaf], names
end
