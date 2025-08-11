# Essential Development Commands

## Testing Commands
```bash
# Setup test environment
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:ai_helper:setup_scm

# Run all tests
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper
```

## Database Migration
```bash
# Run plugin migrations (production)
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

## Vector Search Setup (Optional - requires Qdrant)
```bash
# Generate vector index
bundle exec rake redmine:plugins:ai_helper:vector:generate RAILS_ENV=production

# Register data in vector database  
bundle exec rake redmine:plugins:ai_helper:vector:regist RAILS_ENV=production

# Destroy vector data
bundle exec rake redmine:plugins:ai_helper:vector:destroy RAILS_ENV=production
```

## Installation Commands
```bash
# Basic installation (run from Redmine root)
cd {REDMINE_ROOT}/plugins/
git clone https://github.com/haru/redmine_ai_helper.git
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

## Development Workflow
1. Make code changes
2. Run tests: `bundle exec rake redmine:plugins:test NAME=redmine_ai_helper`
3. Check test coverage in `coverage/` directory
4. Commit changes (no Claude Code mentions in commit messages)

## System Utilities (Linux)
Standard Linux commands available: `git`, `ls`, `cd`, `grep`, `find`, `rg`, etc.