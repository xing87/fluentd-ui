class Fluentd < ActiveRecord::Base
  validates :variant, inclusion: { in: proc { Fluentd.variants } }
  validates :log_file, presence: true
  validates :pid_file, presence: true
  validates :config_file, presence: true
  validate :validate_permissions

  before_validation :expand_paths
  after_save :ensure_default_config_file

  DEFAULT_CONF = <<-CONF.strip_heredoc
    <source>
      type forward
      port 24224
    </source>
    <source>
      type monitor_agent
      port 24220
    </source>
    <source>
      type http
      port 8888
    </source>
    <source>
      type debug_agent
      port 24230
    </source>

    <match debug.*>
      type stdout
    </match>
  CONF

  def self.variants
    %w(fluentd td-agent)
  end

  def fluentd?
    variant == "fluentd"
  end

  def td_agent?
    variant == "td-agent"
  end

  def agent
    klass = variant.underscore.camelize
    Agent.const_get(klass).new({
      :pid_file => pid_file,
      :log_file => log_file,
      :config_file => config_file,
    })
  end

  def load_settings_from_agent_default
    agent.class.default_options.each_pair do |key, value|
      send("#{key}=", value)
    end
  end

  def api
    Api::Http.new(api_endpoint)
  end

  def label
    "#{variant} ##{id}"
  end

  def expand_paths
    %w(pid_file log_file config_file).each do |column|
      path = send(column)
      next if path.blank?
      self.send("#{column}=", File.expand_path(path))
    end
  end

  def validate_permissions
    %w(pid_file log_file config_file).each do |column|
      check_permission(column)
    end
  end

  def check_permission(column)
    path = send(column)
    return if path.blank? # if empty, presence: true will catch it
    if File.exist?(path)
      if File.directory?(path)
        errors.add(column, :is_a_directory)
      end

      unless File.writable?(path)
        errors.add(column, :lack_write_permission)
      end
      unless File.readable?(path)
        errors.add(column, :lack_read_permission)
      end
    else
      unless File.writable?(File.dirname(path))
        errors.add(column, :lack_write_permission)
      end
    end
  end

  def ensure_default_config_file
    return true if File.size?(config_file)

    File.open(config_file, "w") do |f|
      f.write DEFAULT_CONF
    end
  end
end
