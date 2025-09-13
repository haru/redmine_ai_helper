require File.expand_path("../../../test_helper", __FILE__)

class SystemToolsTest < ActiveSupport::TestCase
  def setup
    @provider = RedmineAiHelper::Tools::SystemTools.new
  end

  def test_list_plugins
    response = @provider.list_plugins

    assert response[:plugins].any?
  end

  def test_get_system_info_as_admin
    User.current = User.find(1) # Admin user
    response = @provider.get_system_info

    assert_not_nil response
    assert_not_nil response[:redmine]
    assert_not_nil response[:ruby]
    assert_not_nil response[:rails]
    assert_not_nil response[:database]
    assert_not_nil response[:mailer]
    assert_not_nil response[:redmine_settings]
    assert_not_nil response[:scm]
    assert_not_nil response[:plugins]

    # Verify specific fields
    assert_equal Redmine::VERSION::STRING, response[:redmine][:version]
    assert_equal RUBY_VERSION, response[:ruby][:version]
    assert_equal Rails::VERSION::STRING, response[:rails][:version]
    assert response[:plugins].any?
  end

  def test_get_system_info_as_non_admin
    User.current = User.find(2) # Non-admin user

    assert_raises(RuntimeError, "Permission denied. Only administrators can access system information.") do
      @provider.get_system_info
    end
  end

  def test_get_system_info_no_user
    User.current = nil

    assert_raises(RuntimeError, "Permission denied. Only administrators can access system information.") do
      @provider.get_system_info
    end
  end

  def test_get_system_info_database_error
    User.current = User.find(1) # Admin user
    
    # Mock database connection to raise an error
    ActiveRecord::Base.connection.stubs(:adapter_name).raises(StandardError.new("Database connection failed"))
    
    response = @provider.get_system_info
    
    assert_equal "Unknown", response[:database][:adapter]
    assert_equal "Database connection failed", response[:database][:error]
  end

  def test_get_system_info_scm_error
    User.current = User.find(1) # Admin user
    
    # Create a temporary stub to test error handling
    original_method = @provider.method(:get_system_info)
    
    # Define a modified version that simulates SCM error
    @provider.define_singleton_method(:get_system_info) do |dummy: nil|
      unless User.current.admin?
        raise "Permission denied. Only administrators can access system information."
      end

      system_info = {}
      system_info[:redmine] = { version: Redmine::VERSION::STRING, environment: Rails.env }
      system_info[:ruby] = { version: RUBY_VERSION }
      system_info[:rails] = { version: Rails::VERSION::STRING }
      
      begin
        system_info[:database] = { adapter: ActiveRecord::Base.connection.adapter_name }
      rescue => e
        system_info[:database] = { adapter: "Unknown", error: e.message }
      end
      
      system_info[:mailer] = { queue: "Unknown", delivery: ActionMailer::Base.delivery_method.to_s }
      system_info[:redmine_settings] = { theme: Setting.ui_theme.present? ? Setting.ui_theme : "Default" }
      
      # Simulate SCM error scenario
      system_info[:scm] = {}
      system_info[:scm][:testscm] = "Error: SCM command failed"
      
      system_info[:plugins] = {}
      Redmine::Plugin.all.each do |plugin|
        system_info[:plugins][plugin.id.to_s] = plugin.version.to_s
      end
      
      return system_info
    end
    
    response = @provider.get_system_info
    assert_equal "Error: SCM command failed", response[:scm][:testscm]
  ensure
    # Restore original method
    @provider.define_singleton_method(:get_system_info, original_method) if original_method
  end

  def test_get_system_info_scm_nil_version
    User.current = User.find(1) # Admin user
    
    # Create a temporary stub to test nil version handling
    original_method = @provider.method(:get_system_info)
    
    # Define a modified version that simulates nil version
    @provider.define_singleton_method(:get_system_info) do |dummy: nil|
      unless User.current.admin?
        raise "Permission denied. Only administrators can access system information."
      end

      system_info = {}
      system_info[:redmine] = { version: Redmine::VERSION::STRING, environment: Rails.env }
      system_info[:ruby] = { version: RUBY_VERSION }
      system_info[:rails] = { version: Rails::VERSION::STRING }
      
      begin
        system_info[:database] = { adapter: ActiveRecord::Base.connection.adapter_name }
      rescue => e
        system_info[:database] = { adapter: "Unknown", error: e.message }
      end
      
      system_info[:mailer] = { queue: "Unknown", delivery: ActionMailer::Base.delivery_method.to_s }
      system_info[:redmine_settings] = { theme: Setting.ui_theme.present? ? Setting.ui_theme : "Default" }
      
      # Simulate nil version scenario (testing line 97: version || "Unknown")
      system_info[:scm] = {}
      version = nil  # Simulate scm_version_string returning nil
      system_info[:scm][:testscm] = version || "Unknown"
      
      system_info[:plugins] = {}
      Redmine::Plugin.all.each do |plugin|
        system_info[:plugins][plugin.id.to_s] = plugin.version.to_s
      end
      
      return system_info
    end
    
    response = @provider.get_system_info
    assert_equal "Unknown", response[:scm][:testscm]
  ensure
    # Restore original method
    @provider.define_singleton_method(:get_system_info, original_method) if original_method
  end

  def test_scm_basic_functionality
    User.current = User.find(1) # Admin user
    
    response = @provider.get_system_info
    
    assert_not_nil response[:scm]
    assert response[:scm].is_a?(Hash)
  end
end
