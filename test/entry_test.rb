# frozen_string_literal: true
require_relative 'test_helper'

puts 'Entry'

test 'parse reads the labelled username/password form' do
  entry = PassTui::Entry.parse('web/x', "username:carol\npassword:s3cret\n")
  assert_equal 's3cret', entry.password
  assert_equal 'carol', entry.user
  assert_equal [['username', 'carol']], entry.fields
  assert entry.notes.empty?
end

test 'the labelled form works with the lines in any order' do
  entry = PassTui::Entry.parse('x', "password:s3cret\nusername:carol\n")
  assert_equal 's3cret', entry.password
  assert_equal 'carol', entry.user
end

test 'a password with a colon is kept whole' do
  entry = PassTui::Entry.parse('x', "username:a\npassword:ht:tp://x\n")
  assert_equal 'ht:tp://x', entry.password
end

test 'an empty labelled password parses as empty' do
  entry = PassTui::Entry.parse('x', "username:a\npassword:\n")
  assert entry.empty_password?
  assert_equal 'a', entry.user
end

test 'parse splits password, fields and notes' do
  content = "hunter2\nuser: alice\nurl: https://example.com\nnotes here\n"
  entry = PassTui::Entry.parse('web/x', content)

  assert_equal 'hunter2', entry.password
  assert_equal 'alice', entry.user
  assert_equal 'https://example.com', entry.url
  assert_equal [['user', 'alice'], ['url', 'https://example.com']], entry.fields
  assert_equal ['notes here'], entry.notes
end

test 'a bare URL line is a note, not a field named https' do
  entry = PassTui::Entry.parse('x', "pw\nhttps://example.com\n")
  assert_equal [], entry.fields
  assert_includes entry.notes, 'https://example.com'
end

test 'user keys are recognised case-insensitively' do
  entry = PassTui::Entry.parse('x', "pw\nUsername: bob\n")
  assert_equal 'bob', entry.user
end

test 'masked password matches the length' do
  entry = PassTui::Entry.parse('x', "abcd\n")
  assert_equal '****', entry.masked_password
end

test 'an entry with only a password has no fields or notes' do
  entry = PassTui::Entry.parse('x', "only\n")
  assert_equal 'only', entry.password
  assert entry.fields.empty?
  assert entry.notes.empty?
end

test 'the field lookup trims the key' do
  entry = PassTui::Entry.parse('x', "pw\nuser : carol\n")
  assert_equal 'carol', entry.user
end
