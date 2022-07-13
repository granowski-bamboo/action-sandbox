#!ruby

require 'uri'
require 'net/http'

require 'json'
require 'yaml'

# for debugging, drop the environment vars of the ruby process so we can see what to expect
$stdout.printf("--- ENVIRONMENT ---\n")
ENV.each { |k,v| $stdout.printf("#{k}=#{v}\n") }
$stdout.printf("-------------------\n")

file_data = File.read(ENV['GITHUB_EVENT_PATH'])
event_data = JSON.parse(file_data)

$stdout.printf(event_data)
