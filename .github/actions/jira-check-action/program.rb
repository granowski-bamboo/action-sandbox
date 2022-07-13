#!ruby

# for debugging, drop the environment vars of the ruby process so we can see what to expect
$stdout.printf("--- ENVIRONMENT ---\n")
ENV.each { |k,v| $stdout.printf("#{k}=#{v}\n") }
$stdout.printf("-------------------\n")

require 'uri'
require 'net/http'

require 'json'
require 'yaml'

event_data = JSON.parse(ENV['GITHUB_EVENT_PATH'])

$stdout.printf(event_data.to_yaml)
