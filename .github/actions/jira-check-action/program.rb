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
$stdout.printf("------------------\n")
$stdout.flush

results = event_data["commits"].select do |commit|
  if commit["message"].include?("JIRA")
    $stdout.printf("Found the word 'JIRA' in commit message!\n")
  else
    $stdout.printf("Did not find the word 'JIRA' in commit message.\n")
  end
end

results.each { |r| $stdout.print r }
$stdout.flush
