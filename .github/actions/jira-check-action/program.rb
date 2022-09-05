#!ruby

require 'uri'
require 'net/http'
require 'json'
require 'yaml'
require 'base64'

if ENV['JIRA_USER_NAME'].nil? || ENV['JIRA_USER_NAME'].empty?
  $stdout.printf('To run this workflow, the JIRA_USER_NAME action secret need be set.')
  return 1 # note: any non-zero value is a failed status for github actions
end

if ENV['JIRA_API_KEY'].nil? || ENV['JIRA_API_KEY'].empty?
  $stdout.printf('To run this workflow, the JIRA_API_KEY action secret need be set.')
  return 1 # (non zero ->) failed
end

# for debugging, drop the environment vars of the ruby process so we can see what to expect
# $stdout.printf("--- ENVIRONMENT ---\n")
# ENV.each { |k,v| $stdout.printf("#{k}=#{v}\n") }
# $stdout.printf("-------------------\n\n")
# $stdout.flush

RELEASE_PR_TITLE_REGEX = Regexp.new('[Rr][Ee][Ll][Ee][Aa][Ss][Ee]\/\d{4}([-](a|b|c))?')
COMMIT_MESSAGE_REGEX = /[a-zA-Z]+-\d+/.freeze
BAMBOO_JIRA_ORG = 'hbuco'.freeze

class PullRequestEventFileReader
  attr_reader :data

  def initialize(file)
    file_data = File.read(file)

    @data = JSON.parse(file_data)
  end

  def action
    @data['action']
  end
end

class PushEventFileReader
  attr_reader :data

  def initialize(file)
    file_data = File.read(file)

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
      @commit['id']
    end

    def message_is_valid?
      return @message_is_valid unless @message_is_valid.nil?

      # initial state, assume the commit is valid
      @message_is_valid = true

      matches = @commit['message'].scan(COMMIT_MESSAGE_REGEX)

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
    attr_reader :pr_title_is_valid, :jira_keys, :id

    def initialize(pr)
      super()

      @pr = pr
      @pr_title_is_valid = nil
      @jira_keys = []
    end

    def title
      @pr['title']
    end

    def pr_title_is_valid?
      return @pr_title_is_valid unless @pr_title_is_valid.nil?

      # initial state, assume the commit is valid
      @pr_title_is_valid = true

      matches = @pr['title'].scan(COMMIT_MESSAGE_REGEX)
      matches_release = @pr['title'].scan(RELEASE_PR_TITLE_REGEX)

      if !matches.nil? && matches.length.positive?
        matches.each do |cap|
          match_text = cap
          @jira_keys.push(match_text)
        end
      else
        if !matches_release.nil? && matches_release.length.positive?
          $stdout.printf("The PR title matches one of a release 'release/YYMM-[abc]' so it is valid.")
          return @pr_title_is_valid
        end

        $stdout.printf('The PR title does not contain a JIRA key or is not a release, so it is not a valid PR title.')

        @pr_title_is_valid = false
      end

      @pr_title_is_valid
    end
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
    jusername = ENV['JIRA_USER_NAME']
    jtoken = ENV['JIRA_API_TOKEN']
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

      case response.code
      when '404'
        $stdout.printf("Jira key '#{jkey}' does not exist in Jira.\n")

        # todo -> validate the key is a "BLUE-0" key
        #
        r = Result.new(valid: false, status_code: :not_found, body: nil, jira_key: jkey)
      when '200'
        $stdout.printf("Found key '#{jkey}' in Jira\n")
        jira_json = puts response.read_body
        r = Result.new(valid: true, status_code: :ok, body: jira_json, jira_key: jkey)
      else
        $stdout.printf("An issue occurred trying to query for Jira key '#{jkey}' -> http status code '#{response.code}'\n")
        r = Result.new(valid: false, status_code: response.code, body: nil, jira_key: jkey)
      end
      @results.push(r)
    end
  end
end

PR_ACTION_MESSAGE = {
  'opened': 'Processing a newly opened PR.',
  'reopened': 'Processing a previously created PR that is being reopened.',
  'edited': 'Processing a recently edited PR.',
  'ready_for_review': 'Processing a PR that was recently converted from a draft.'
}.freeze

jira_keys_collection = []

case ENV['GITHUB_EVENT_NAME']
when 'pull_request'
  ev = PullRequestEventFileReader.new(ENV['GITHUB_EVENT_PATH'])

  $stdout.printf("#{PR_ACTION_MESSAGE[ev.action]}\n")

  if ev.action == 'opened' ||
     ev.action == 'reopened' ||
     ev.action == 'edited' ||
     ev.action == 'ready_for_review' ||
     ev.action == 'synchronize'

    # $stdout.printf("--- EVENT DATA ---\n")
    # $stdout.printf(ev.data.to_json)
    # $stdout.printf("\n")
    # $stdout.printf("------------------\n\n")
    # $stdout.flush

    prv = Validators::PullRequestValidator.new(ev.data['pull_request'])

    result = prv.pr_title_is_valid?

    if result == false
      $stdout.printf("PR failed workflow, missing Jira keys in title.\n")
      $stdout.flush

      return ~0
    else
      $stdout.printf("PR has #{prv.jira_keys.length} Jira key pattern matches\n")
      $stdout.flush
    end

    # gather the jira keys for later validation
    prv.jira_keys.each do |key|
      jira_keys_collection.push(key)
    end
  else
    $stdout.printf("The action '#{ev.action}' is not processed for pull request events. Doing nothing.\n")
    return ~0
  end
when 'push'
  ev = PushEventFileReader.new(ENV['GITHUB_EVENT_PATH'])

  # $stdout.printf("--- EVENT DATA ---\n")
  # $stdout.printf(ev.data.to_json)
  # $stdout.printf("\n")
  # $stdout.printf("------------------\n\n")
  # $stdout.flush

  commits_failing_validation = []

  # ensure that each commit has a Jira key in it
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

    # gather jira keys for more later validation
    cv.jira_keys.each do |key|
      jira_keys_collection.push(key)
    end
  end

  $stdout.printf("Found text in commit messages that matches jira keys below\n")
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
else
  $stdout.printf("The event '#{ENV['GITHUB_EVENT_NAME']}' is not known for this action. Doing nothing.\n")
  return ~0
end

jv = JiraValidation.new(jira_keys_collection)

has_invalid_calls = jv.results.any? { |r| !r.valid }

if has_invalid_calls
  $stdout.printf('There are some invalid jira-key states for this PR/commit to be accept.')
  exit 1
end

exit 0
