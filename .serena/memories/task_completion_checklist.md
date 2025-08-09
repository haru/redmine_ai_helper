# Task Completion Checklist

## When completing any development task:

### 1. Code Quality
- [ ] Follow Ruby on Rails conventions
- [ ] Use proper logging (ai_helper_logger, not Rails.logger)
- [ ] Write comments in English
- [ ] For JavaScript: use vanilla JS, no jQuery, use let/const

### 2. Testing Requirements
- [ ] Add tests for any new features implemented
- [ ] Use "shoulda" testing framework (not rspec)
- [ ] Avoid mocks unless connecting to external servers
- [ ] Run full test suite: `bundle exec rake redmine:plugins:test NAME=redmine_ai_helper`
- [ ] Verify test coverage is 95% or higher (check `coverage/` directory)
- [ ] Ensure all tests pass

### 3. Database Changes
- [ ] If database changes made, run: `bundle exec rake redmine:plugins:migrate RAILS_ENV=test`
- [ ] Run: `bundle exec rake redmine:plugins:ai_helper:setup_scm` if SCM-related changes

### 4. CSS/UI Changes
- [ ] Use Redmine's existing CSS classes and design system
- [ ] Use `.box` class for containers
- [ ] No custom colors or fonts
- [ ] Maintain visual consistency with Redmine interface

### 5. Pre-commit Verification
- [ ] All tests passing
- [ ] Test coverage maintained at 95%+
- [ ] No linting errors
- [ ] Code follows established patterns

### 6. Commit Guidelines
- [ ] Write commit message in plain English
- [ ] Do NOT mention Claude Code in commit messages
- [ ] Commit message describes the change clearly

## Commands to Run Before Marking Task Complete
```bash
# Essential test command
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper

# If database migrations were added
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:ai_helper:setup_scm
```