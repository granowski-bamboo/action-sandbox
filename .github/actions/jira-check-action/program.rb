#!ruby

require 'uri'
require 'net/http'

require 'json'
require 'yaml'

# for debugging, drop the environment vars of the ruby process so we can see what to expect
$stdout.printf("--- ENVIRONMENT ---\n")
ENV.each { |k,v| $stdout.printf("#{k}=#{v}\n") }
$stdout.printf("-------------------\n")
$stdout.flush

file_data = File.read(ENV['GITHUB_EVENT_PATH'])
event_data = JSON.parse(file_data)

$stdout.printf("--- EVENT DATA ---\n")
$stdout.printf(event_data.to_json)
$stdout.printf("\n")
$stdout.printf("------------------\n")
$stdout.flush

jira_keys_collection = []

results = event_data["commits"].each do |commit|
  # reg = Regexp.new("[a-zA-Z]+-{1}\d+", Regexp::IGNORECASE | Regexp::MULTILINE)
  reg = Regexp.new("[a-zA-Z]+-{1}\d+")
  md = reg.match(commit["message"])
  captures = md.to_a
  if captures.size.positive?
    $stdout.printf("Commit #{commit["id"]} has #{captures.length} Jira key pattern matches\n")
    $stdout.flush
    captures.each do |cap|
      match_text = cap
      jira_keys_collection.push(match_text)
    end
  else
    $stdout.printf("Commit failed workflow, missing Jira keys -> #{commit["id"]}\n")
    $stdout.printf("No Jira keys were referenced in the commit message, failed workflow!\n")
    $stdout.flush
    return 1
  end

  $stdout.printf("Found text that matches jira keys below\n")
  $stdout.printf("---------------------------------------\n")
  jira_keys_collection.each do |jk|
    $stdout.printf("#{jk}\n")
  end
  $stdout.printf("---------------------------------------\n")
  $stdout.flush
end

results.each { |r| $stdout.print r }
$stdout.flush
