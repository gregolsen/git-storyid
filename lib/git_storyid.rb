require "readline"
require "optparse"
require "pivotal_tracker"
require "yaml"
require "open3"

class GitStoryid

  def self.run(*args)
    new(*args).run
  end

  def initialize(*arguments)
    parser = OptionParser.new do |opts|
      opts.banner = "Do git commit with information from pivotal story"
      opts.on("-m [MESSAGE]", "Add addional MESSAGE to comit") do |message|
        @message = message
      end
    end
    parser.parse!(arguments)

    unless arguments.empty?
      @stories = arguments.map do |argument|
        Configuration.project.stories.find(argument) 
      end
    end
  end

  def all_stories
    @all_stories ||= Configuration.project.stories.all( 
      :owner => Configuration.me,
      :state => %w(started finished delivered),
      :limit => 30
    )
  end

  def readline_stories_if_not_present
    return if @stories
    if all_stories.empty?
      quit "No stories started and owned by you."
    end
    all_stories.each_with_index do |story, index|
      puts "[#{index + 1}] #{story.name}"
    end
    puts ""
    @stories  = Readline.readline("Indexes(csv): ", true).split(/\s*,\s*/).reject do |string|
      string == ""
    end.map do |string|
      index = string.to_i
      all_stories[index - 1] || (quit("Story index #{index} not found."))
    end
  end

  def quit(message)
    puts message
    exit 1
  end

  def run
    if execute("git", "diff", "--staged").empty?
      quit "No changes staged to commit."
    end

    readline_stories_if_not_present

    message = ("[#{@stories.map { |s| "\##{s.id}"}.join(", ")}]").rjust 12
    message += ' '
    if @message && !@message.empty?
      message += @message.to_s + "\n\n"
    end
    message += @stories.map {|s| "Feature: " + s.name.strip}.join("\n\n")
    puts execute("git", "commit", "-m", message)
  end

  def execute(*args)
    Open3.popen3(*args) {|i, o| return o.read }
  end



  module Configuration
    class << self
    def read
      return if @loaded
      load_config
      ensure_full_config
      setup_api_client
      @loaded = true
    end

    def load_config
      @config = load_config_from(global_config_path)
      @project_config = load_config_from(project_config_path)
      @config.merge!(@project_config)
    end

    def setup_api_client
      PivotalTracker::Client.token = @config['api_token']
      PivotalTracker::Client.use_ssl = @config['use_ssl'] ? @config['use_ssl'] : false
    end

    def ensure_full_config
      changed = false
      {
        "api_token" => "Api token (https://www.pivotaltracker.com/profile)",
        "use_ssl" => "Use SSL (y/n)",
        "me" => "Your pivotal initials (e.g. BG)",
        "project_id" => "Project ID"
      }.each do |key, label|
        if @config[key].nil?
          changed = true
          value = Readline.readline("#{label}: ", true) 
          @project_config[key]  = format_config_value(value)
        end
      end
      if changed
        File.open("./.pivotalrc", "w") do |file|
          file.write YAML.dump(@project_config)
        end
        @config.merge!(@project_config)
        puts "Writing config to .pivotalrc"
      end
    end

    def format_config_value(value)
      case value
      when "y"
        true
      when "n"
        false
      else
        value
      end
    end

    def load_config_from(path)
      return {} unless path
      file = File.join path,'.pivotalrc'
      if File.exists?(file)
        YAML.load(File.read(file)) || {}
      else 
        {}
      end
    end

    def project
      read
      @project ||= PivotalTracker::Project.find(@config['project_id'])
    end

    def me
      read
      @me ||= @config['me']
    end

    def global_config_path
      @global_config_path ||= File.expand_path('~')
    end

    def project_config_path
      @project_config_path ||= find_project_config
    end


    private

    def find_project_config
      dirs = File.split(Dir.pwd)
      until dirs.empty? || File.exists?(File.join(dirs, '.pivotalrc'))
        dirs.pop
      end
      if dirs.empty? || File.join(dirs, '.pivotalrc')==global_config_path
        nil
      else
        File.join(dirs)
      end
    end
    end
  end

  class Error < StandardError
  end
end
