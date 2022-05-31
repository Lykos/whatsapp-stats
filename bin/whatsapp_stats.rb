#!/usr/bin/ruby
# coding: utf-8

require 'time'

Message = Struct.new(:time, :author, :text, :type)
AuthorStats = Struct.new(:name, :text_bytes, :messages_by_type)

WHATSAPP_MESSAGE_REGEXP = /^(\d+\/\d+\/\d+, \d+:\d+) - ([^:]+?)(?:\: (.*)| changed the subject from ".*" to "(.*)")$/
SPECIAL_MESSAGE_REGEXP = /^(\d+\/\d+\/\d+, \d+:\d+) - (?:Messages to this group are now secured with end-to-end encryption\. Tap for more info\.|[^:]+? added .+|[^:]+? created group ".*")$/
TIME_FORMAT = "%d/%m/%Y, %R"
MEDIA_OMITTED_TEXT = "<Media omitted>"

# Check whether the given line starts a new message. This is not 100% accurate
# because people might write a message exactly in the same format as WhatsApp
# starts a new message, but it's good enough for practical purposes.
def starts_new_message(line)
  line =~ WHATSAPP_MESSAGE_REGEXP
end

# Parses a message into a format that we can work with and determines the type.
def parse_message(raw_message)
  raw_time, author, text, new_subject = raw_message.match(WHATSAPP_MESSAGE_REGEXP).captures
  if text == nil
    type = :change_name
    text = new_subject
  elsif text == MEDIA_OMITTED_TEXT
    type = :media
  else
    type = :text
  end
  time = DateTime.strptime(raw_time, TIME_FORMAT)
  Message.new(time, author, text, type)  
end

# Filters out special messages from WhatsApp that we want to ignore.
def is_special_message(line)
  line =~ SPECIAL_MESSAGE_REGEXP
end

# Total number of messages of one author.
def message_sum(author_stats)
  author_stats.messages_by_type.values.inject(0, :+)
end

if ARGV.length != 1
  warn "This script needs exactly one argument: The Whatsapp History file."
  exit(1)
end

file = ARGV[0]
messages = []
current_raw_message = ''

# Read and parse all message, but ignore special Whatsapp messages.
File.readlines(file).each do |line|
  if is_special_message(line)
    next
  end
  if !current_raw_message.empty? && starts_new_message(line)
    messages.push(parse_message(current_raw_message))
    current_raw_message = ''
  end
  current_raw_message += line
end
messages.push(parse_message(current_raw_message))

# Collect stats for each author.
author_stats = []
messages.group_by { |m| m.author }.each do |author, ms|
  stats = AuthorStats.new(author, 0, {})
  stats.messages_by_type.default = 0
  ms.each do |m|
    stats.messages_by_type[m.type] += 1
    if m.type == :text
      stats.text_bytes += m.text.length
    end
  end
  author_stats.push(stats)
end

# Print stats
author_stats.sort_by { |a| message_sum(a) }.reverse.each do |a|
  message_number_details = a.messages_by_type.collect { |t, n| "#{t}: #{n}" }.join(", ")
  puts "#{a.name} wrote #{message_sum(a)} messages (#{message_number_details}) whose text had a total of #{a.text_bytes} bytes."
end
