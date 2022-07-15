#!ruby

require 'uri'
require 'net/http'
require 'json'
require 'yaml'
require 'base64'


# for debugging, drop the environment vars of the ruby process so we can see what to expect
$stdout.printf("--- ENVIRONMENT ---\n")
ENV.each { |k,v| $stdout.printf("#{k}=#{v}\n") }
$stdout.printf("-------------------\n\n")
$stdout.flush


COMMIT_MESSAGE_REGEX = /[a-zA-Z]+-\d+/.freeze
BAMBOO_JIRA_ORG = "hbuco".freeze

class PullRequestEventFileReader
  attr_reader :data

  def initialize(file)
    file_data = File.read(file || '/Users/dgranowski/Repositories/action-sandbox/.github/actions/jira-check-action/sample-event.json')

    @data = JSON.parse(file_data)
  end

  def action
    @data['action']
  end
end

class PushEventFileReader
  attr_reader :data

  def initialize(file)
    file_data = File.read(file || '/Users/dgranowski/Repositories/action-sandbox/.github/actions/jira-check-action/sample-event.json')

    @data = JSON.parse(file_data)
  end

  def commits
    @data['commits']
  end
end

module Validators
  class CommitValidator
    attr_reader :message_is_valid, :jira_keys, :id

    def initialize(commit)
      super()

      @commit = commit
      @message_is_valid = nil
      @jira_keys = []
    end

    def id
      @commit["id"]
    end

    def message_is_valid?
      return @message_is_valid unless @message_is_valid.nil?

      # initial state, assume the commit is valid
      @message_is_valid = true

      matches = @commit["message"].scan(COMMIT_MESSAGE_REGEX)

      if !matches.nil? && matches.length.positive?
        matches.each do |cap|
          match_text = cap
          @jira_keys.push(match_text)
        end
      else
        # commits_failing_validation.push(commit['id'])
        @message_is_valid = false
      end

      @message_is_valid
    end
  end

  class PullRequestValidator

  end
end

class JiraValidation
  attr_reader :keys, :results

  JIRA_ENDPOINT = "https://#{BAMBOO_JIRA_ORG}.atlassian.net/rest/api/3/issue/".freeze

  def initialize(keys)
    super()

    @keys = keys
    @results = []
    execute
  end

  class Result
    attr_reader :valid, :status_code, :body, :jira_key

    def initialize(valid: , status_code: , body: , jira_key:)
      super()

      @valid = valid
      @status_code = status_code
      @body = body
      @jira_key = jira_key
    end
  end

  def execute
    jusername = ENV['JIRA_USER_NAME'] || 'dgranowski@bamboohealth.com'
    jtoken = ENV['JIRA_API_TOKEN'] || 'h9DKOC2nZywbo0INmcKTC247'
    calculated_auth_header = Base64.encode64("#{jusername}:#{jtoken}").sub("\n", '').chomp!

    auth_header = "Basic #{calculated_auth_header}"

    @keys.each do |jkey|
      next if /[a-zA-Z]+-0+/.match?(jkey)

      url = URI("https://hbuco.atlassian.net/rest/api/3/issue/#{jkey}?fields=key,assignee,status,issuetype")

      https = Net::HTTP.new(url.host, url.port)
      https.use_ssl = true

      request = Net::HTTP::Get.new(url)
      request['Authorization'] = auth_header

      response = https.request(request)
      # @results.push(response)
      case response.code
      when '404'
        # $stdout.printf("Jira key '#{jkey}' does not exist in Jira.\n")
        r = Result.new(valid: false, status_code: :not_found, body: nil, jira_key: jkey)
      when '200'
        # $stdout.printf("Found key '#{jkey}' in Jira\n")
        jira_json = puts response.read_body
        r = Result.new(valid: true, status_code: :ok, body: jira_json, jira_key: jkey)
      else
        # $stdout.printf("An issue occurred trying to query for Jira key '#{jkey}' -> http status code '#{response.code}'\n")
        r = Result.new(valid: false, status_code: response.code, body: nil, jira_key: jkey)
      end
      @results.push(r)
    end
  end
end

case ENV['GITHUB_EVENT_NAME'] || 'push'
when 'pull_request'
  ev = PullRequestEventFileReader.new(ENV['GITHUB_EVENT_PATH'])

  if ev.action == 'opened' ||
     ev.action == 'reopened' ||
     ev.action == 'edited' ||
     ev.action == 'ready_for_review'
    # todo -> ev.changes[title], ev.changes[body] analysis ; these are during the edited action
    # todo -> pull the commits from the pull request (ev.pull_request.commits_url), do analysis on their messages
  end
  nil
when 'push'
  #
  # file_data = File.read('/Users/dgranowski/Repositories/action-sandbox/.github/actions/jira-check-action/sample-event.json')
  # event_data = JSON.parse(file_data)
  ev = PushEventFileReader.new(ENV['GITHUB_EVENT_PATH'])

  $stdout.printf("--- EVENT DATA ---\n")
  $stdout.printf(ev.data.to_json)
  $stdout.printf("\n")
  $stdout.printf("------------------\n\n")
  $stdout.flush

  jira_keys_collection = []
  commits_failing_validation = []

  ev.commits.each do |commit|
    cv = Validators::CommitValidator.new(commit)

    result = cv.message_is_valid?

    if result == false
      $stdout.printf("Commit failed workflow, missing Jira keys -> #{cv.id}\n")
      $stdout.printf("No Jira keys were referenced in the commit message, failed workflow!\n\n")
      $stdout.flush
    else
      $stdout.printf("Commit #{cv.id} has #{cv.jira_keys.length} Jira key pattern matches\n")
      $stdout.flush
    end

    cv.jira_keys.each do |key|
      jira_keys_collection.push(key)
    end
  end

  $stdout.printf("Found text that matches jira keys below\n")
  $stdout.printf("---------------------------------------\n")
  jira_keys_collection.each do |jk|
    $stdout.printf("#{jk}\n")
  end
  $stdout.printf("---------------------------------------\n\n")
  $stdout.flush

  $stdout.printf("Commits failing message pattern matching\n")
  $stdout.printf("----------------------------------------\n")
  commits_failing_validation.each do |commit_id|
    $stdout.printf("#{commit_id}\n")
  end
  $stdout.printf("----------------------------------------\n\n")

  jv = JiraValidation.new(jira_keys_collection)

  has_invalid_calls = jv.results.any? { |r| !r.valid }

  if has_invalid_calls
    return 1
  end

  return 0
end
