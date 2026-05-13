# frozen_string_literal: true

# generate git repository for Redmine AI Helper tests
namespace :redmine do
  namespace :plugins do
    namespace :ai_helper do
      desc "Setup SCM for Redmine AI Helper tests"
      task setup_scm: :environment do
        plugin_dir = Rails.root.join("plugins/redmine_ai_helper").to_s
        scm_archive = "#{plugin_dir}/test/redmine_ai_helper_test_repo.git.tgz"
        puts scm_archive
        plugin_tmp = "#{plugin_dir}/tmp"
        puts plugin_tmp
        system("mkdir -p #{plugin_tmp}")
        Dir.chdir(plugin_tmp) do
          system("rm -rf redmine_ai_helper_test_repo.git")
          system("tar xvfz #{scm_archive}")
        end
      end
    end
  end
end
